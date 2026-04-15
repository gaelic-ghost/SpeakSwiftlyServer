import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Relative Path End-to-End Lane

extension ServerE2E {
    static func runRelativePathProfileAndCloneLane(using transport: E2ETransport) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let callerWorkingDirectory = sandbox.rootURL.appendingPathComponent("\(transport.profilePrefix)-caller-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: callerWorkingDirectory, withIntermediateDirectories: true)

        let relativeReferencePath = "exports/reference.wav"
        let exportedReferenceURL = callerWorkingDirectory.appending(path: relativeReferencePath)
        let fixtureProfileName = "\(transport.profilePrefix)-relative-profile-source"
        let cloneProfileName = "\(transport.profilePrefix)-relative-profile-clone"

        let server = try makeServer(
            port: randomPort(in: 58600..<58800),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: transport == .mcp,
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
                    outputPath: relativeReferencePath,
                    cwd: callerWorkingDirectory.path,
                )
                #expect(FileManager.default.fileExists(atPath: exportedReferenceURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: relativeReferencePath,
                    transcript: testingCloneSourceText,
                    expectTranscription: false,
                    cwd: callerWorkingDirectory.path,
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server,
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: fixtureProfileName,
                    text: testingCloneSourceText,
                    voiceDescription: testingProfileVoiceDescription,
                    outputPath: relativeReferencePath,
                    cwd: callerWorkingDirectory.path,
                )
                #expect(FileManager.default.fileExists(atPath: exportedReferenceURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: relativeReferencePath,
                    transcript: testingCloneSourceText,
                    expectTranscription: false,
                    cwd: callerWorkingDirectory.path,
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)
        }

        let storedProfile = try loadStoredProfileManifest(
            named: cloneProfileName,
            from: sandbox.profileRootURL,
        )
        #expect(storedProfile.sourceText == testingCloneSourceText)
    }
}
