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
        cwd: String? = nil
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
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
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
        cwd: String? = nil
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
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)

        assertCloneTranscriptionStages(
            in: snapshot,
            expectTranscription: expectTranscription
        )
    }

    static func assertProfileIsVisible(
        using client: E2EMCPClient,
        profileName: String
    ) async throws {
        let payload = try await client.callToolJSON(name: "list_voice_profiles", arguments: [:])
        let profiles = try requireProfiles(from: payload)
        #expect(profiles.contains { $0.profileName == profileName })
    }

    static func runSilentSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
        let payload = try await client.callTool(
            name: "generate_speech",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
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
        profileName: String
    ) async throws -> String {
        try stabilizeBuiltInAudioRouteForAudiblePlayback()

        let engineReadyLog = try await server.waitForStderrJSONObject(timeout: .seconds(120)) {
            guard
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }
        #expect(engineReadyLog["event"] as? String == "playback_engine_ready")

        let payload = try await client.callTool(
            name: "generate_speech",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
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

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

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

    static func expectMarvisVoiceSelection(
        on server: ServerProcess,
        requestID: String,
        expectedVoice: String
    ) async throws {
        let log = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "marvis_voice_selected",
                $0["request_id"] as? String == requestID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["speech_backend"] as? String == "marvis"
                && details["marvis_voice"] as? String == expectedVoice
        }
        #expect(log["event"] as? String == "marvis_voice_selected")
    }

    static func assertMarvisPlaybackStartedInOrder(
        on server: ServerProcess,
        requestIDs: [String]
    ) async throws {
        let startedRequestIDs: [String] = try await e2eWaitUntil(
            timeout: e2eTimeout,
            pollInterval: .milliseconds(200)
        ) {
            let matches = server.stderrObjects().compactMap { object -> String? in
                guard object["event"] as? String == "playback_started" else { return nil }
                return object["request_id"] as? String
            }
            let filtered = matches.filter { requestIDs.contains($0) }
            guard Set(filtered).isSuperset(of: Set(requestIDs)) else { return nil }
            return filtered
        }

        var previousIndex = -1
        for requestID in requestIDs {
            guard let index = startedRequestIDs.firstIndex(of: requestID) else {
                Issue.record("The live Marvis playback trace never reported a playback_started event for request '\(requestID)'.")
                return
            }
            #expect(index > previousIndex)
            previousIndex = index
        }
    }

    static func waitForMCPPlaybackState(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackStateSnapshot) -> Bool
    ) async throws -> E2EPlaybackStateSnapshot {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try requireObjectPayload(
                from: try await client.callToolJSON(name: "get_playback_state", arguments: [:])
            )
            let snapshot: E2EPlaybackStateSnapshot
            if let playback = payload["playback"] as? [String: Any] {
                snapshot = try decodePayload(E2EPlaybackStateSnapshot.self, from: playback)
            } else {
                snapshot = try decodePayload(E2EPlaybackStateSnapshot.self, from: payload)
            }
            return predicate(snapshot) ? snapshot : nil
        }
    }

    static func waitForMCPGenerationQueue(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try requireObjectPayload(
                from: try await client.callToolJSON(name: "list_generation_queue", arguments: [:])
            )
            let snapshot = try decodePayload(E2EQueueSnapshotResponse.self, from: payload)
            return predicate(snapshot) ? snapshot : nil
        }
    }
}
