import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Clone End-to-End Lane

extension ServerE2E {
    static func runCloneLane(
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
                _ = try await runAudibleSpeech(
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
                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )
            }
        }
    }
}
