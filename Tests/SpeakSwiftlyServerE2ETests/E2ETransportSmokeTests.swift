import Foundation
import Testing

// MARK: - Transport Smoke Tests

extension ServerTransportE2ETests {
    @Test func `http transport boots the published runtime and retains a completed request`() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59600..<59700),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: false,
        )
        try server.start()
        defer { server.stop() }

        let client = E2EHTTPClient(baseURL: server.baseURL)
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let health = try await decode(
            E2EHealthSnapshot.self,
            from: client.request(path: "/healthz", method: "GET").data,
        )
        #expect(health.status == "ok")
        #expect(health.workerMode == "ready")
        #expect(health.workerReady)

        let readiness = try await decode(
            E2EReadinessSnapshot.self,
            from: client.request(path: "/readyz", method: "GET").data,
        )
        #expect(readiness.workerReady)

        let profileName = "http-smoke-profile"
        try await ServerE2E.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription,
        )
        try await ServerE2E.assertProfileIsVisible(using: client, profileName: profileName)

        let status = try await decode(
            E2EStatusSnapshot.self,
            from: client.request(path: "/runtime/host", method: "GET").data,
        )
        #expect(status.workerMode == "ready")
        #expect(status.cachedProfiles.contains { $0.profileName == profileName })
        #expect(status.transports.contains { $0.name == "http" && $0.state == "listening" })

        let jobID = try await ServerE2E.submitSpeechJob(
            using: client,
            text: ServerE2E.testingPlaybackText,
            profileName: profileName,
        )
        let terminalSnapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        ServerE2E.assertSpeechJobCompleted(terminalSnapshot, expectedJobID: jobID)

        let retainedSnapshot = try await decode(
            E2EJobSnapshot.self,
            from: client.request(path: "/requests/\(jobID)", method: "GET").data,
        )
        #expect(retainedSnapshot.requestID == jobID)
        #expect(retainedSnapshot.status == "completed")
        #expect(retainedSnapshot.terminalEvent?.ok == true)

        let retainedEvents = try await client.request(path: "/requests/\(jobID)/events", method: "GET")
        #expect(retainedEvents.statusCode == 200)
        #expect(retainedEvents.text.contains(#""event":"started""#))
        #expect(retainedEvents.text.contains(#""stage":"playback_finished""#))
        #expect(retainedEvents.text.contains(#""ok":true"#))
    }

    @Test func `mcp transport delivers a resource update and retains a completed request`() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59800..<59900),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: true,
        )
        try server.start()
        defer { server.stop() }

        let client = try await E2EMCPClient.connect(
            baseURL: server.baseURL,
            path: "/mcp",
            timeout: Self.e2eTimeout,
            server: server,
        )
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let runtimeOverview = try await Self.requireObjectPayload(
            from: client.readResourceJSON(uri: "speak://runtime/overview"),
        )
        let transports = try requireArray("transports", in: runtimeOverview)
        #expect(transports.contains {
            $0["name"] as? String == "mcp" && ($0["advertised_address"] as? String)?.contains("/mcp") == true
        })

        let eventStream = client.openEventStream()
        try await eventStream.start()
        defer { eventStream.stop() }

        try await client.subscribe(to: "speak://voices")

        let profileName = "mcp-smoke-profile"
        let createPayload = try await client.callTool(
            name: "create_voice_profile_from_description",
            arguments: [
                "profile_name": profileName,
                "vibe": "femme",
                "text": Self.testingProfileText,
                "voice_description": Self.testingProfileVoiceDescription,
            ],
        )
        let createJobID = try requireString("request_id", in: createPayload)
        #expect(createPayload["request_resource_uri"] as? String == "speak://requests/\(createJobID)")

        let profileNotification = try await eventStream.waitForNotification(timeout: .seconds(60)) {
            guard $0["method"] as? String == "notifications/resources/updated" else {
                return false
            }
            guard let params = $0["params"] as? [String: Any] else {
                return false
            }

            return params["uri"] as? String == "speak://voices"
        }
        let notificationParams = try requireDictionary("params", in: profileNotification)
        #expect(notificationParams["uri"] as? String == "speak://voices")

        _ = try await waitForTerminalJob(
            id: createJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )

        let profiles = try await requireProfiles(from: client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(profiles.contains { $0.profileName == profileName })

        let profileDetail = try await Self.requireObjectPayload(
            from: client.readResourceJSON(uri: "speak://voices/\(profileName)"),
        )
        #expect(profileDetail["profile_name"] as? String == profileName)

        let speechPayload = try await client.callTool(
            name: "generate_speech",
            arguments: [
                "text": ServerE2E.testingPlaybackText,
                "profile_name": profileName,
            ],
        )
        let speechJobID = try requireString("request_id", in: speechPayload)
        #expect(speechPayload["request_resource_uri"] as? String == "speak://requests/\(speechJobID)")

        let speechTerminal = try await waitForTerminalJob(
            id: speechJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        ServerE2E.assertSpeechJobCompleted(speechTerminal, expectedJobID: speechJobID)

        let retainedRequest = try await Self.requireObjectPayload(
            from: client.readResourceJSON(uri: "speak://requests/\(speechJobID)"),
        )
        #expect(retainedRequest["request_id"] as? String == speechJobID)
        #expect(retainedRequest["status"] as? String == "completed")

        try await client.unsubscribe(from: "speak://voices")
    }
}
