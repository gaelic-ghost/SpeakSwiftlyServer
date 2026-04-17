import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Queued Marvis End-to-End Lane

extension ServerE2E {
    static func runQueuedMarvisTripletLane(using transport: E2ETransport) async throws {
        struct MarvisQueuedLane {
            let profileName: String
            let vibe: String
            let voiceDescription: String
            let expectedVoice: String
        }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let prefix = transport.profilePrefix
        let lanes = [
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-femme-profile",
                vibe: "femme",
                voiceDescription: "A warm, bright, feminine narrator voice.",
                expectedVoice: "conversational_a",
            ),
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-masc-profile",
                vibe: "masc",
                voiceDescription: "A grounded, rich, masculine speaking voice.",
                expectedVoice: "conversational_b",
            ),
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-androgenous-profile",
                vibe: "androgenous",
                voiceDescription: "A calm, balanced, and gentle speaking voice.",
                expectedVoice: "conversational_a",
            ),
        ]

        let server = try makeServer(
            port: randomPort(in: 59000..<59200),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: isPlaybackTraceEnabled,
            mcpEnabled: transport == .mcp,
            speechBackend: "marvis",
        )
        try server.start()
        defer { server.stop() }

        switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(
                    using: client,
                    timeout: e2eTimeout,
                    server: server,
                )

                for lane in lanes {
                    try await createVoiceDesignProfile(
                        using: client,
                        server: server,
                        profileName: lane.profileName,
                        vibe: lane.vibe,
                        text: testingProfileText,
                        voiceDescription: lane.voiceDescription,
                    )
                }

                var jobIDs = [String]()
                for lane in lanes {
                    let jobID = try await submitSpeechJob(
                        using: client,
                        text: testingPlaybackText,
                        profileName: lane.profileName,
                    )
                    jobIDs.append(jobID)
                }

                _ = try await waitForPlaybackState(
                    using: client,
                    timeout: .seconds(180),
                    matching: { $0.state == "playing" && $0.activeRequest?.id == jobIDs[0] },
                )
                let queued = try await waitForGenerationQueue(
                    using: client,
                    timeout: .seconds(180),
                    matching: { snapshot in
                        let ids = Set(snapshot.queue.map(\.id))
                        return ids.contains(jobIDs[1]) && ids.contains(jobIDs[2])
                    },
                )
                #expect(queued.queueType == "generation")

                do {
                    let firstSnapshot = try await waitForTerminalJob(
                        id: jobIDs[0],
                        using: client,
                        timeout: e2eTimeout,
                        server: server,
                    )
                    assertSpeechJobCompleted(firstSnapshot, expectedJobID: jobIDs[0])
                    #expect(!firstSnapshot.history.contains { $0.event == "queued" })

                    let secondSnapshot = try await waitForTerminalJob(
                        id: jobIDs[1],
                        using: client,
                        timeout: e2eTimeout,
                        server: server,
                    )
                    assertSpeechJobCompleted(secondSnapshot, expectedJobID: jobIDs[1])
                    #expect(secondSnapshot.history.contains {
                        $0.event == "queued" && (
                            $0.reason == "waiting_for_marvis_generation_lane"
                                || $0.reason == "waiting_for_playback_stability"
                        )
                    })

                    let thirdSnapshot = try await waitForTerminalJob(
                        id: jobIDs[2],
                        using: client,
                        timeout: e2eTimeout,
                        server: server,
                    )
                    assertSpeechJobCompleted(thirdSnapshot, expectedJobID: jobIDs[2])
                    // The shared generation-queue snapshot above already proves the third
                    // request entered the Marvis queue. Upstream runtime coverage only treats
                    // that queued scheduler state as durable for the tail request, so we do
                    // not require a retained per-request queued event here.
                } catch {
                    await recordQueuedMarvisHTTPDiagnostics(
                        using: client,
                        requestIDs: jobIDs,
                        expectedProfiles: lanes.map(\.profileName),
                    )
                    throw error
                }

                try await assertMarvisPlaybackStartedInOrder(on: server, requestIDs: jobIDs)

                for (jobID, lane) in zip(jobIDs, lanes) {
                    try await expectMarvisVoiceSelection(
                        on: server,
                        requestID: jobID,
                        expectedVoice: lane.expectedVoice,
                    )
                }

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server,
                )
                try await waitUntilWorkerReady(
                    using: client,
                    timeout: e2eTimeout,
                    server: server,
                )

                for lane in lanes {
                    try await createVoiceDesignProfile(
                        using: client,
                        server: server,
                        profileName: lane.profileName,
                        vibe: lane.vibe,
                        text: testingProfileText,
                        voiceDescription: lane.voiceDescription,
                    )
                }

                var jobIDs = [String]()
                for lane in lanes {
                    let payload = try await client.callTool(
                        name: "generate_speech",
                        arguments: [
                            "text": testingPlaybackText,
                            "profile_name": lane.profileName,
                        ],
                    )
                    let jobID = try requireString("request_id", in: payload)
                    #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")
                    jobIDs.append(jobID)
                }

                let queued = try await waitForMCPGenerationQueue(
                    using: client,
                    timeout: .seconds(180),
                    matching: { snapshot in
                        let ids = Set(snapshot.queue.map(\.id))
                        return ids.contains(jobIDs[1]) && ids.contains(jobIDs[2])
                    },
                )
                #expect(queued.queueType == "generation")

                let firstSnapshot = try await waitForTerminalJob(
                    id: jobIDs[0],
                    using: client,
                    timeout: e2eTimeout,
                    server: server,
                )
                assertSpeechJobCompleted(firstSnapshot, expectedJobID: jobIDs[0])
                #expect(!firstSnapshot.history.contains { $0.event == "queued" })

                let secondSnapshot = try await waitForTerminalJob(
                    id: jobIDs[1],
                    using: client,
                    timeout: e2eTimeout,
                    server: server,
                )
                assertSpeechJobCompleted(secondSnapshot, expectedJobID: jobIDs[1])
                #expect(secondSnapshot.history.contains {
                    $0.event == "queued" && (
                        $0.reason == "waiting_for_marvis_generation_lane"
                            || $0.reason == "waiting_for_playback_stability"
                    )
                })

                let thirdSnapshot = try await waitForTerminalJob(
                    id: jobIDs[2],
                    using: client,
                    timeout: e2eTimeout,
                    server: server,
                )
                assertSpeechJobCompleted(thirdSnapshot, expectedJobID: jobIDs[2])
                // The shared generation-queue snapshot above already proves the third
                // request entered the Marvis queue. Upstream runtime coverage only treats
                // that queued scheduler state as durable for the tail request, so we do
                // not require a retained per-request queued event here.

                try await assertMarvisPlaybackStartedInOrder(on: server, requestIDs: jobIDs)

                for (jobID, lane) in zip(jobIDs, lanes) {
                    try await expectMarvisVoiceSelection(
                        on: server,
                        requestID: jobID,
                        expectedVoice: lane.expectedVoice,
                    )
                }
        }
    }
}
