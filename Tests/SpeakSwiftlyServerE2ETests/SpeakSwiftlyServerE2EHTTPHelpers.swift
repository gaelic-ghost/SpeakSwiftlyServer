import Foundation
import Testing

// MARK: - HTTP End-to-End Helpers

extension ServerE2E {
    static func createVoiceDesignProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil,
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "vibe": vibe,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            body["output_path"] = outputPath
        }
        if let cwd {
            body["cwd"] = cwd
        }

        let response = try await client.request(path: "/voices/from-description", method: "POST", jsonBody: body)
        #expect(response.statusCode == 202)

        let createJobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: createJobID,
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
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool,
        cwd: String? = nil,
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "vibe": vibe,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            body["transcript"] = transcript
        }
        if let cwd {
            body["cwd"] = cwd
        }

        let response = try await client.request(path: "/voices/from-audio", method: "POST", jsonBody: body)
        #expect(response.statusCode == 202)

        let cloneJobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: cloneJobID,
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
        using client: E2EHTTPClient,
        profileName: String,
    ) async throws {
        let profilesResponse = try await client.request(path: "/voices", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName })
    }

    static func assertProfileIsNotVisible(
        using client: E2EHTTPClient,
        profileName: String,
    ) async throws {
        let profilesResponse = try await client.request(path: "/voices", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName } == false)
    }

    static func runSilentSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String,
    ) async throws {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ],
        )
        #expect(response.statusCode == 202)

        let jobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
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

        let eventsResponse = try await client.request(path: "/requests/\(jobID)/events", method: "GET")
        #expect(eventsResponse.statusCode == 200)
        #expect(eventsResponse.text.contains("event: worker_status"))
        #expect(eventsResponse.text.contains(#""event":"started""#))
        #expect(eventsResponse.text.contains(#""ok":true"#))
        #expect(!eventsResponse.text.contains(#""event":"queued""#))
    }

    static func runAudibleSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String,
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

        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ],
        )
        #expect(response.statusCode == 202)

        let jobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID

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
            server: server,
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

    static func submitSpeechJob(
        using client: E2EHTTPClient,
        text: String,
        profileName: String,
    ) async throws -> String {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ],
        )
        #expect(response.statusCode == 202)
        return try decode(E2EJobCreatedResponse.self, from: response.data).jobID
    }

    static func waitForPlaybackState(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackStateSnapshot) -> Bool,
    ) async throws -> E2EPlaybackStateSnapshot {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let response = try await client.request(path: "/playback/state", method: "GET")
            guard response.statusCode == 200 else { return nil }

            let snapshot = try decode(E2EPlaybackStateResponse.self, from: response.data).playback
            return predicate(snapshot) ? snapshot : nil
        }
    }

    static func waitForGenerationQueue(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool,
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let response = try await client.request(path: "/generation/queue", method: "GET")
            guard response.statusCode == 200 else { return nil }

            let snapshot = try decode(E2EQueueSnapshotResponse.self, from: response.data)
            return predicate(snapshot) ? snapshot : nil
        }
    }
}
