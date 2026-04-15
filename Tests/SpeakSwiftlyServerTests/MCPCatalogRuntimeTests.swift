import Foundation
import MCP
import Testing
@testable import SpeakSwiftlyServer

// MARK: - MCP Catalog Runtime Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func embeddedMCPRoutesDriveSpeechRuntimeAndTextProfileTools() async throws {
        try await Self.withEmbeddedMCPSurface { runtime, _, mcpSurface, sessionID in
            let queueSpeechToolEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_speech",
                            arguments: [
                                "text": "Inspect MCP resources",
                                "profile_name": "default",
                                "text_profile_name": "mcp-text",
                                "cwd": "./Tests",
                                "repo_root": "../SpeakSwiftlyServer",
                                "text_format": "cli_output",
                                "nested_source_format": "rust_source",
                                "source_format": "source_code",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let queueSpeechToolPayload = try mcpToolPayload(from: queueSpeechToolEnvelope)
            let requestID = try #require(queueSpeechToolPayload["request_id"] as? String)
            #expect(queueSpeechToolPayload["status_resource_uri"] as? String == "speak://runtime/overview")
            #expect(queueSpeechToolPayload["request_resource_uri"] as? String == "speak://requests/\(requestID)")
            let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
            #expect(
                queuedSpeechInvocation.normalizationContext
                    == SpeechNormalizationContext(
                        cwd: "./Tests",
                        repoRoot: "../SpeakSwiftlyServer",
                        textFormat: .cli,
                        nestedSourceFormat: .rust
                    )
            )
            #expect(queuedSpeechInvocation.textProfileName == "mcp-text")
            #expect(queuedSpeechInvocation.sourceFormat == .generic)

            let createCloneToolEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "create_voice_profile_from_audio",
                            arguments: [
                                "profile_name": "clone-from-mcp",
                                "vibe": "androgenous",
                                "reference_audio_path": "./Fixtures/mcp-reference.wav",
                                "transcript": "Imported from MCP",
                                "cwd": "/tmp/mcp-clone-cwd",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let createCloneToolPayload = try mcpToolPayload(from: createCloneToolEnvelope)
            let createCloneRequestID = try #require(createCloneToolPayload["request_id"] as? String)
            #expect(createCloneToolPayload["request_resource_uri"] as? String == "speak://requests/\(createCloneRequestID)")
            let createCloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
            #expect(createCloneInvocation.profileName == "clone-from-mcp")
            #expect(createCloneInvocation.vibe == .androgenous)
            #expect(createCloneInvocation.referenceAudioPath == "./Fixtures/mcp-reference.wav")
            #expect(createCloneInvocation.transcript == "Imported from MCP")
            #expect(createCloneInvocation.cwd == "/tmp/mcp-clone-cwd")

            let renameVoiceToolEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "update_voice_profile_name",
                            arguments: [
                                "profile_name": "clone-from-mcp",
                                "new_profile_name": "clone-from-mcp-renamed",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let renameVoiceToolPayload = try mcpToolPayload(from: renameVoiceToolEnvelope)
            let renameVoiceRequestID = try #require(renameVoiceToolPayload["request_id"] as? String)
            #expect(renameVoiceToolPayload["request_resource_uri"] as? String == "speak://requests/\(renameVoiceRequestID)")
            let renameVoiceInvocation = try #require(await runtime.latestRenameProfileInvocation())
            #expect(renameVoiceInvocation.profileName == "clone-from-mcp")
            #expect(renameVoiceInvocation.newProfileName == "clone-from-mcp-renamed")

            let rerollVoiceToolEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "reroll_voice_profile",
                            arguments: [
                                "profile_name": "clone-from-mcp-renamed",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let rerollVoiceToolPayload = try mcpToolPayload(from: rerollVoiceToolEnvelope)
            let rerollVoiceRequestID = try #require(rerollVoiceToolPayload["request_id"] as? String)
            #expect(rerollVoiceToolPayload["request_resource_uri"] as? String == "speak://requests/\(rerollVoiceRequestID)")
            let rerollVoiceInvocation = try #require(await runtime.latestRerollProfileInvocation())
            #expect(rerollVoiceInvocation.profileName == "clone-from-mcp-renamed")

            let createTextProfileEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"id":"mcp-text","name":"MCP Text","replacements":[{"id":"mcp-replacement","text":"CLI","replacement":"command line interface","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["cli_output"],"priority":1}]}}}"#,
                        sessionID: sessionID
                    )
                )
            )
            let createTextProfilePayload = try mcpToolPayload(from: createTextProfileEnvelope)
            #expect(createTextProfilePayload["id"] as? String == "mcp-text")

            let listTextProfilesEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "get_text_normalizer_snapshot",
                            arguments: [:]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let listTextProfilesPayload = try mcpToolPayload(from: listTextProfilesEnvelope)
            #expect(listTextProfilesPayload["built_in_style"] as? String == "balanced")
            let listTextStoredProfiles = try #require(listTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(listTextStoredProfiles.contains { $0["id"] as? String == "mcp-text" })

            let getTextProfileStyleEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "get_text_profile_style", arguments: [:]),
                        sessionID: sessionID
                    )
                )
            )
            let getTextProfileStylePayload = try mcpToolPayload(from: getTextProfileStyleEnvelope)
            #expect(getTextProfileStylePayload["built_in_style"] as? String == "balanced")

            let setTextProfileStyleEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_text_profile_style",
                            arguments: ["built_in_style": "compact"]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let setTextProfileStylePayload = try mcpToolPayload(from: setTextProfileStyleEnvelope)
            #expect(setTextProfileStylePayload["built_in_style"] as? String == "compact")

            let loadTextProfilesEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "load_text_profiles", arguments: [:]),
                        sessionID: sessionID
                    )
                )
            )
            let loadTextProfilesPayload = try mcpToolPayload(from: loadTextProfilesEnvelope)
            let loadedStoredProfiles = try #require(loadTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(loadedStoredProfiles.contains { $0["id"] as? String == "mcp-text" })

            let saveTextProfilesEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "save_text_profiles", arguments: [:]),
                        sessionID: sessionID
                    )
                )
            )
            let saveTextProfilesPayload = try mcpToolPayload(from: saveTextProfilesEnvelope)
            let savedStoredProfiles = try #require(saveTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(savedStoredProfiles.contains { $0["id"] as? String == "mcp-text" })
            let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
            #expect(persistenceActionCounts.load == 1)
            #expect(persistenceActionCounts.save == 1)

            let statusToolEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "get_runtime_overview", arguments: [:]),
                        sessionID: sessionID
                    )
                )
            )
            let statusToolPayload = try mcpToolPayload(from: statusToolEnvelope)
            #expect(statusToolPayload["worker_mode"] as? String == "ready")
            let statusRuntimeConfiguration = try #require(statusToolPayload["runtime_configuration"] as? [String: Any])
            #expect(statusRuntimeConfiguration["active_runtime_speech_backend"] as? String == "qwen3")
            let transports = try #require(statusToolPayload["transports"] as? [[String: Any]])
            #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })

            let getRuntimeConfigEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "get_staged_runtime_config", arguments: [:]),
                        sessionID: sessionID
                    )
                )
            )
            let getRuntimeConfigPayload = try mcpToolPayload(from: getRuntimeConfigEnvelope)
            #expect(getRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3")
            #expect(getRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "qwen3")

            let setRuntimeConfigEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_staged_config",
                            arguments: ["speech_backend": "marvis"]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let setRuntimeConfigPayload = try mcpToolPayload(from: setRuntimeConfigEnvelope)
            #expect(setRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3")
            #expect(setRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "marvis")
            #expect(setRuntimeConfigPayload["persisted_speech_backend"] as? String == "marvis")
        }
    }
}
