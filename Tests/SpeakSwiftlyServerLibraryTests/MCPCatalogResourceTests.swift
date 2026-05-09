import Foundation
import MCP
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - MCP Catalog Resource Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP routes expose readable resources and guidance prompts`() async throws {
        try await Self.withEmbeddedMCPSurface { _, _, mcpSurface, sessionID in
            let seedRequestEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_speech",
                            arguments: [
                                "text": "Inspect MCP resources",
                                "profile_name": "default",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let seedRequestPayload = try mcpToolPayload(from: seedRequestEnvelope)
            let requestID = try #require(seedRequestPayload["request_id"] as? String)

            _ = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"name":"MCP Text","replacements":[]}}}"#,
                        sessionID: sessionID,
                    ),
                ),
            )

            let getPromptEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "draft_profile_voice_description",
                            arguments: [
                                "profile_goal": "gentle narration",
                                "voice_traits": "warm, steady, intimate",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let getPromptResult = try #require(mcpResultPayload(from: getPromptEnvelope))
            let promptMessages = try #require(getPromptResult["messages"] as? [[String: Any]])
            let firstPromptMessage = try #require(promptMessages.first)
            let promptContent = try #require(firstPromptMessage["content"] as? [String: Any])
            #expect((promptContent["text"] as? String)?.contains("gentle narration") == true)
            #expect((promptContent["text"] as? String)?.contains("Make the description self-contained") == true)

            let voiceDesignPromptEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "draft_voice_design_instruction",
                            arguments: [
                                "spoken_text": "I can keep going.",
                                "emotion": "encouraging",
                                "delivery_style": "warm and focused",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let voiceDesignPromptResult = try #require(mcpResultPayload(from: voiceDesignPromptEnvelope))
            let voiceDesignPromptMessages = try #require(voiceDesignPromptResult["messages"] as? [[String: Any]])
            let voiceDesignPromptContent = try #require(voiceDesignPromptMessages.first?["content"] as? [String: Any])
            #expect((voiceDesignPromptContent["text"] as? String)?.contains("not a remembered prior voice design") == true)

            let voiceGuideEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://voices/guide"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let voiceGuideResult = try #require(mcpResultPayload(from: voiceGuideEnvelope))
            let voiceGuideContents = try #require(voiceGuideResult["contents"] as? [[String: Any]])
            let voiceGuideText = try #require(voiceGuideContents.first?["text"] as? String)
            #expect(voiceGuideText.contains("Qwen voice-design guidance"))

            let textProfilePromptEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "draft_text_profile",
                            arguments: [
                                "user_goal": "expand acronyms in technical speech",
                                "profile_scope": "swift package walkthroughs",
                                "format_focus": "swift_source",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let textProfilePromptResult = try #require(mcpResultPayload(from: textProfilePromptEnvelope))
            let textProfilePromptMessages = try #require(textProfilePromptResult["messages"] as? [[String: Any]])
            let textProfilePromptContent = try #require(textProfilePromptMessages.first?["content"] as? [String: Any])
            #expect((textProfilePromptContent["text"] as? String)?.contains("expand acronyms in technical speech") == true)

            let runtimeResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://overview"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let runtimeResourceResult = try #require(mcpResultPayload(from: runtimeResourceEnvelope))
            let contents = try #require(runtimeResourceResult["contents"] as? [[String: Any]])
            let firstContent = try #require(contents.first)
            let runtimeText = try #require(firstContent["text"] as? String)
            let runtimePayload = try jsonObject(from: Data(runtimeText.utf8))
            let runtimeTransports = try #require(runtimePayload["transports"] as? [[String: Any]])
            #expect(runtimeTransports.contains { $0["name"] as? String == "mcp" && $0["advertised_address"] as? String == "http://127.0.0.1:7337/mcp" })
            let runtimeRefresh = try #require(runtimePayload["runtime_refresh"] as? [String: Any])
            #expect((runtimeRefresh["sequence_id"] as? Int ?? 0) > 0)
            #expect(runtimeRefresh["source"] as? String == "runtime_snapshots")

            let runtimeStatusResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://status"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let runtimeStatusResourceResult = try #require(mcpResultPayload(from: runtimeStatusResourceEnvelope))
            let runtimeStatusContents = try #require(runtimeStatusResourceResult["contents"] as? [[String: Any]])
            let runtimeStatusText = try #require(runtimeStatusContents.first?["text"] as? String)
            let runtimeStatusPayload = try jsonObject(from: Data(runtimeStatusText.utf8))
            #expect(runtimeStatusPayload["speech_backend"] as? String == "qwen3_smol")
            #expect(runtimeStatusPayload["runtime_backend_transition"] is [String: Any])

            let runtimeConfigResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://configuration"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let runtimeConfigResourceResult = try #require(mcpResultPayload(from: runtimeConfigResourceEnvelope))
            let runtimeConfigContents = try #require(runtimeConfigResourceResult["contents"] as? [[String: Any]])
            let runtimeConfigText = try #require(runtimeConfigContents.first?["text"] as? String)
            let runtimeConfigPayload = try jsonObject(from: Data(runtimeConfigText.utf8))
            #expect(runtimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3_smol")

            let playbackResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://playback"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let playbackResourceResult = try #require(mcpResultPayload(from: playbackResourceEnvelope))
            let playbackContents = try #require(playbackResourceResult["contents"] as? [[String: Any]])
            let playbackText = try #require(playbackContents.first?["text"] as? String)
            let playbackPayload = try jsonObject(from: Data(playbackText.utf8))
            let playbackState = try #require(playbackPayload["playback"] as? [String: Any])
            #expect(playbackState["state"] as? String != nil)

            let playbackQueueResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://playback/queue"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let playbackQueueResourceResult = try #require(mcpResultPayload(from: playbackQueueResourceEnvelope))
            let playbackQueueContents = try #require(playbackQueueResourceResult["contents"] as? [[String: Any]])
            let playbackQueueText = try #require(playbackQueueContents.first?["text"] as? String)
            let playbackQueuePayload = try jsonObject(from: Data(playbackQueueText.utf8))
            #expect(playbackQueuePayload["queue_type"] as? String == "playback")

            let jobsResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://requests"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let jobsResourceResult = try #require(mcpResultPayload(from: jobsResourceEnvelope))
            let jobsContents = try #require(jobsResourceResult["contents"] as? [[String: Any]])
            let jobsText = try #require(jobsContents.first?["text"] as? String)
            let jobsPayload = try #require(try JSONSerialization.jsonObject(with: Data(jobsText.utf8)) as? [[String: Any]])
            #expect(jobsPayload.contains { $0["request_id"] as? String == requestID })

            let profileDetailEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://voices/default"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let profileDetailResult = try #require(mcpResultPayload(from: profileDetailEnvelope))
            let profileDetailContents = try #require(profileDetailResult["contents"] as? [[String: Any]])
            let profileDetailText = try #require(profileDetailContents.first?["text"] as? String)
            let profileDetailPayload = try jsonObject(from: Data(profileDetailText.utf8))
            #expect(profileDetailPayload["profile_name"] as? String == "default")

            let builtInProfileEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://voices/swift-signal"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let builtInProfileResult = try #require(mcpResultPayload(from: builtInProfileEnvelope))
            let builtInProfileContents = try #require(builtInProfileResult["contents"] as? [[String: Any]])
            let builtInProfileText = try #require(builtInProfileContents.first?["text"] as? String)
            let builtInProfilePayload = try jsonObject(from: Data(builtInProfileText.utf8))
            #expect(builtInProfilePayload["profile_name"] as? String == "swift-signal")
            #expect(builtInProfilePayload["author"] as? String == "system")
            #expect(builtInProfilePayload["seed_id"] as? String == "swift.signal")
            #expect((builtInProfilePayload["source_text"] as? String)?.contains("maintainer/tool surfaces") == true)
            #expect((builtInProfilePayload["voice_description"] as? String)?.contains("maintainer/tool surfaces") == true)

            let textProfilesResourceEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let textProfilesResourceResult = try #require(mcpResultPayload(from: textProfilesResourceEnvelope))
            let textProfilesContents = try #require(textProfilesResourceResult["contents"] as? [[String: Any]])
            let textProfilesText = try #require(textProfilesContents.first?["text"] as? String)
            let textProfilesPayload = try jsonObject(from: Data(textProfilesText.utf8))
            #expect(textProfilesPayload["built_in_style"] as? String == "balanced")
            let storedProfilesPayload = try #require(textProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(storedProfilesPayload.contains { $0["profile_id"] as? String == "mcp-text" })

            let textProfileStyleEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles/style"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let textProfileStyleResult = try #require(mcpResultPayload(from: textProfileStyleEnvelope))
            let textProfileStyleContents = try #require(textProfileStyleResult["contents"] as? [[String: Any]])
            let textProfileStyleText = try #require(textProfileStyleContents.first?["text"] as? String)
            let textProfileStylePayload = try jsonObject(from: Data(textProfileStyleText.utf8))
            let textProfileStyle = try #require(textProfileStylePayload["built_in_style"] as? String)
            #expect(textProfileStyle == "balanced")

            let textProfilesGuideEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles/guide"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let textProfilesGuideResult = try #require(mcpResultPayload(from: textProfilesGuideEnvelope))
            let textProfilesGuideContents = try #require(textProfilesGuideResult["contents"] as? [[String: Any]])
            let textProfilesGuideText = try #require(textProfilesGuideContents.first?["text"] as? String)
            #expect(textProfilesGuideText.contains("text_profile_id"))
            #expect(textProfilesGuideText.contains("set_text_profile_style"))
            #expect(textProfilesGuideText.contains("Read `speak-swiftly://text-profiles/style`"))

            let voiceProfilesGuideEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://voices/guide"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let voiceProfilesGuideResult = try #require(mcpResultPayload(from: voiceProfilesGuideEnvelope))
            let voiceProfilesGuideContents = try #require(voiceProfilesGuideResult["contents"] as? [[String: Any]])
            let voiceProfilesGuideText = try #require(voiceProfilesGuideContents.first?["text"] as? String)
            #expect(voiceProfilesGuideText.contains("create_voice_profile_from_audio"))
            #expect(voiceProfilesGuideText.contains("update_voice_profile_name"))
            #expect(voiceProfilesGuideText.contains("reroll_voice_profile"))
            #expect(voiceProfilesGuideText.contains("generate_speech"))
            #expect(voiceProfilesGuideText.contains("Read `speak-swiftly://voices` to inspect the currently cached voice profiles."))
            #expect(voiceProfilesGuideText.contains("SpeakSwiftly's bundled system-profile install"))

            let playbackGuideEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://playback/guide"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let playbackGuideResult = try #require(mcpResultPayload(from: playbackGuideEnvelope))
            let playbackGuideContents = try #require(playbackGuideResult["contents"] as? [[String: Any]])
            let playbackGuideText = try #require(playbackGuideContents.first?["text"] as? String)
            #expect(playbackGuideText.contains("cancel_request"))
            #expect(playbackGuideText.contains("cancel_generation") == false)
            #expect(playbackGuideText.contains("cancel_playback") == false)
            #expect(playbackGuideText.contains("Use `cancel_request` when the user wants one known request stopped by id"))
            #expect(playbackGuideText.contains("Add `scope` to `cancel_request` only when the user explicitly wants to constrain cancellation"))
            #expect(playbackGuideText.contains("clear_generation_queue"))
            #expect(playbackGuideText.contains("clear_playback_queue"))
            #expect(playbackGuideText.contains("Read `speak-swiftly://overview` first"))
            #expect(playbackGuideText.contains("Playback freshness is currently host-event-driven"))

            let chooseActionPromptEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "choose_surface_action",
                            arguments: [
                                "user_goal": "Help the user decide whether to clone a voice or create a synthetic profile.",
                                "current_context": "The user has not provided reference audio yet.",
                            ],
                        ),
                        sessionID: sessionID,
                    ),
                ),
            )
            let chooseActionPromptResult = try #require(mcpResultPayload(from: chooseActionPromptEnvelope))
            let chooseActionPromptMessages = try #require(chooseActionPromptResult["messages"] as? [[String: Any]])
            let chooseActionPromptContent = try #require(chooseActionPromptMessages.first?["content"] as? [String: Any])
            let chooseActionPromptText = try #require(chooseActionPromptContent["text"] as? String)
            #expect(chooseActionPromptText.contains("action_type"))
            #expect(chooseActionPromptText.contains("create_voice_profile_from_description"))
            #expect(chooseActionPromptText.contains("speak-swiftly://playback"))
            #expect(chooseActionPromptText.contains("speak-swiftly://playback/queue"))
            #expect(chooseActionPromptText.contains("for read-only inspection, use a speak-swiftly:// resource"))
            #expect(chooseActionPromptText.contains("Use tools for queueing, mutation, cancellation, clearing, playback control, and runtime changes."))

            let storedTextProfileEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles/stored/mcp-text"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let storedTextProfileResult = try #require(mcpResultPayload(from: storedTextProfileEnvelope))
            let storedTextProfileContents = try #require(storedTextProfileResult["contents"] as? [[String: Any]])
            let storedTextProfileText = try #require(storedTextProfileContents.first?["text"] as? String)
            let storedTextProfilePayload = try jsonObject(from: Data(storedTextProfileText.utf8))
            #expect(storedTextProfilePayload["profile_id"] as? String == "mcp-text")

            let jobDetailEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak-swiftly://requests/\(requestID)"),
                        sessionID: sessionID,
                    ),
                ),
            )
            let jobDetailResult = try #require(mcpResultPayload(from: jobDetailEnvelope))
            let jobDetailContents = try #require(jobDetailResult["contents"] as? [[String: Any]])
            let jobDetailText = try #require(jobDetailContents.first?["text"] as? String)
            let jobDetailPayload = try jsonObject(from: Data(jobDetailText.utf8))
            #expect(jobDetailPayload["request_id"] as? String == requestID)
        }
    }

    @available(macOS 14, *)
    @Test func `embedded MCP text profile resources surface transport failures as explicit jsonrpc errors`() async throws {
        let runtime = MockRuntime(
            speakBehavior: .holdOpen,
            textProfileTransportError: SpeakSwiftly.Error(
                code: .internalError,
                message: "Configured MCP text-profile transport failure for tests.",
            ),
        )
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        let host = ServerHost(
            configuration: configuration,
            httpConfig: testHTTPConfig(configuration),
            mcpConfig: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP",
            ),
            runtime: runtime,
            runtimeStartupConfigurationStore: .init(
                environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
                activeRuntimeSpeechBackend: .qwen3_smol,
            ),
            state: state,
        )

        await host.start()
        await runtime.publishStatus(.residentModelReady)
        try await waitUntilReady(host)
        let mcpSurface = try #require(
            await MCPSurface.build(
                configuration: .init(
                    enabled: true,
                    path: "/mcp",
                    serverName: "speak-swiftly-test-mcp",
                    title: "SpeakSwiftly Test MCP",
                ),
                host: host,
            ),
        )

        try await mcpSurface.start()
        let initializeResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let sessionID = try #require(mcpSessionID(from: initializeResponse))
        try await drainMCPResponse(initializeResponse)
        _ = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: sessionID,
            ),
        )

        let envelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpReadResourceRequestJSON(uri: "speak-swiftly://text-profiles"),
                    sessionID: sessionID,
                ),
            ),
        )
        let error = try #require(envelope["error"] as? [String: Any])
        let message = try #require(error["message"] as? String)
        #expect((error["code"] as? Int) == -32603)
        #expect(message.contains("Configured MCP text-profile transport failure for tests."))
    }
}
