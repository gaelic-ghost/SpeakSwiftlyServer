import Foundation
import MCP
import SpeakSwiftly
import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
import SSSHTTP
import SSSMCP
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
            #expect(textProfilesGuideText.contains("HTTP text-profile endpoints"))
            #expect(textProfilesGuideText.contains("GET /text-profiles/effective/{profile_id}"))

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
            #expect(voiceProfilesGuideText.contains("POST /voices/from-audio"))
            #expect(voiceProfilesGuideText.contains("PUT /voices/{profile_name}/name"))
            #expect(voiceProfilesGuideText.contains("POST /voices/{profile_name}/reroll"))
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
            #expect(playbackGuideText.contains("DELETE /requests/{request_id}"))
            #expect(playbackGuideText.contains("cancel_generation") == false)
            #expect(playbackGuideText.contains("cancel_playback") == false)
            #expect(playbackGuideText.contains("HTTP `scope` query parameter"))
            #expect(playbackGuideText.contains("DELETE /generation/queue"))
            #expect(playbackGuideText.contains("DELETE /playback/queue"))
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
            #expect(chooseActionPromptText.contains("HTTP-only actions"))
            #expect(chooseActionPromptText.contains("speak-swiftly://playback"))
            #expect(chooseActionPromptText.contains("action_type must be one of tool, resource, prompt, or http"))

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
