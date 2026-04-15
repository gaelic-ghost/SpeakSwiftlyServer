import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - MCP Playback Surface End-to-End Tests

extension ControlE2ETests {
    @Test func `mcp playback and voice mutation controls stay live and accurate`() async throws {
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

        let eventStream = client.openEventStream()
        try await eventStream.start()
        defer { eventStream.stop() }

        try await client.subscribe(to: "speak://voices")

        let createdProfileName = "mcp-control-profile"
        let createProfilePayload = try await client.callTool(
            name: "create_voice_profile_from_description",
            arguments: [
                "profile_name": createdProfileName,
                "vibe": "femme",
                "text": Self.testingProfileText,
                "voice_description": Self.testingProfileVoiceDescription,
            ],
        )
        let createProfileJobID = try requireString("request_id", in: createProfilePayload)
        _ = try await waitForTerminalJob(
            id: createProfileJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )

        let profileNotification = try await eventStream.waitForNotification(timeout: Duration.seconds(60)) {
            guard $0["method"] as? String == "notifications/resources/updated" else {
                return false
            }
            guard let params = $0["params"] as? [String: Any] else {
                return false
            }

            return params["uri"] as? String == "speak://voices"
        }
        let profileNotificationParams = try requireDictionary("params", in: profileNotification)
        #expect(profileNotificationParams["uri"] as? String == "speak://voices")

        let profilesPayload = try await requireProfiles(from: client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(profilesPayload.contains { $0.profileName == createdProfileName })

        let profileDetail = try await Self.requireObjectPayload(
            from: client.readResourceJSON(uri: "speak://voices/\(createdProfileName)"),
        )
        #expect(profileDetail["profile_name"] as? String == createdProfileName)

        let longPlaybackText = Self.operatorControlPlaybackText
        let firstSpeechJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": createdProfileName,
                ],
            ),
        )
        _ = try await Self.waitForMCPPlaybackState(
            using: client,
            timeout: .seconds(180),
            matching: { $0.state == "playing" && $0.activeRequest?.id == firstSpeechJobID },
        )
        let pausedPayload = try await Self.requireObjectPayload(from: client.callToolJSON(name: "pause_playback", arguments: [:]))
        let pausedPlayback = try requireDictionary("playback", in: pausedPayload)
        #expect(pausedPlayback["state"] as? String == "paused")
        let resumedPayload = try await Self.requireObjectPayload(from: client.callToolJSON(name: "resume_playback", arguments: [:]))
        let resumedPlayback = try requireDictionary("playback", in: resumedPayload)
        #expect(resumedPlayback["state"] as? String == "playing")

        let secondSpeechJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": createdProfileName,
                ],
            ),
        )
        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in queue.queue.contains { $0.id == secondSpeechJobID } },
        )
        let cancelledPayload = try await Self.requireObjectPayload(
            from: client.callToolJSON(
                name: "cancel_request",
                arguments: ["request_id": secondSpeechJobID],
            ),
        )
        #expect(cancelledPayload["cancelled_request_id"] as? String == secondSpeechJobID)

        let thirdSpeechJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": createdProfileName,
                ],
            ),
        )
        let fourthSpeechJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": createdProfileName,
                ],
            ),
        )
        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                let ids = Set(queue.queue.map(\.id))
                return ids.contains(thirdSpeechJobID) && ids.contains(fourthSpeechJobID)
            },
        )
        let clearedPayload = try await Self.requireObjectPayload(from: client.callToolJSON(name: "clear_playback_queue", arguments: [:]))
        #expect((clearedPayload["cleared_count"] as? Int) ?? 0 >= 2)

        _ = try await waitForTerminalJob(
            id: firstSpeechJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        let jobsResourcePayload = try await Self.requireArrayPayload(from: client.readResourceJSON(uri: "speak://requests"))
        #expect(jobsResourcePayload.contains { $0["request_id"] as? String == firstSpeechJobID })

        let removeProfilePayload = try await client.callTool(
            name: "delete_voice_profile",
            arguments: ["profile_name": createdProfileName],
        )
        let removeProfileJobID = try requireString("request_id", in: removeProfilePayload)
        _ = try await waitForTerminalJob(
            id: removeProfileJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        let remainingProfiles = try await requireProfiles(from: client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(remainingProfiles.contains { $0.profileName == createdProfileName } == false)

        try await client.unsubscribe(from: "speak://voices")
    }
}
