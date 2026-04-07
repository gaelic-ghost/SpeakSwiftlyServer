import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - End-to-End Tests

/// Keep the suite type name stable so Xcode test plans can target it directly.
@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1",
        "Set SPEAKSWIFTLYSERVER_E2E=1 to run live end-to-end coverage."
    )
)
struct SpeakSwiftlyServerE2ETests {
    // MARK: Test Fixtures

    private static let testingProfileText = "Hello there from SpeakSwiftlyServer end-to-end coverage."
    private static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."
    fileprivate static let testingCloneSourceText = """
    This imported reference audio should let SpeakSwiftlyServer build a clone profile for end to end coverage with a clean transcript and steady speech.
    """
    private static let testingPlaybackText = """
    Hello from the real resident SpeakSwiftlyServer playback path. This end to end test uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
    """

    // MARK: Sequential End-to-End Workflows

    @Test func httpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runVoiceDesignLane(using: .http)
    }

    @Test func httpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .http, transcriptMode: .provided)
    }

    @Test func httpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .http, transcriptMode: .inferred)
    }

    @Test func mcpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runVoiceDesignLane(using: .mcp)
    }

    @Test func mcpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .mcp, transcriptMode: .provided)
    }

    @Test func mcpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .mcp, transcriptMode: .inferred)
    }

    // MARK: Lane Workflows

    private static func runVoiceDesignLane(using transport: E2ETransport) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let profileName = "\(transport.profilePrefix)-voice-design-profile"

        do {
            let server = try makeServer(
                port: randomPort(in: 59_000..<59_200),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: profileName,
                    text: testingProfileText,
                    voiceDescription: testingProfileVoiceDescription
                )
                try await assertProfileIsVisible(using: client, profileName: profileName)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: profileName,
                    text: testingProfileText,
                    voiceDescription: testingProfileVoiceDescription
                )
                try await assertProfileIsVisible(using: client, profileName: profileName)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )
            }
        }

        do {
            let server = try makeServer(
                port: randomPort(in: 59_200..<59_400),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: isPlaybackTraceEnabled,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)

                try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)

                try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )
            }
        }
    }

    private static func runCloneLane(
        using transport: E2ETransport,
        transcriptMode: CloneTranscriptMode
    ) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let fixtureProfileName = "\(transport.profilePrefix)-\(transcriptMode.slug)-clone-source-profile"
        let cloneProfileName = "\(transport.profilePrefix)-\(transcriptMode.slug)-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("\(transport.profilePrefix)-\(transcriptMode.slug)-reference.wav")

        do {
            let server = try makeServer(
                port: randomPort(in: 59_400..<59_600),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: fixtureProfileName,
                    text: testingCloneSourceText,
                    voiceDescription: testingProfileVoiceDescription,
                    outputPath: referenceAudioURL.path
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: referenceAudioURL.path,
                    transcript: transcriptMode.providedTranscript,
                    expectTranscription: transcriptMode.expectTranscription
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: fixtureProfileName,
                    text: testingCloneSourceText,
                    voiceDescription: testingProfileVoiceDescription,
                    outputPath: referenceAudioURL.path
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: referenceAudioURL.path,
                    transcript: transcriptMode.providedTranscript,
                    expectTranscription: transcriptMode.expectTranscription
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)
            }

            let storedProfile = try loadStoredProfileManifest(
                named: cloneProfileName,
                from: sandbox.profileRootURL
            )
            switch transcriptMode {
            case .provided:
                #expect(storedProfile.sourceText == testingCloneSourceText)
            case .inferred:
                let inferredTranscript = storedProfile.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(!inferredTranscript.isEmpty)
                #expect(transcriptLooksCloseToCloneSource(inferredTranscript))
            }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )
            }
        }

        do {
            let server = try makeServer(
                port: randomPort(in: 59_600..<59_800),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: isPlaybackTraceEnabled,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )
            }
        }
    }

    // MARK: HTTP Lane Helpers

    private static func createVoiceDesignProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            body["output_path"] = outputPath
        }

        let response = try await client.request(path: "/profiles", method: "POST", jsonBody: body)
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

    private static func createCloneProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            body["transcript"] = transcript
        }

        let response = try await client.request(path: "/profiles/clone", method: "POST", jsonBody: body)
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

    private static func assertProfileIsVisible(
        using client: E2EHTTPClient,
        profileName: String
    ) async throws {
        let profilesResponse = try await client.request(path: "/profiles", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName })
    }

    private static func runSilentSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
        let response = try await client.request(
            path: "/speak",
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

        let eventsResponse = try await client.request(path: "/jobs/\(jobID)/events", method: "GET")
        #expect(eventsResponse.statusCode == 200)
        #expect(eventsResponse.text.contains("event: worker_status"))
        #expect(eventsResponse.text.contains(#""event":"started""#))
        #expect(eventsResponse.text.contains(#""ok":true"#))
        #expect(!eventsResponse.text.contains(#""event":"queued""#))
    }

    private static func runAudibleSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
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
            path: "/speak",
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
    }

    // MARK: MCP Lane Helpers

    private static func createVoiceDesignProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String? = nil
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            arguments["output_path"] = outputPath
        }

        let payload = try await client.callTool(name: "create_profile", arguments: arguments)
        let jobID = try requireString("job_id", in: payload)
        #expect(payload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")

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

    private static func createCloneProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            arguments["transcript"] = transcript
        }

        let payload = try await client.callTool(name: "create_clone", arguments: arguments)
        let jobID = try requireString("job_id", in: payload)
        #expect(payload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")

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

    private static func assertProfileIsVisible(
        using client: E2EMCPClient,
        profileName: String
    ) async throws {
        let payload = try await client.callToolJSON(name: "list_profiles", arguments: [:])
        let profiles = try requireProfiles(from: payload)
        #expect(profiles.contains { $0.profileName == profileName })
    }

    private static func runSilentSpeech(
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
        let jobID = try requireString("job_id", in: payload)
        #expect(payload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")

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

    private static func runAudibleSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
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
        let jobID = try requireString("job_id", in: payload)
        #expect(payload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")

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
    }

    // MARK: Shared Assertions

    private static func assertSpeechJobCompleted(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.history.contains { $0.ok == true })
    }

    private static func assertCloneTranscriptionStages(
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

    private static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
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

    private static func normalizedTranscriptTokens(from text: String) -> Set<String> {
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

    // MARK: Build Artifacts

    private static func speakSwiftlyProductsURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productsURL = serverRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.derived/Build/Products/Debug", isDirectory: true)

        let metallibURL = productsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The live SpeakSwiftlyServer end-to-end suite requires the Xcode-built SpeakSwiftly products at '\(productsURL.path)'. Build ../SpeakSwiftly with Xcode first so `default.metallib` is available."
            )
        }
        return productsURL
    }

    private static func serverExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServer", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServer executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live end-to-end suite."
            )
        }
        return executableURL
    }

    private static func stageMetallibForServerBinary(
        from dependencyProductsURL: URL,
        serverExecutableURL: URL
    ) throws {
        let sourceURL = dependencyProductsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)
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

    private static func makeServer(
        port: Int,
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool
    ) throws -> ServerProcess {
        let dependencyProductsURL = try speakSwiftlyProductsURL()
        let executableURL = try serverExecutableURL()
        try stageMetallibForServerBinary(
            from: dependencyProductsURL,
            serverExecutableURL: executableURL
        )

        return try ServerProcess(
            executableURL: executableURL,
            dependencyProductsURL: dependencyProductsURL,
            profileRootURL: profileRootURL,
            port: port,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled
        )
    }

    private static func randomPort(in range: Range<Int>) -> Int {
        Int.random(in: range)
    }

    private static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    private static var e2eTimeout: Duration {
        .seconds(1_200)
    }
}

