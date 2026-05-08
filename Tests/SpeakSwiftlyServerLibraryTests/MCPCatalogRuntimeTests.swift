import Foundation
import MCP
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - MCP Catalog Runtime Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP routes drive speech runtime and text profile tools`() async throws {
        try await Self.withEmbeddedMCPSurface { runtime, _, mcpSurface, sessionID in
            let queueSpeechToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_speech",
                            argumentsJSON: #"{"text":"Inspect MCP resources","profile_name":"default","text_profile_id":"mcp-text","request_context":{"source":"mcp","topic":"catalog-runtime","attributes":{"caller.app":"SpeakSwiftlyServerLibraryTests","caller.project":"SpeakSwiftlyServer","surface":"mcp"}},"cwd":"./Tests","repo_root":".","source_format":"source_code","qwen_pre_model_text_chunking":true}"#,
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let queueSpeechToolPayload = try mcpToolPayload(from: queueSpeechToolEnvelope)
            let requestID = try #require(queueSpeechToolPayload["request_id"] as? String)
            #expect(queueSpeechToolPayload["status_resource_uri"] as? String == "speak-swiftly://overview")
            #expect(queueSpeechToolPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(requestID)")
            let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
            #expect(queuedSpeechInvocation.textProfileID == "mcp-text")
            #expect(queuedSpeechInvocation.sourceFormat == .generic)
            #expect(queuedSpeechInvocation.qwenPreModelTextChunking == true)
            #expect(
                queuedSpeechInvocation.requestContext
                    == SpeakSwiftly.RequestContext(
                        source: "mcp",
                        topic: "catalog-runtime",
                        cwd: "./Tests",
                        repoRoot: ".",
                        attributes: [
                            "caller.app": "SpeakSwiftlyServerLibraryTests",
                            "caller.project": "SpeakSwiftlyServer",
                            "mcp.client.display_name": "ServerTests via SpeakSwiftlyServer",
                            "mcp.client.name": "ServerTests",
                            "mcp.client.version": "1.0",
                            "mcp.tool": "generate_speech",
                            "server.app": "SpeakSwiftlyServer",
                            "surface": "mcp",
                        ],
                    ),
            )

            let cancelSpeechToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "cancel_request",
                            arguments: [
                                "request_id": requestID,
                                "scope": "generation",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let cancelSpeechToolPayload = try mcpToolPayload(from: cancelSpeechToolEnvelope)
            #expect(cancelSpeechToolPayload["cancelled_request_id"] as? String == requestID)

            let retainedAudioToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_audio_file",
                            argumentsJSON: #"{"text":"Default MCP context","profile_name":"default"}"#,
                            id: "tool-retained-audio-1",
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let retainedAudioPayload = try mcpToolPayload(from: retainedAudioToolEnvelope)
            let retainedAudioRequestID = try #require(retainedAudioPayload["request_id"] as? String)
            #expect(retainedAudioPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(retainedAudioRequestID)")
            let retainedAudioArtifact = try #require(await runtime.generationArtifacts.last)
            #expect(
                retainedAudioArtifact.requestContext
                    == SpeakSwiftly.RequestContext(
                        source: "mcp",
                        topic: "generate_audio_file",
                        attributes: [
                            "mcp.client.display_name": "ServerTests via SpeakSwiftlyServer",
                            "mcp.client.name": "ServerTests",
                            "mcp.client.version": "1.0",
                            "mcp.tool": "generate_audio_file",
                            "server.app": "SpeakSwiftlyServer",
                            "surface": "mcp",
                        ],
                    ),
            )

            let createCloneToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "create_voice_profile_from_audio",
                            arguments: [
                                "profile_name": "clone-from-mcp",
                                "vibe": "femme",
                                "reference_audio_path": "./Fixtures/mcp-reference.wav",
                                "transcript": "Imported from MCP",
                                "cwd": "./mcp-clone-cwd",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let createCloneToolPayload = try mcpToolPayload(from: createCloneToolEnvelope)
            let createCloneRequestID = try #require(createCloneToolPayload["request_id"] as? String)
            #expect(createCloneToolPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(createCloneRequestID)")
            let createCloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
            #expect(createCloneInvocation.profileName == "clone-from-mcp")
            #expect(createCloneInvocation.vibe == .femme)
            #expect(createCloneInvocation.referenceAudioPath == "./Fixtures/mcp-reference.wav")
            #expect(createCloneInvocation.transcript == "Imported from MCP")
            #expect(createCloneInvocation.cwd == "./mcp-clone-cwd")

            let renameVoiceToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "update_voice_profile_name",
                            arguments: [
                                "profile_name": "clone-from-mcp",
                                "new_profile_name": "clone-from-mcp-renamed",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let renameVoiceToolPayload = try mcpToolPayload(from: renameVoiceToolEnvelope)
            let renameVoiceRequestID = try #require(renameVoiceToolPayload["request_id"] as? String)
            #expect(renameVoiceToolPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(renameVoiceRequestID)")
            let renameVoiceInvocation = try #require(await runtime.latestRenameProfileInvocation())
            #expect(renameVoiceInvocation.profileName == "clone-from-mcp")
            #expect(renameVoiceInvocation.newProfileName == "clone-from-mcp-renamed")

            let rerollVoiceToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "reroll_voice_profile",
                            arguments: [
                                "profile_name": "clone-from-mcp-renamed",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let rerollVoiceToolPayload = try mcpToolPayload(from: rerollVoiceToolEnvelope)
            let rerollVoiceRequestID = try #require(rerollVoiceToolPayload["request_id"] as? String)
            #expect(rerollVoiceToolPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(rerollVoiceRequestID)")
            let rerollVoiceInvocation = try #require(await runtime.latestRerollProfileInvocation())
            #expect(rerollVoiceInvocation.profileName == "clone-from-mcp-renamed")

            let createTextProfileEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"name":"MCP Text","replacements":[{"id":"mcp-replacement","text":"CLI","replacement":"command line interface","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["cli_output"],"priority":1}]}}}"#,
                        sessionID: sessionID,
                    ),
                ),
            )
            let createTextProfilePayload = try mcpToolPayload(from: createTextProfileEnvelope)
            #expect(createTextProfilePayload["profile_id"] as? String == "mcp-text")

            let listTextProfilesEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let listTextProfilesPayload = try mcpResourceObjectPayload(from: listTextProfilesEnvelope)
            #expect(listTextProfilesPayload["built_in_style"] as? String == "balanced")
            let listTextStoredProfiles = try #require(listTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(listTextStoredProfiles.contains { $0["profile_id"] as? String == "mcp-text" })

            let getTextProfileStyleEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles/style"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let getTextProfileStylePayload = try mcpResourceObjectPayload(from: getTextProfileStyleEnvelope)
            #expect(getTextProfileStylePayload["built_in_style"] as? String == "balanced")

            let setTextProfileStyleEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_text_profile_style",
                            arguments: ["built_in_style": "compact"],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let setTextProfileStylePayload = try mcpToolPayload(from: setTextProfileStyleEnvelope)
            #expect(setTextProfileStylePayload["built_in_style"] as? String == "compact")

            let loadTextProfilesEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "load_text_profiles", arguments: [:]),
                        sessionID: sessionID,
                    ),
                ),
            )
            let loadTextProfilesPayload = try mcpToolPayload(from: loadTextProfilesEnvelope)
            let loadedStoredProfiles = try #require(loadTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(loadedStoredProfiles.contains { $0["profile_id"] as? String == "mcp-text" })

            let saveTextProfilesEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(name: "save_text_profiles", arguments: [:]),
                        sessionID: sessionID,
                    ),
                ),
            )
            let saveTextProfilesPayload = try mcpToolPayload(from: saveTextProfilesEnvelope)
            let savedStoredProfiles = try #require(saveTextProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(savedStoredProfiles.contains { $0["profile_id"] as? String == "mcp-text" })
            let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
            #expect(persistenceActionCounts.load == 1)
            #expect(persistenceActionCounts.save == 1)

            let statusResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://overview"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let statusResourcePayload = try mcpResourceObjectPayload(from: statusResourceEnvelope)
            #expect(statusResourcePayload["worker_mode"] as? String == "ready")
            let statusRuntimeConfiguration = try #require(statusResourcePayload["runtime_configuration"] as? [String: Any])
            #expect(statusRuntimeConfiguration["active_runtime_speech_backend"] as? String == "qwen3_smol")
            #expect(statusRuntimeConfiguration["active_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(statusRuntimeConfiguration["next_qwen_resident_model"] as? String == "base_0_6b_8bit")
            let transports = try #require(statusResourcePayload["transports"] as? [[String: Any]])
            #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })

            let runtimeConfigResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://configuration"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let getRuntimeConfigPayload = try mcpResourceObjectPayload(from: runtimeConfigResourceEnvelope)
            #expect(getRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3_smol")
            #expect(getRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "qwen3_smol")
            #expect(getRuntimeConfigPayload["active_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(getRuntimeConfigPayload["next_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(getRuntimeConfigPayload["active_marvis_resident_policy"] as? String == "dual_resident_serialized")
            #expect(getRuntimeConfigPayload["next_marvis_resident_policy"] as? String == "dual_resident_serialized")

            let setRuntimeConfigEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_runtime_configuration",
                            arguments: [
                                "speech_backend": "marvis",
                                "qwen_resident_model": "base_1_7b_8bit",
                                "marvis_resident_policy": "single_resident_dynamic",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let setRuntimeConfigPayload = try mcpToolPayload(from: setRuntimeConfigEnvelope)
            #expect(setRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3_smol")
            #expect(setRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "marvis")
            #expect(setRuntimeConfigPayload["active_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(setRuntimeConfigPayload["next_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(setRuntimeConfigPayload["active_marvis_resident_policy"] as? String == "dual_resident_serialized")
            #expect(setRuntimeConfigPayload["next_marvis_resident_policy"] as? String == "single_resident_dynamic")
            #expect(setRuntimeConfigPayload["persisted_speech_backend"] as? String == "marvis")
            #expect(setRuntimeConfigPayload["persisted_qwen_resident_model"] as? String == "base_0_6b_8bit")
            #expect(setRuntimeConfigPayload["persisted_marvis_resident_policy"] as? String == "single_resident_dynamic")

            let switchBackendEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "switch_speech_backend",
                            arguments: ["speech_backend": "marvis"],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let switchBackendPayload = try mcpToolPayload(from: switchBackendEnvelope)
            let switchBackendRequestID = try #require(switchBackendPayload["request_id"] as? String)
            #expect(switchBackendPayload["request_resource_uri"] as? String == "speak-swiftly://requests/\(switchBackendRequestID)")
            #expect(switchBackendPayload["status_resource_uri"] as? String == "speak-swiftly://overview")

            let setChatterboxRuntimeConfigEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_runtime_configuration",
                            arguments: ["speech_backend": "chatterbox_turbo"],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let setChatterboxRuntimeConfigPayload = try mcpToolPayload(from: setChatterboxRuntimeConfigEnvelope)
            #expect(setChatterboxRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "chatterbox_turbo")
            #expect(setChatterboxRuntimeConfigPayload["persisted_speech_backend"] as? String == "chatterbox_turbo")

            let setQuantizedRuntimeConfigEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "set_runtime_configuration",
                            arguments: ["speech_backend": "qwen3_big_4bit"],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let setQuantizedRuntimeConfigPayload = try mcpToolPayload(from: setQuantizedRuntimeConfigEnvelope)
            #expect(setQuantizedRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "qwen3_big_4bit")
            #expect(setQuantizedRuntimeConfigPayload["next_qwen_resident_model"] as? String == "base_1_7b_8bit")
            #expect(setQuantizedRuntimeConfigPayload["persisted_speech_backend"] as? String == "qwen3_big_4bit")
        }
    }
}
