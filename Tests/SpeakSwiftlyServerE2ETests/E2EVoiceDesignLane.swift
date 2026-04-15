import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Voice Design End-to-End Lane

extension ServerE2E {
    static func runVoiceDesignLane(using transport: E2ETransport) async throws {
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

                _ = try await runAudibleSpeech(
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

                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )
            }
        }
    }
}