// MARK: - End-to-End Helpers

private enum E2ETransport: Sendable {
    case http
    case mcp

    var profilePrefix: String {
        switch self {
        case .http:
            "http"
        case .mcp:
            "mcp"
        }
    }
}

private enum CloneTranscriptMode: Sendable {
    case provided
    case inferred

    var slug: String {
        switch self {
        case .provided:
            "provided-transcript"
        case .inferred:
            "inferred-transcript"
        }
    }

    var providedTranscript: String? {
        switch self {
        case .provided:
            SpeakSwiftlyServerE2ETests.testingCloneSourceText
        case .inferred:
            nil
        }
    }

    var expectTranscription: Bool {
        switch self {
        case .provided:
            false
        case .inferred:
            true
        }
    }
}

private struct ServerE2ESandbox {
    let rootURL: URL
    let profileRootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyServer-E2E-\(UUID().uuidString)", isDirectory: true)
        profileRootURL = rootURL.appendingPathComponent("profiles", isDirectory: true)

        try FileManager.default.createDirectory(at: profileRootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

// MARK: - Live Server Process

private final class ServerProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    let baseURL: URL

    init(
        executableURL: URL,
        dependencyProductsURL: URL,
        profileRootURL: URL,
        port: Int,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool
    ) throws {
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw E2ETransportError("The live end-to-end suite could not construct a localhost base URL for port '\(port)'.")
        }
        self.baseURL = baseURL

        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["APP_PORT"] = String(port)
        environment["SPEAKSWIFTLY_PROFILE_ROOT"] = profileRootURL.path
        environment["APP_MCP_ENABLED"] = mcpEnabled ? "true" : "false"
        environment["APP_MCP_PATH"] = "/mcp"
        environment["APP_MCP_SERVER_NAME"] = "speak-swiftly-server-e2e"
        environment["APP_MCP_TITLE"] = "SpeakSwiftlyServer E2E MCP"
        if silentPlayback {
            environment["SPEAKSWIFTLY_SILENT_PLAYBACK"] = "1"
        } else {
            environment.removeValue(forKey: "SPEAKSWIFTLY_SILENT_PLAYBACK")
        }
        if playbackTrace {
            environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] = "1"
        }
        environment["DYLD_FRAMEWORK_PATH"] = dependencyProductsURL.path
        process.environment = environment
    }

    func start() throws {
        stdoutTask = captureLines(from: stdoutPipe.fileHandleForReading, recordingInto: stdoutRecorder)
        stderrTask = captureLines(from: stderrPipe.fileHandleForReading, recordingInto: stderrRecorder)
        try process.run()
    }

    func stop() {
        terminateProcessIfNeeded()
        stdoutTask?.cancel()
        stderrTask?.cancel()
    }

    var isStillRunning: Bool {
        process.isRunning
    }

    var combinedOutput: String {
        stdoutRecorder.contents + (stdoutRecorder.isEmpty || stderrRecorder.isEmpty ? "" : "\n") + stderrRecorder.contents
    }

    func waitForStderrJSONObject(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool
    ) async throws -> [String: Any] {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(100)) {
            for line in self.stderrRecorder.snapshot {
                guard let data = line.data(using: .utf8) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) else { continue }
                guard let object = json as? [String: Any], predicate(object) else { continue }
                return object
            }

            guard self.isStillRunning else {
                throw E2ETransportError(
                    "The live SpeakSwiftlyServer process exited before the expected stderr JSON log was observed.\n\(self.combinedOutput)"
                )
            }
            return nil
        }
    }

    private func captureLines(
        from handle: FileHandle,
        recordingInto recorder: SynchronizedLogBuffer
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await line in handle.bytes.lines {
                    recorder.append(line)
                }
            } catch is CancellationError {
                return
            } catch {
                recorder.append(
                    "Server process log capture stopped after an unexpected stream error: \(error.localizedDescription)"
                )
            }
        }
    }

    private let stdoutRecorder = SynchronizedLogBuffer()
    private let stderrRecorder = SynchronizedLogBuffer()

    private func terminateProcessIfNeeded() {
        guard process.isRunning else { return }

        if waitForExit(after: { process.interrupt() }, timeout: .seconds(5)) {
            return
        }
        if waitForExit(after: { process.terminate() }, timeout: .seconds(5)) {
            return
        }

        #if canImport(Darwin)
        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(timeout: .seconds(2))
        #endif
    }

    private func waitForExit(
        after action: () -> Void,
        timeout: Duration
    ) -> Bool {
        action()
        return waitForExit(timeout: timeout)
    }

    private func waitForExit(timeout: Duration) -> Bool {
        guard process.isRunning else { return true }

        let semaphore = DispatchSemaphore(value: 0)
        let originalHandler = process.terminationHandler
        process.terminationHandler = { completedProcess in
            originalHandler?(completedProcess)
            semaphore.signal()
        }
        defer {
            process.terminationHandler = originalHandler
        }

        guard process.isRunning else { return true }
        let timeoutInterval =
            Double(timeout.components.seconds)
            + Double(timeout.components.attoseconds) / 1_000_000_000_000_000_000
        return semaphore.wait(timeout: .now() + timeoutInterval) == .success
    }

    private final class SynchronizedLogBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var lines = [String]()

        func append(_ line: String) {
            lock.withLock {
                lines.append(line)
            }
        }

        var contents: String {
            lock.withLock {
                lines.joined(separator: "\n")
            }
        }

        var snapshot: [String] {
            lock.withLock {
                lines
            }
        }

        var isEmpty: Bool {
            lock.withLock {
                lines.isEmpty
            }
        }
    }
}

