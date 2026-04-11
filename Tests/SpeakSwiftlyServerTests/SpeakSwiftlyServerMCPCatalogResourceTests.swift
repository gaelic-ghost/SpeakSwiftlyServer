import Foundation
import MCP
import Testing
@testable import SpeakSwiftlyServer

// MARK: - MCP Catalog Resource Tests

extension SpeakSwiftlyServerTests {
    @available(macOS 14, *)
    @Test func embeddedMCPRoutesExposeReadableResourcesAndGuidancePrompts() async throws {
        try await Self.withEmbeddedMCPSurface { _, _, mcpSurface, sessionID in
            let seedRequestEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_speech",
                            arguments: [
                                "text": "Inspect MCP resources",
                                "profile_name": "default",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let seedRequestPayload = try mcpToolPayload(from: seedRequestEnvelope)
            let requestID = try #require(seedRequestPayload["request_id"] as? String)

            _ = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"id":"mcp-text","name":"MCP Text","replacements":[]}}}"#,
                        sessionID: sessionID
                    )
                )
            )

            let getPromptEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "draft_profile_voice_description",
                            arguments: [
                                "profile_goal": "gentle narration",
                                "voice_traits": "warm, steady, intimate",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let getPromptResult = try #require(mcpResultPayload(from: getPromptEnvelope))
            let promptMessages = try #require(getPromptResult["messages"] as? [[String: Any]])
            let firstPromptMessage = try #require(promptMessages.first)
            let promptContent = try #require(firstPromptMessage["content"] as? [String: Any])
            #expect((promptContent["text"] as? String)?.contains("gentle narration") == true)

            let textProfilePromptEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "draft_text_profile",
                            arguments: [
                                "user_goal": "expand acronyms in technical speech",
                                "profile_scope": "swift package walkthroughs",
                                "format_focus": "swift_source",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let textProfilePromptResult = try #require(mcpResultPayload(from: textProfilePromptEnvelope))
            let textProfilePromptMessages = try #require(textProfilePromptResult["messages"] as? [[String: Any]])
            let textProfilePromptContent = try #require(textProfilePromptMessages.first?["content"] as? [String: Any])
            #expect((textProfilePromptContent["text"] as? String)?.contains("expand acronyms in technical speech") == true)

            let runtimeResourceEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://runtime/overview"),
                        sessionID: sessionID
                    )
                )
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
            #expect(runtimeRefresh["source"] as? String == "runtime_overview")

            let runtimeStatusResourceEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://runtime/status"),
                        sessionID: sessionID
                    )
                )
            )
            let runtimeStatusResourceResult = try #require(mcpResultPayload(from: runtimeStatusResourceEnvelope))
            let runtimeStatusContents = try #require(runtimeStatusResourceResult["contents"] as? [[String: Any]])
            let runtimeStatusText = try #require(runtimeStatusContents.first?["text"] as? String)
            let runtimeStatusPayload = try jsonObject(from: Data(runtimeStatusText.utf8))
            let runtimeStatus = try #require(runtimeStatusPayload["status"] as? [String: Any])
            #expect(runtimeStatus["speech_backend"] as? String == "qwen3")

            let runtimeConfigResourceEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://runtime/configuration"),
                        sessionID: sessionID
                    )
                )
            )
            let runtimeConfigResourceResult = try #require(mcpResultPayload(from: runtimeConfigResourceEnvelope))
            let runtimeConfigContents = try #require(runtimeConfigResourceResult["contents"] as? [[String: Any]])
            let runtimeConfigText = try #require(runtimeConfigContents.first?["text"] as? String)
            let runtimeConfigPayload = try jsonObject(from: Data(runtimeConfigText.utf8))
            #expect(runtimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3")

            let jobsResourceEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://requests"),
                        sessionID: sessionID
                    )
                )
            )
            let jobsResourceResult = try #require(mcpResultPayload(from: jobsResourceEnvelope))
            let jobsContents = try #require(jobsResourceResult["contents"] as? [[String: Any]])
            let jobsText = try #require(jobsContents.first?["text"] as? String)
            let jobsPayload = try #require(try JSONSerialization.jsonObject(with: Data(jobsText.utf8)) as? [[String: Any]])
            #expect(jobsPayload.contains { $0["request_id"] as? String == requestID })

            let profileDetailEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://voices/default"),
                        sessionID: sessionID
                    )
                )
            )
            let profileDetailResult = try #require(mcpResultPayload(from: profileDetailEnvelope))
            let profileDetailContents = try #require(profileDetailResult["contents"] as? [[String: Any]])
            let profileDetailText = try #require(profileDetailContents.first?["text"] as? String)
            let profileDetailPayload = try jsonObject(from: Data(profileDetailText.utf8))
            #expect(profileDetailPayload["profile_name"] as? String == "default")

            let textProfilesResourceEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://text-profiles"),
                        sessionID: sessionID
                    )
                )
            )
            let textProfilesResourceResult = try #require(mcpResultPayload(from: textProfilesResourceEnvelope))
            let textProfilesContents = try #require(textProfilesResourceResult["contents"] as? [[String: Any]])
            let textProfilesText = try #require(textProfilesContents.first?["text"] as? String)
            let textProfilesPayload = try jsonObject(from: Data(textProfilesText.utf8))
            #expect(textProfilesPayload["built_in_style"] as? String == "balanced")
            let storedProfilesPayload = try #require(textProfilesPayload["stored_profiles"] as? [[String: Any]])
            #expect(storedProfilesPayload.contains { $0["id"] as? String == "mcp-text" })

            let textProfileStyleEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/style"),
                        sessionID: sessionID
                    )
                )
            )
            let textProfileStyleResult = try #require(mcpResultPayload(from: textProfileStyleEnvelope))
            let textProfileStyleContents = try #require(textProfileStyleResult["contents"] as? [[String: Any]])
            let textProfileStyleText = try #require(textProfileStyleContents.first?["text"] as? String)
            let textProfileStylePayload = try jsonObject(from: Data(textProfileStyleText.utf8))
            let textProfileStyle = try #require(textProfileStylePayload["built_in_style"] as? String)
            #expect(textProfileStyle == "balanced")

            let textProfilesGuideEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/guide"),
                        sessionID: sessionID
                    )
                )
            )
            let textProfilesGuideResult = try #require(mcpResultPayload(from: textProfilesGuideEnvelope))
            let textProfilesGuideContents = try #require(textProfilesGuideResult["contents"] as? [[String: Any]])
            let textProfilesGuideText = try #require(textProfilesGuideContents.first?["text"] as? String)
            #expect(textProfilesGuideText.contains("text_profile_name"))
            #expect(textProfilesGuideText.contains("set_text_profile_style"))

            let voiceProfilesGuideEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://voices/guide"),
                        sessionID: sessionID
                    )
                )
            )
            let voiceProfilesGuideResult = try #require(mcpResultPayload(from: voiceProfilesGuideEnvelope))
            let voiceProfilesGuideContents = try #require(voiceProfilesGuideResult["contents"] as? [[String: Any]])
            let voiceProfilesGuideText = try #require(voiceProfilesGuideContents.first?["text"] as? String)
            #expect(voiceProfilesGuideText.contains("create_voice_profile_from_audio"))
            #expect(voiceProfilesGuideText.contains("update_voice_profile_name"))
            #expect(voiceProfilesGuideText.contains("reroll_voice_profile"))
            #expect(voiceProfilesGuideText.contains("generate_speech"))

            let playbackGuideEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://playback/guide"),
                        sessionID: sessionID
                    )
                )
            )
            let playbackGuideResult = try #require(mcpResultPayload(from: playbackGuideEnvelope))
            let playbackGuideContents = try #require(playbackGuideResult["contents"] as? [[String: Any]])
            let playbackGuideText = try #require(playbackGuideContents.first?["text"] as? String)
            #expect(playbackGuideText.contains("cancel_request"))
            #expect(playbackGuideText.contains("clear_playback_queue"))

            let chooseActionPromptEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpGetPromptRequestJSON(
                            name: "choose_surface_action",
                            arguments: [
                                "user_goal": "Help the user decide whether to clone a voice or create a synthetic profile.",
                                "current_context": "The user has not provided reference audio yet.",
                            ]
                        ),
                        sessionID: sessionID
                    )
                )
            )
            let chooseActionPromptResult = try #require(mcpResultPayload(from: chooseActionPromptEnvelope))
            let chooseActionPromptMessages = try #require(chooseActionPromptResult["messages"] as? [[String: Any]])
            let chooseActionPromptContent = try #require(chooseActionPromptMessages.first?["content"] as? [String: Any])
            let chooseActionPromptText = try #require(chooseActionPromptContent["text"] as? String)
            #expect(chooseActionPromptText.contains("action_type"))
            #expect(chooseActionPromptText.contains("create_voice_profile_from_description"))

            let storedTextProfileEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/stored/mcp-text"),
                        sessionID: sessionID
                    )
                )
            )
            let storedTextProfileResult = try #require(mcpResultPayload(from: storedTextProfileEnvelope))
            let storedTextProfileContents = try #require(storedTextProfileResult["contents"] as? [[String: Any]])
            let storedTextProfileText = try #require(storedTextProfileContents.first?["text"] as? String)
            let storedTextProfilePayload = try jsonObject(from: Data(storedTextProfileText.utf8))
            #expect(storedTextProfilePayload["id"] as? String == "mcp-text")

            let jobDetailEnvelope = try await mcpEnvelope(
                from: await mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpReadResourceRequestJSON(uri: "speak://requests/\(requestID)"),
                        sessionID: sessionID
                    )
                )
            )
            let jobDetailResult = try #require(mcpResultPayload(from: jobDetailEnvelope))
            let jobDetailContents = try #require(jobDetailResult["contents"] as? [[String: Any]])
            let jobDetailText = try #require(jobDetailContents.first?["text"] as? String)
            let jobDetailPayload = try jsonObject(from: Data(jobDetailText.utf8))
            #expect(jobDetailPayload["request_id"] as? String == requestID)
        }
    }
}
