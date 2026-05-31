import Foundation
import Testing

// MARK: - MCP End-to-End Helpers

extension ServerE2E {
    static func createVoiceDesignProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil,
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "vibe": vibe,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            arguments["output_path"] = outputPath
        }
        if let cwd {
            arguments["cwd"] = cwd
        }

        let payload = try await client.callTool(name: "create_voice_profile_from_description", arguments: arguments)
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak-swiftly://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server,
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)
        if outputPath != nil {
            #expect(snapshot.terminalEvent?.profilePath?.isEmpty == false)
        }
    }

    static func createCloneProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool,
        cwd: String? = nil,
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "vibe": vibe,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            arguments["transcript"] = transcript
        }
        if let cwd {
            arguments["cwd"] = cwd
        }

        let payload = try await client.callTool(name: "create_voice_profile_from_audio", arguments: arguments)
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak-swiftly://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server,
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)

        assertCloneTranscriptionStages(
            in: snapshot,
            expectTranscription: expectTranscription,
        )
    }

    static func assertProfileIsVisible(
        using client: E2EMCPClient,
        profileName: String,
    ) async throws {
        let payload = try await client.readResourceJSON(uri: "speak-swiftly://voices")
        let profiles = try requireProfiles(from: payload)
        #expect(profiles.contains { $0.profileName == profileName })
    }

    static func runSilentSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String,
    ) async throws {
        let payload = try await client.callTool(
            name: "generate_speech",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ],
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak-swiftly://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server,
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "started" && $0.op == "generate_speech" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        #expect(!snapshot.history.contains { $0.event == "queued" })
    }

    static func runAudibleSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String,
    ) async throws -> String {
        let audiblePlaybackTimeout = Duration.seconds(180)

        try stabilizeBuiltInAudioRouteForAudiblePlayback()

        let payload = try await client.callTool(
            name: "generate_speech",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ],
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak-swiftly://requests/\(jobID)")

        do {
            _ = try await server.waitForStderrJSONObject(timeout: audiblePlaybackTimeout) {
                guard
                    $0["event"] as? String == "playback_started",
                    $0["request_id"] as? String == jobID,
                    let details = $0["details"] as? [String: Any]
                else {
                    return false
                }

                let textComplexityClass = details["text_complexity_class"] as? String
                return ["compact", "balanced", "extended"].contains(textComplexityClass)
                    && details["startup_buffer_target_ms"] as? Int != nil
                    && details["startup_buffered_audio_ms"] as? Int != nil
                    && details["process_phys_footprint_bytes"] as? Int != nil
                    && details["mlx_active_memory_bytes"] as? Int != nil
            }
        } catch is E2ETimeoutError {
            throw E2ETransportError(
                """
                The live MCP audible speech helper never observed a `playback_started` trace event for request '\(jobID)' before timing out.
                Recent server stderr:
                \(server.recentStructuredStderrSummary())
                """,
            )
        }

        let snapshot: E2EJobSnapshot
        do {
            snapshot = try await waitForTerminalJob(
                id: jobID,
                using: client,
                timeout: audiblePlaybackTimeout,
                server: server,
            )
        } catch is E2ETimeoutError {
            let snapshotText = try await client.readResourceText(uri: "speak-swiftly://requests/\(jobID)")
            throw E2ETransportError(
                """
                The live MCP audible speech helper timed out before request '\(jobID)' reached a terminal state.
                Current request snapshot:
                \(snapshotText)
                Recent server stderr:
                \(server.recentStructuredStderrSummary())
                """,
            )
        }

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "preroll_ready" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        if let playbackFinishedLog = server.stderrObjects().last(where: { object in
            guard
                object["event"] as? String == "playback_finished",
                object["request_id"] as? String == jobID,
                let details = object["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
        }) {
            let details = try #require(playbackFinishedLog["details"] as? [String: Any])
            #expect(details["played_back_callback_count"] as? Int != nil)
            #expect(details["startup_buffer_target_ms"] as? Int != nil)
            #expect(details["low_water_target_ms"] as? Int != nil)
            #expect(details["process_phys_footprint_bytes"] as? Int != nil)
            #expect(details["mlx_active_memory_bytes"] as? Int != nil)
        }
        return jobID
    }

    static func waitForMCPPlaybackState(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackSnapshot) -> Bool,
    ) async throws -> E2EPlaybackSnapshot {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try await ServerE2E.requireObjectPayload(
                from: client.readResourceJSON(uri: "speak-swiftly://overview"),
            )
            let playback = try #require(payload["playback"] as? [String: Any])
            let snapshot = try decodePayload(E2EPlaybackSnapshot.self, from: playback)
            return predicate(snapshot) ? snapshot : nil
        }
    }

    static func waitForMCPGenerationQueue(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool,
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try await ServerE2E.requireObjectPayload(
                from: client.readResourceJSON(uri: "speak-swiftly://overview"),
            )
            let generationQueue = try #require(payload["generation_queue"] as? [String: Any])
            let snapshot = try decodePayload(E2EQueueSnapshotResponse.self, from: generationQueue)
            return predicate(snapshot) ? snapshot : nil
        }
    }
}