// MARK: - HTTP Client

private struct E2EHTTPClient {
    let baseURL: URL

    func request(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2ETransportError("The live HTTP request to '\(path)' did not return an HTTPURLResponse.")
        }
        return E2EHTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, data: data)
    }
}

private struct E2EHTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let data: Data

    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

// MARK: - MCP Client

private struct E2EMCPClient {
    let baseURL: URL
    let path: String
    let sessionID: String

    static func connect(
        baseURL: URL,
        path: String,
        timeout: Duration,
        server: ServerProcess
    ) async throws -> E2EMCPClient {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
            guard server.isStillRunning else {
                throw E2ETransportError(
                    "The live SpeakSwiftlyServer process exited before the MCP transport became available.\n\(server.combinedOutput)"
                )
            }

            do {
                return try await connectNow(baseURL: baseURL, path: path)
            } catch {
                if isRetryableConnectionDuringStartup(error) {
                    return nil
                }
                return nil
            }
        }
    }

    private static func connectNow(baseURL: URL, path: String) async throws -> E2EMCPClient {
        let initializeBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "initialize-1",
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [:],
                "clientInfo": [
                    "name": "SpeakSwiftlyServerE2ETests",
                    "version": "1.0",
                ],
            ],
        ]

        let initializeResponse = try await post(
            baseURL: baseURL,
            path: path,
            jsonBody: initializeBody,
            sessionID: nil
        )
        let sessionID = try requireMCPHeader("Mcp-Session-Id", in: initializeResponse.headers)
        _ = try parseMCPEnvelope(from: initializeResponse.data)

        let initializedBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
        ]
        let initializedResponse = try await post(
            baseURL: baseURL,
            path: path,
            jsonBody: initializedBody,
            sessionID: sessionID
        )
        #expect((200...299).contains(initializedResponse.statusCode))

        return .init(baseURL: baseURL, path: path, sessionID: sessionID)
    }

    func callTool(name: String, arguments: [String: String]) async throws -> [String: Any] {
        let payload = try await callToolJSON(name: name, arguments: arguments)
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected the '\(name)' MCP tool to return a top-level JSON object, but received '\(type(of: payload))'."
            )
        }
        return object
    }

    func callToolJSON(name: String, arguments: [String: String]) async throws -> Any {
        let response = try await Self.post(
            baseURL: baseURL,
            path: path,
            jsonBody: [
                "jsonrpc": "2.0",
                "id": UUID().uuidString,
                "method": "tools/call",
                "params": [
                    "name": name,
                    "arguments": arguments,
                ],
            ],
            sessionID: sessionID
        )
        let envelope = try parseMCPEnvelope(from: response.data)
        if let error = envelope["error"] as? [String: Any] {
            throw E2ETransportError("The live MCP tools/call request for '\(name)' failed with payload: \(error)")
        }
        let result = try requireDictionary("result", in: envelope)
        let content = try requireArray("content", in: result)
        let first = try requireFirstDictionary(in: content)
        let text = try requireString("text", in: first)
        return try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    func readResourceText(uri: String) async throws -> String {
        let response = try await Self.post(
            baseURL: baseURL,
            path: path,
            jsonBody: [
                "jsonrpc": "2.0",
                "id": UUID().uuidString,
                "method": "resources/read",
                "params": ["uri": uri],
            ],
            sessionID: sessionID
        )
        let envelope = try parseMCPEnvelope(from: response.data)
        if let error = envelope["error"] as? [String: Any] {
            throw E2ETransportError("The live MCP resources/read request for '\(uri)' failed with payload: \(error)")
        }
        let result = try requireDictionary("result", in: envelope)
        let contents = try requireArray("contents", in: result)
        let first = try requireFirstDictionary(in: contents)
        return try requireString("text", in: first)
    }

    private static func post(
        baseURL: URL,
        path: String,
        jsonBody: [String: Any],
        sessionID: String?
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2ETransportError("The live MCP transport did not return an HTTPURLResponse.")
        }
        return E2EHTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, data: data)
    }
}

