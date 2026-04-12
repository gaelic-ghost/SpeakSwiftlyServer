import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - HTTP Control Surface End-to-End Tests

extension SpeakSwiftlyServerE2EControlSurfaceTests {
    @Test func httpTextProfileLifecycleCoversStoredActiveEffectiveAndPersistenceFlows() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59_700..<59_800),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: false
        )
        try server.start()
        defer { server.stop() }

        let client = E2EHTTPClient(baseURL: server.baseURL)
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let initialTextProfiles = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles", method: "GET").data
        ).textProfiles
        #expect(initialTextProfiles.builtInStyle == "balanced")
        #expect(initialTextProfiles.baseProfile.id.isEmpty == false)
        #expect(initialTextProfiles.activeProfile.id.isEmpty == false)

        let initialTextProfileStyle = try decode(
            E2ETextProfileStyleResponse.self,
            from: try await client.request(path: "/text-profiles/style", method: "GET").data
        ).textProfileStyle
        #expect(initialTextProfileStyle.builtInStyle == "balanced")

        let createdStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored",
                method: "POST",
                jsonBody: [
                    "id": "http-text-profile",
                    "name": "HTTP Text Profile",
                    "replacements": [
                        Self.replacementJSON(
                            id: "expand-swift",
                            text: "SPM",
                            replacement: "Swift Package Manager",
                            formats: ["swift_source"]
                        ),
                    ],
                ]
            ).data
        ).profile
        #expect(createdStored.id == "http-text-profile")
        #expect(createdStored.replacements.count == 1)

        let storedRoute = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/stored/http-text-profile", method: "GET").data
        ).profile
        #expect(storedRoute.id == "http-text-profile")

        let replacedStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile",
                method: "PUT",
                jsonBody: [
                    "profile": [
                        "id": "http-text-profile",
                        "name": "HTTP Text Profile Updated",
                        "replacements": [
                            Self.replacementJSON(
                                id: "expand-swift",
                                text: "SPM",
                                replacement: "Swift Package Manager",
                                formats: ["swift_source"]
                            ),
                            Self.replacementJSON(
                                id: "expand-mcp",
                                text: "MCP",
                                replacement: "Model Context Protocol"
                            ),
                        ],
                    ],
                ]
            ).data
        ).profile
        #expect(replacedStored.name == "HTTP Text Profile Updated")
        #expect(replacedStored.replacements.count == 2)

        let storedWithAddedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements",
                method: "POST",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-tts",
                        text: "TTS",
                        replacement: "text to speech"
                    ),
                ]
            ).data
        ).profile
        #expect(storedWithAddedReplacement.replacements.contains { $0.id == "expand-tts" })

        let storedWithReplacedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements/expand-tts",
                method: "PUT",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-tts",
                        text: "TTS",
                        replacement: "text-to-speech",
                        phase: "after_built_ins"
                    ),
                ]
            ).data
        ).profile
        let replacedTTSRule = storedWithReplacedReplacement.replacements.first { $0.id == "expand-tts" }
        #expect(replacedTTSRule?.replacement == "text-to-speech")
        #expect(replacedTTSRule?.phase == "after_built_ins")

        let activeProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active",
                method: "PUT",
                jsonBody: [
                    "profile": [
                        "id": "http-session-profile",
                        "name": "HTTP Session Profile",
                        "replacements": [
                            Self.replacementJSON(
                                id: "expand-cwd",
                                text: "cwd",
                                replacement: "current working directory",
                                match: "whole_token"
                            ),
                        ],
                    ],
                ]
            ).data
        ).profile
        #expect(activeProfile.id == "http-session-profile")

        let activeWithAddedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements",
                method: "POST",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-repo",
                        text: "repo",
                        replacement: "repository"
                    ),
                ]
            ).data
        ).profile
        #expect(activeWithAddedReplacement.replacements.contains { $0.id == "expand-repo" })

        let activeWithReplacedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements/expand-repo",
                method: "PUT",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-repo",
                        text: "repo",
                        replacement: "source repository",
                        formats: ["markdown"]
                    ),
                ]
            ).data
        ).profile
        #expect(activeWithReplacedReplacement.replacements.contains {
            $0.id == "expand-repo" && $0.replacement == "source repository"
        })

        let activeAfterRemoval = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements/expand-repo",
                method: "DELETE"
            ).data
        ).profile
        #expect(activeAfterRemoval.replacements.contains { $0.id == "expand-repo" } == false)

        let effectiveDefault = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/effective", method: "GET").data
        ).profile
        #expect(effectiveDefault.id == "http-session-profile")

        let effectiveStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/effective/http-text-profile", method: "GET").data
        ).profile
        #expect(effectiveStored.id == "http-text-profile")

        let baseProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/base", method: "GET").data
        ).profile
        #expect(baseProfile.id.isEmpty == false)

        let savedSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/save", method: "POST").data
        ).textProfiles
        #expect(savedSnapshot.storedProfiles.contains { $0.id == "http-text-profile" })

        let compactSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(
                path: "/text-profiles/style",
                method: "PUT",
                jsonBody: ["built_in_style": "compact"]
            ).data
        ).textProfiles
        #expect(compactSnapshot.builtInStyle == "compact")

        let loadedSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/load", method: "POST").data
        ).textProfiles
        #expect(loadedSnapshot.storedProfiles.contains { $0.id == "http-text-profile" })
        #expect(loadedSnapshot.builtInStyle == "compact")

        let resetProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/active/reset", method: "POST").data
        ).profile
        #expect(resetProfile.id == initialTextProfiles.activeProfile.id)

        let storedAfterStoredRemoval = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements/expand-tts",
                method: "DELETE"
            ).data
        ).profile
        #expect(storedAfterStoredRemoval.replacements.contains { $0.id == "expand-tts" } == false)

        let finalSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/stored/http-text-profile", method: "DELETE").data
        ).textProfiles
        #expect(finalSnapshot.storedProfiles.contains { $0.id == "http-text-profile" } == false)
    }
}
