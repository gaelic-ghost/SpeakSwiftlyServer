import Foundation
import Testing

// MARK: - End-to-End Operator Control Surface Tests

extension ControlE2ETests {
    @Test func `http operator control surface covers read queue playback and removal flows`() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59600..<59700),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
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

        let profileName = "http-operator-control-profile"
        try await Self.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription,
        )

        let status = try await decode(
            E2EStatusSnapshot.self,
            from: client.request(path: "/runtime/host", method: "GET").data,
        )
        #expect(status.workerMode == "ready")
        #expect(status.cachedProfiles.contains { $0.profileName == profileName })
        #expect(status.transports.contains { $0.name == "http" && $0.state == "listening" })

        let longPlaybackText = Self.operatorControlPlaybackText
        let firstJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName,
        )

        let playingState = try await Self.waitForPlaybackState(
            using: client,
            timeout: .seconds(180),
            matching: { $0.state == "playing" && $0.activeRequest?.id == firstJobID },
        )
        #expect(playingState.activeRequest?.op == "generate_speech")

        let paused = try await decode(
            E2EPlaybackStateResponse.self,
            from: client.request(path: "/playback/pause", method: "POST").data,
        )
        #expect(paused.playback.state == "paused")
        #expect(paused.playback.activeRequest?.id == firstJobID)

        let resumed = try await decode(
            E2EPlaybackStateResponse.self,
            from: client.request(path: "/playback/resume", method: "POST").data,
        )
        #expect(resumed.playback.state == "playing")
        #expect(resumed.playback.activeRequest?.id == firstJobID)

        let secondJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName,
        )
        let queuedSecond = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                queue.queue.contains { $0.id == secondJobID }
            },
        )
        #expect(queuedSecond.queueType == "generation")
        #expect(queuedSecond.queue.contains { $0.id == secondJobID })

        let cancelled = try await decode(
            E2EQueueCancellationResponse.self,
            from: client.request(path: "/playback/requests/\(secondJobID)", method: "DELETE").data,
        )
        #expect(cancelled.cancelledRequestID == secondJobID)

        let secondTerminal = try await waitForTerminalJob(
            id: secondJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        Self.assertSpeechJobCancelled(secondTerminal, expectedJobID: secondJobID)

        let thirdJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName,
        )
        let fourthJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName,
        )
        _ = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                let ids = Set(queue.queue.map(\.id))
                return ids.contains(thirdJobID) && ids.contains(fourthJobID)
            },
        )

        let cleared = try await decode(
            E2EQueueClearedResponse.self,
            from: client.request(path: "/playback/queue", method: "DELETE").data,
        )
        #expect(cleared.clearedCount >= 2)

        _ = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { $0.queue.isEmpty },
        )

        let thirdTerminal = try await waitForTerminalJob(
            id: thirdJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        let fourthTerminal = try await waitForTerminalJob(
            id: fourthJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        Self.assertSpeechJobCancelled(thirdTerminal, expectedJobID: thirdJobID)
        Self.assertSpeechJobCancelled(fourthTerminal, expectedJobID: fourthJobID)

        _ = try await waitForTerminalJob(
            id: firstJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )

        let removeResponse = try await client.request(path: "/voices/\(profileName)", method: "DELETE")
        #expect(removeResponse.statusCode == 202)
        let removeJobID = try decode(E2EJobCreatedResponse.self, from: removeResponse.data).jobID
        let removeSnapshot = try await waitForTerminalJob(
            id: removeJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        #expect(removeSnapshot.status == "completed")
        try await Self.assertProfileIsNotVisible(using: client, profileName: profileName)
    }

    @Test func `mcp operator control surface covers playback and queue mutations without catalog subscriptions`() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59600..<59700),
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
            from: client.callToolJSON(name: "get_runtime_overview", arguments: [:]),
        )
        #expect(runtimeOverview["worker_mode"] as? String == "ready")

        let profileName = "mcp-operator-control-profile"
        try await Self.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription,
        )
        try await Self.assertProfileIsVisible(using: client, profileName: profileName)

        let longPlaybackText = Self.operatorControlPlaybackText
        let firstJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": profileName,
                ],
            ),
        )

        let playingState = try await Self.waitForMCPPlaybackState(
            using: client,
            timeout: .seconds(180),
            matching: { $0.state == "playing" && $0.activeRequest?.id == firstJobID },
        )
        #expect(playingState.activeRequest?.op == "generate_speech")

        let pausedPayload = try await Self.requireObjectPayload(
            from: client.callToolJSON(name: "pause_playback", arguments: [:]),
        )
        let pausedPlayback = try requireDictionary("playback", in: pausedPayload)
        #expect(pausedPlayback["state"] as? String == "paused")

        let resumedPayload = try await Self.requireObjectPayload(
            from: client.callToolJSON(name: "resume_playback", arguments: [:]),
        )
        let resumedPlayback = try requireDictionary("playback", in: resumedPayload)
        #expect(resumedPlayback["state"] as? String == "playing")

        let secondJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": profileName,
                ],
            ),
        )
        let queuedSecond = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                queue.queue.contains { $0.id == secondJobID }
            },
        )
        #expect(queuedSecond.queueType == "generation")
        #expect(queuedSecond.queue.contains { $0.id == secondJobID })

        let cancelledPayload = try await Self.requireObjectPayload(
            from: client.callToolJSON(
                name: "cancel_request",
                arguments: ["request_id": secondJobID],
            ),
        )
        #expect(cancelledPayload["cancelled_request_id"] as? String == secondJobID)

        let secondTerminal = try await waitForTerminalJob(
            id: secondJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        Self.assertSpeechJobCancelled(secondTerminal, expectedJobID: secondJobID)

        let thirdJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": profileName,
                ],
            ),
        )
        let fourthJobID = try await requireString(
            "request_id",
            in: client.callTool(
                name: "generate_speech",
                arguments: [
                    "text": longPlaybackText,
                    "profile_name": profileName,
                ],
            ),
        )
        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                let ids = Set(queue.queue.map(\.id))
                return ids.contains(thirdJobID) && ids.contains(fourthJobID)
            },
        )

        let clearedPayload = try await Self.requireObjectPayload(
            from: client.callToolJSON(name: "clear_playback_queue", arguments: [:]),
        )
        #expect((clearedPayload["cleared_count"] as? Int) ?? 0 >= 2)

        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { $0.queue.isEmpty },
        )

        let thirdTerminal = try await waitForTerminalJob(
            id: thirdJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        let fourthTerminal = try await waitForTerminalJob(
            id: fourthJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        Self.assertSpeechJobCancelled(thirdTerminal, expectedJobID: thirdJobID)
        Self.assertSpeechJobCancelled(fourthTerminal, expectedJobID: fourthJobID)

        let firstTerminal = try await waitForTerminalJob(
            id: firstJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        Self.assertSpeechJobCompleted(firstTerminal, expectedJobID: firstJobID)
        #expect(firstTerminal.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })

        let removeProfilePayload = try await client.callTool(
            name: "delete_voice_profile",
            arguments: ["profile_name": profileName],
        )
        let removeProfileJobID = try requireString("request_id", in: removeProfilePayload)
        let removeSnapshot = try await waitForTerminalJob(
            id: removeProfileJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server,
        )
        #expect(removeSnapshot.status == "completed")
        let remainingProfiles = try await requireProfiles(from: client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(remainingProfiles.contains { $0.profileName == profileName } == false)
    }
}