// MARK: - Transport Waiters

private func waitUntilWorkerReady(
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before `/readyz` reported readiness.\n\(server.combinedOutput)"
            )
        }

        let response: E2EHTTPResponse
        do {
            response = try await client.request(path: "/readyz", method: "GET")
        } catch {
            guard isRetryableConnectionDuringStartup(error) else {
                throw error
            }
            return nil
        }
        guard response.statusCode == 200 else { return nil }
        let readiness = try decode(E2EReadinessSnapshot.self, from: response.data)
        return readiness.workerReady ? true : nil
    }
}

private func waitUntilWorkerReady(
    using client: E2EMCPClient,
    timeout: Duration,
    server: ServerProcess
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before the MCP status tool reported readiness.\n\(server.combinedOutput)"
            )
        }

        let payload = try await client.callTool(name: "status", arguments: [:])
        guard payload["worker_mode"] as? String == "ready" else { return nil }
        return true
    }
}

private func waitForTerminalJob(
    id jobID: String,
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before job '\(jobID)' reached a terminal state.\n\(server.combinedOutput)"
            )
        }

        let response = try await client.request(path: "/jobs/\(jobID)", method: "GET")
        guard response.statusCode == 200 else { return nil }
        let snapshot = try decode(E2EJobSnapshot.self, from: response.data)
        return snapshot.terminalEvent == nil ? nil : snapshot
    }
}

