import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Marvis End-to-End Lane

extension ServerE2E {
    static func runMarvisTripletLane(using transport: E2ETransport) async throws {
        struct MarvisProfileLane {
            let profileName: String
            let vibe: String
            let voiceDescription: String
            let expectedVoice: String
        }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let prefix = transport.profilePrefix
        let lanes = [
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-femme-profile",
                vibe: "femme",
                voiceDescription: "A warm, bright, feminine narrator voice.",
                expectedVoice: "conversational_a",
            ),
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-masc-profile",
                vibe: "masc",
                voiceDescription: "A grounded, rich, masculine speaking voice.",
                expectedVoice: "conversational_b",
            ),
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-androgenous-profile",
                vibe: "androgenous",
                voiceDescription: "A calm, balanced, and gentle speaking voice.",
                expectedVoice: "conversational_a",
            ),
        ]

        let server = try makeServer(
            port: randomPort(in: 58800..<59000),
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
                    expectPlaybackEngine: true,
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

                let profilesResponse = try await client.request(path: "/voices", method: "GET")
                #expect(profilesResponse.statusCode == 200)
                let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
                for lane in lanes {
                    #expect(profiles.contains {
                        $0.profileName == lane.profileName && $0.vibe == lane.vibe
                    })
                }

                for lane in lanes {
                    let jobID = try await runAudibleSpeech(
                        using: client,
                        server: server,
                        text: testingPlaybackText,
                        profileName: lane.profileName,
                    )
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
                    expectPlaybackEngine: true,
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

                let profilesPayload = try await client.callToolJSON(name: "list_voice_profiles", arguments: [:])
                let profiles = try requireProfiles(from: profilesPayload)
                for lane in lanes {
                    #expect(profiles.contains {
                        $0.profileName == lane.profileName && $0.vibe == lane.vibe
                    })
                }

                for lane in lanes {
                    let jobID = try await runAudibleSpeech(
                        using: client,
                        server: server,
                        text: testingPlaybackText,
                        profileName: lane.profileName,
                    )
                    try await expectMarvisVoiceSelection(
                        on: server,
                        requestID: jobID,
                        expectedVoice: lane.expectedVoice,
                    )
                }
        }
    }
}
