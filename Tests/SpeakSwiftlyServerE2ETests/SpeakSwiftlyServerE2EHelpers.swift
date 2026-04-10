import Foundation
import SpeakSwiftlyCore
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Shared End-to-End Helpers

extension SpeakSwiftlyServerE2ETests {
    static func createVoiceDesignProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil
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
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool,
        cwd: String? = nil
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
        using client: E2EHTTPClient,
        profileName: String
    ) async throws {
        let profilesResponse = try await client.request(path: "/voices", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName })
    }

    static func assertProfileIsNotVisible(
        using client: E2EHTTPClient,
        profileName: String
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
        profileName: String
    ) async throws {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        #expect(response.statusCode == 202)

        let jobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "started" && $0.op == "queue_speech_live" })
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
        profileName: String
    ) async throws -> String {
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
            ]
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

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["time_to_first_chunk_ms"] as? Int != nil
                && details["played_back_callback_count"] as? Int != nil
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["low_water_target_ms"] as? Int != nil
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
        return jobID
    }

    static func submitSpeechJob(
        using client: E2EHTTPClient,
        text: String,
        profileName: String
    ) async throws -> String {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        #expect(response.statusCode == 202)
        return try decode(E2EJobCreatedResponse.self, from: response.data).jobID
    }

    static func waitForPlaybackState(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackStateSnapshot) -> Bool
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
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let response = try await client.request(path: "/generation/queue", method: "GET")
            guard response.statusCode == 200 else { return nil }
            let snapshot = try decode(E2EQueueSnapshotResponse.self, from: response.data)
            return predicate(snapshot) ? snapshot : nil
        }
    }

    // MARK: MCP Lane Helpers

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
            name: "queue_speech_live",
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
        #expect(snapshot.history.contains { $0.event == "started" && $0.op == "queue_speech_live" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        #expect(!snapshot.history.contains { $0.event == "queued" })
    }

    static func runAudibleSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws -> String {
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
            name: "queue_speech_live",
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

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["time_to_first_chunk_ms"] as? Int != nil
                && details["played_back_callback_count"] as? Int != nil
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["low_water_target_ms"] as? Int != nil
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

    static func recordQueuedMarvisHTTPDiagnostics(
        using client: E2EHTTPClient,
        requestIDs: [String],
        expectedProfiles: [String]
    ) async {
        do {
            let requestList = try decode(
                E2ERequestListResponse.self,
                from: try await client.request(path: "/requests", method: "GET").data
            )
            let hostState = try jsonObject(
                from: try await client.request(path: "/runtime/host", method: "GET").data
            )

            let retainedRequests = requestList.requests
                .filter { requestIDs.contains($0.requestID) }
                .sorted { lhs, rhs in
                    requestIDs.firstIndex(of: lhs.requestID) ?? .max
                        < requestIDs.firstIndex(of: rhs.requestID) ?? .max
                }
                .map(requestDiagnosticSummary)
                .joined(separator: "\n")

            let playbackQueue = try diagnosticJSONString(from: hostState["playback_queue"])
            let generationQueue = try diagnosticJSONString(from: hostState["generation_queue"])
            let currentGenerationJobs = try diagnosticJSONString(from: hostState["current_generation_jobs"])

            Issue.record(
                """
                Queued Marvis HTTP diagnostics
                expected_profiles: \(expectedProfiles.joined(separator: ", "))
                request_ids: \(requestIDs.joined(separator: ", "))
                playback_queue: \(playbackQueue)
                generation_queue: \(generationQueue)
                current_generation_jobs: \(currentGenerationJobs)
                retained_requests:
                \(retainedRequests.isEmpty ? "none" : retainedRequests)
                """
            )
        } catch {
            Issue.record(
                "Queued Marvis HTTP diagnostics could not be captured after a live-playback failure. Likely cause: \(error.localizedDescription)"
            )
        }
    }

    static func requestDiagnosticSummary(_ snapshot: E2EJobSnapshot) -> String {
        let latestEvent = snapshot.history.last?.event ?? "nil"
        let latestStage = snapshot.history.last?.stage ?? "nil"
        let terminalEvent = snapshot.terminalEvent?.event ?? "nil"
        let historySummary = snapshot.history
            .map {
                [
                    $0.event ?? "message",
                    $0.stage,
                    $0.reason,
                    $0.op,
                ]
                .compactMap { $0 }
                .joined(separator: ":")
            }
            .joined(separator: " -> ")

        return "- \(snapshot.requestID) status=\(snapshot.status) latest=\(latestEvent):\(latestStage) terminal=\(terminalEvent) history=\(historySummary)"
    }

    static func diagnosticJSONString(from value: Any?) throws -> String {
        guard let value else { return "null" }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
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

    // MARK: Shared Assertions

    static func assertSpeechJobCompleted(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.history.contains { $0.ok == true })
    }

    static func assertSpeechJobCancelled(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == false)
        #expect(snapshot.terminalEvent?.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
    }

    static func assertCloneTranscriptionStages(
        in snapshot: E2EJobSnapshot,
        expectTranscription: Bool
    ) {
        let sawLoading = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "loading_clone_transcription_model"
        }
        let sawTranscribing = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "transcribing_clone_audio"
        }

        if expectTranscription {
            #expect(sawLoading)
            #expect(sawTranscribing)
        } else {
            #expect(!sawLoading)
            #expect(!sawTranscribing)
        }
    }

    static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
        let expectedTokens = normalizedTranscriptTokens(from: testingCloneSourceText)
        let actualTokens = normalizedTranscriptTokens(from: transcript)

        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else {
            return false
        }

        let sharedTokens = expectedTokens.intersection(actualTokens)
        let recall = Double(sharedTokens.count) / Double(expectedTokens.count)
        let precision = Double(sharedTokens.count) / Double(actualTokens.count)

        return recall >= 0.7 && precision >= 0.6
    }

    static func normalizedTranscriptTokens(from text: String) -> Set<String> {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return Set(
            normalized
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    static func replacementJSON(
        id: String,
        text: String,
        replacement: String,
        match: String = "exact_phrase",
        phase: String = "before_built_ins",
        isCaseSensitive: Bool = false,
        formats: [String] = [],
        priority: Int = 0
    ) -> [String: Any] {
        [
            "id": id,
            "text": text,
            "replacement": replacement,
            "match": match,
            "phase": phase,
            "is_case_sensitive": isCaseSensitive,
            "formats": formats,
            "priority": priority,
        ]
    }

    static func requirePromptText(in result: [String: Any]) throws -> String {
        let messages = try requireArray("messages", in: result)
        let firstMessage = try requireFirstDictionary(in: messages)
        let content = try requireDictionary("content", in: firstMessage)
        return try requireString("text", in: content)
    }

    static func requireObjectPayload(from payload: Any) throws -> [String: Any] {
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON object payload, but received '\(type(of: payload))'."
            )
        }
        return object
    }

    static func requireArrayPayload(from payload: Any) throws -> [[String: Any]] {
        guard let array = payload as? [[String: Any]] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON array payload, but received '\(type(of: payload))'."
            )
        }
        return array
    }

    static func decodePayload<Value: Decodable>(_ type: Value.Type, from payload: [String: Any]) throws -> Value {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try decode(Value.self, from: data)
    }

    // MARK: Build Artifacts

    private struct SpeakSwiftlyPublishedRuntimeMetadata: Decodable {
        let buildConfiguration: String
        let productsPath: String
        let executablePath: String
        let launcherPath: String
        let metallibPath: String
        let aliasPath: String
        let sourceRoot: String?

        enum CodingKeys: String, CodingKey {
            case buildConfiguration = "build_configuration"
            case productsPath = "products_path"
            case executablePath = "executable_path"
            case launcherPath = "launcher_path"
            case metallibPath = "metallib_path"
            case aliasPath = "alias_path"
            case sourceRoot = "source_root"
        }
    }

    private struct SpeakSwiftlyPublishedRuntimeArtifacts {
        let metadataURL: URL
        let metadata: SpeakSwiftlyPublishedRuntimeMetadata
        let productsURL: URL
        let executableURL: URL
        let launcherURL: URL
        let metallibURL: URL
    }

    private static func speakSwiftlyPublishedRuntimeArtifacts(configuration: String) throws -> SpeakSwiftlyPublishedRuntimeArtifacts {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let metadataURL = serverRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.local/xcode/SpeakSwiftly.\(configuration.lowercased()).json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The live SpeakSwiftlyServer end-to-end suite requires the sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)'. Publish and verify the sibling \(configuration) runtime first."
            )
        }

        let metadata = try decode(
            SpeakSwiftlyPublishedRuntimeMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.buildConfiguration == configuration else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)' reported build configuration '\(metadata.buildConfiguration)' instead of the expected '\(configuration)'."
            )
        }

        let siblingSourceRootURL = metadataURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localXcodeRootURL = siblingSourceRootURL
            .appendingPathComponent(".local/xcode", isDirectory: true)
        let productsURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.productsPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: localXcodeRootURL.appendingPathComponent(configuration, isDirectory: true),
            isDirectory: true
        )
        let executableURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.executablePath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent("SpeakSwiftly", isDirectory: false),
            isDirectory: false
        )
        let launcherURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.launcherPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent("run-speakswiftly", isDirectory: false),
            isDirectory: false
        )
        let metallibURL = resolvedPublishedRuntimeURL(
            recordedPath: metadata.metallibPath,
            recordedSourceRoot: metadata.sourceRoot,
            actualSourceRootURL: siblingSourceRootURL,
            fallbackURL: productsURL.appendingPathComponent(
                "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
                isDirectory: false
            ),
            isDirectory: false
        )
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing metallib path '\(metallibURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing runtime launcher '\(launcherURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing executable '\(executableURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }

        return .init(
            metadataURL: metadataURL,
            metadata: metadata,
            productsURL: productsURL,
            executableURL: executableURL,
            launcherURL: launcherURL,
            metallibURL: metallibURL
        )
    }

    private static func resolvedPublishedRuntimeURL(
        recordedPath: String,
        recordedSourceRoot: String?,
        actualSourceRootURL: URL,
        fallbackURL: URL,
        isDirectory: Bool
    ) -> URL {
        let recordedURL = URL(fileURLWithPath: recordedPath, isDirectory: isDirectory)
        if FileManager.default.fileExists(atPath: recordedURL.path) {
            return recordedURL
        }

        guard
            let recordedSourceRoot,
            recordedPath.hasPrefix(recordedSourceRoot)
        else {
            return fallbackURL
        }

        let relativeSuffix = String(recordedPath.dropFirst(recordedSourceRoot.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard relativeSuffix.isEmpty == false else {
            return fallbackURL
        }

        let rebasedURL = actualSourceRootURL
            .appendingPathComponent(relativeSuffix, isDirectory: isDirectory)
        if FileManager.default.fileExists(atPath: rebasedURL.path) {
            return rebasedURL
        }

        return fallbackURL
    }

    static func serverToolExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServerTool", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServerTool executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live end-to-end suite."
            )
        }
        return executableURL
    }

    private static func stageMetallibForServerBinary(
        sourceURL: URL,
        serverExecutableURL: URL
    ) throws {
        let targetDirectoryURL = serverExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let targetURL = targetDirectoryURL.appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    }

    static func makeServer(
        port: Int,
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil
    ) throws -> ServerProcess {
        let publishedRuntimeArtifacts = try speakSwiftlyPublishedRuntimeArtifacts(configuration: "Debug")
        let executableURL = try serverToolExecutableURL()
        try stageMetallibForServerBinary(
            sourceURL: publishedRuntimeArtifacts.metallibURL,
            serverExecutableURL: executableURL
        )

        return try ServerProcess(
            executableURL: executableURL,
            profileRootURL: profileRootURL,
            port: port,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled,
            speechBackend: speechBackend
        )
    }

    static func randomPort(in range: Range<Int>) -> Int {
        Int.random(in: range)
    }

    static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    static var e2eTimeout: Duration {
        .seconds(1_200)
    }
}