private func waitForTerminalJob(
    id jobID: String,
    using client: E2EMCPClient,
    timeout: Duration,
    server: ServerProcess
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before MCP job resource '\(jobID)' reached a terminal state.\n\(server.combinedOutput)"
            )
        }

        let text = try await client.readResourceText(uri: "speak://jobs/\(jobID)")
        let snapshot = try decode(E2EJobSnapshot.self, from: Data(text.utf8))
        return snapshot.terminalEvent == nil ? nil : snapshot
    }
}

private func e2eWaitUntil<T>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping () async throws -> T?
) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(for: pollInterval)
    }
    throw E2ETimeoutError()
}

// MARK: - Stored Profile Helpers

private struct StoredProfileManifest: Decodable, Sendable {
    let sourceText: String
}

private func loadStoredProfileManifest(named profileName: String, from rootURL: URL) throws -> StoredProfileManifest {
    let manifestURL = rootURL
        .appendingPathComponent(profileName, isDirectory: true)
        .appendingPathComponent("profile.json", isDirectory: false)
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONSerialization.jsonObject(with: data)
    guard let object = manifest as? [String: Any] else {
        throw E2ETransportError(
            "The stored profile manifest at '\(manifestURL.path)' did not decode into a JSON object."
        )
    }

    let sourceText =
        object["source_text"] as? String
        ?? object["sourceText"] as? String
        ?? object["transcript"] as? String

    guard let sourceText else {
        let availableKeys = object.keys.sorted().joined(separator: ", ")
        throw E2ETransportError(
            "The stored profile manifest at '\(manifestURL.path)' did not contain a usable source-text field. Available keys: [\(availableKeys)]."
        )
    }

    return .init(sourceText: sourceText)
}

// MARK: - JSON Helpers

private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try JSONDecoder().decode(Value.self, from: data)
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    if let dictionaries = json as? [[String: Any]] {
        guard let dictionary = dictionaries.first else {
            throw E2ETransportError("Expected at least one JSON object in the live end-to-end helper array payload, but the array was empty.")
        }
        return dictionary
    }
    guard let dictionary = json as? [String: Any] else {
        throw E2ETransportError("Expected a top-level JSON object in the live end-to-end helper, but received '\(type(of: json))'.")
    }
    return dictionary
}

private func parseMCPEnvelope(from data: Data) throws -> [String: Any] {
    let body = String(decoding: data, as: UTF8.self)
    if let dataLine = body
        .split(separator: "\n")
        .reversed()
        .first(where: {
            $0.hasPrefix("data: ")
                && $0.dropFirst("data: ".count).isEmpty == false
        })
    {
        let payload = dataLine.dropFirst("data: ".count)
        guard payload.isEmpty == false else {
            throw E2ETransportError("The live MCP response contained an empty `data:` payload. Raw body: \(body)")
        }
        return try mcpEnvelope(from: Data(payload.utf8), rawBody: body)
    }
    return try mcpEnvelope(from: data, rawBody: body)
}

private func mcpEnvelope(from data: Data, rawBody: String) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    if let dictionary = json as? [String: Any] {
        return dictionary
    }

    if let dictionaries = json as? [[String: Any]] {
        if let envelope = dictionaries.first(where: { $0["result"] != nil || $0["error"] != nil }) {
            return envelope
        }
        if let first = dictionaries.first {
            return first
        }
        throw E2ETransportError("The live MCP response decoded to an empty envelope array. Raw body: \(rawBody)")
    }

    throw E2ETransportError("Expected the live MCP response to decode into a JSON-RPC object or array of objects, but received '\(type(of: json))'. Raw body: \(rawBody)")
}

private func requireMCPHeader(_ name: String, in headers: [AnyHashable: Any]) throws -> String {
    for (key, value) in headers {
        if String(describing: key).caseInsensitiveCompare(name) == .orderedSame,
           let stringValue = value as? String,
           stringValue.isEmpty == false
        {
            return stringValue
        }
    }
    throw E2ETransportError("The live MCP initialize response was missing the required '\(name)' header.")
}

private func requireDictionary(_ key: String, in object: [String: Any]) throws -> [String: Any] {
    guard let value = object[key] as? [String: Any] else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be a JSON object.")
    }
    return value
}

private func requireArray(_ key: String, in object: [String: Any]) throws -> [[String: Any]] {
    guard let value = object[key] as? [[String: Any]] else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be an array of JSON objects.")
    }
    return value
}

private func requireFirstDictionary(in array: [[String: Any]]) throws -> [String: Any] {
    guard let first = array.first else {
        throw E2ETransportError("The live end-to-end helper expected at least one object in the MCP content array.")
    }
    return first
}

private func requireString(_ key: String, in object: [String: Any]) throws -> String {
    guard let value = object[key] as? String, value.isEmpty == false else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be a non-empty string.")
    }
    return value
}

private func requireProfiles(from payload: Any) throws -> [E2EProfileSnapshot] {
    if let profiles = payload as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    if let profile = payload as? [String: Any], profile["profile_name"] != nil {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": [profile]])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    guard let payload = payload as? [String: Any] else {
        throw E2ETransportError(
            "The live end-to-end helper expected the profile list payload to decode into a JSON object or array, but received '\(type(of: payload))'."
        )
    }

    if let profiles = payload["profiles"] as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    if let wrappedProfiles = payload["profiles"] as? [String: Any] {
        if let profiles = wrappedProfiles["profiles"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
            return try decode(E2EProfileListResponse.self, from: data).profiles
        }
        if let items = wrappedProfiles["items"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["profiles": items])
            return try decode(E2EProfileListResponse.self, from: data).profiles
        }
    }

    if let profiles = payload["items"] as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    let availableKeys = payload.keys.sorted().joined(separator: ", ")
    throw E2ETransportError(
        "The live end-to-end helper could not find a decodable profile list in the MCP payload. Available top-level keys: [\(availableKeys)]."
    )
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - Error Helpers

private struct E2ETimeoutError: Error {}

private struct E2ETransportError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct SpeakSwiftlyBuildError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func isRetryableConnectionDuringStartup(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    return nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorNetworkConnectionLost
}

// MARK: - Decodable Transport Models

private struct E2EReadinessSnapshot: Decodable, Sendable {
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case workerReady = "worker_ready"
    }
}

private struct E2EJobCreatedResponse: Decodable, Sendable {
    let jobID: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}

private struct E2EProfileListResponse: Decodable, Sendable {
    let profiles: [E2EProfileSnapshot]
}

private struct E2EProfileSnapshot: Decodable, Sendable {
    let profileName: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
    }
}

private struct E2EJobSnapshot: Decodable, Sendable {
    let jobID: String
    let status: String
    let history: [E2EJobEvent]
    let terminalEvent: E2EJobEvent?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case status
        case history
        case terminalEvent = "terminal_event"
    }
}

private struct E2EJobEvent: Decodable, Sendable {
    let id: String?
    let event: String?
    let op: String?
    let stage: String?
    let ok: Bool?
    let profileName: String?
    let profilePath: String?
    let message: String?
    let code: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case op
        case stage
        case ok
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case message
        case code
    }
}
