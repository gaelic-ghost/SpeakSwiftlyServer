import Foundation
import MCP
@testable import SpeakSwiftlyServer
import Testing

// MARK: - MCP Catalog Listing Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP routes list tools resources templates and prompts`() async throws {
        try await Self.withEmbeddedMCPSurface { _, _, mcpSurface, sessionID in
            let listToolsEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpListToolsRequestJSON(),
                        sessionID: sessionID,
                    ),
                ),
            )
            let listToolsResult = try #require(mcpResultPayload(from: listToolsEnvelope))
            let tools = try #require(listToolsResult["tools"] as? [[String: Any]])
            let toolNames = Set(tools.compactMap { $0["name"] as? String })
            #expect(toolNames == Set(MCPToolCatalog.definitions.map(\.name)))
            #expect(tools.contains { $0["name"] as? String == "generate_speech" })
            #expect(tools.contains { $0["name"] as? String == "create_voice_profile_from_audio" })
            #expect(tools.contains { $0["name"] as? String == "update_voice_profile_name" })
            #expect(tools.contains { $0["name"] as? String == "reroll_voice_profile" })
            #expect(tools.contains { $0["name"] as? String == "set_runtime_configuration" })
            #expect(tools.contains { $0["name"] as? String == "get_staged_runtime_config" } == false)
            #expect(tools.contains { $0["name"] as? String == "set_staged_config" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_runtime_overview" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_runtime_status" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_runtime_configuration" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_voice_profiles" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_text_normalizer_snapshot" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_text_profile_style" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_generation_queue" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_playback_queue" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_playback_state" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_active_requests" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_generation_jobs" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_generation_job" } == false)
            #expect(tools.contains { $0["name"] as? String == "clear_generation_queue" })
            #expect(tools.contains { $0["name"] as? String == "clear_playback_queue" })
            #expect(tools.contains { $0["name"] as? String == "cancel_generation" } == false)
            #expect(tools.contains { $0["name"] as? String == "cancel_playback" } == false)
            let cancelRequestTool = try #require(tools.first { $0["name"] as? String == "cancel_request" })
            #expect((cancelRequestTool["description"] as? String)?.contains("Optionally set scope") == true)
            let cancelRequestSchema = try #require(cancelRequestTool["inputSchema"] as? [String: Any])
            let cancelRequestProperties = try #require(cancelRequestSchema["properties"] as? [String: Any])
            let cancelRequestScope = try #require(cancelRequestProperties["scope"] as? [String: Any])
            let cancelRequestScopeEnum = try #require(cancelRequestScope["enum"] as? [String])
            #expect(cancelRequestScopeEnum == ["generation", "playback"])
            let setRuntimeConfigurationTool = try #require(tools.first { $0["name"] as? String == "set_runtime_configuration" })
            #expect((setRuntimeConfigurationTool["description"] as? String)?.contains("Persist the speech backend") == true)
            let setRuntimeConfigurationSchema = try #require(setRuntimeConfigurationTool["inputSchema"] as? [String: Any])
            let setRuntimeConfigurationProperties = try #require(setRuntimeConfigurationSchema["properties"] as? [String: Any])
            let setRuntimeConfigurationBackend = try #require(setRuntimeConfigurationProperties["speech_backend"] as? [String: Any])
            let setRuntimeConfigurationBackendEnum = try #require(setRuntimeConfigurationBackend["enum"] as? [String])
            #expect(setRuntimeConfigurationBackendEnum == [
                "qwen3_smol",
                "qwen3_smol_4bit",
                "qwen3_smol_5bit",
                "qwen3_smol_6bit",
                "qwen3_smol_8bit",
                "qwen3_smol_bf16",
                "qwen3_big",
                "qwen3_big_4bit",
                "qwen3_big_5bit",
                "qwen3_big_6bit",
                "qwen3_big_8bit",
                "qwen3_big_bf16",
                "chatterbox_turbo",
                "marvis",
                "marvis_4bit",
                "marvis_6bit",
            ])
            #expect(setRuntimeConfigurationProperties["qwen_resident_model"] == nil)
            #expect(setRuntimeConfigurationProperties["marvis_resident_policy"] == nil)

            let generateSpeechTool = try #require(tools.first { $0["name"] as? String == "generate_speech" })
            let generateSpeechSchema = try #require(generateSpeechTool["inputSchema"] as? [String: Any])
            let generateSpeechProperties = try #require(generateSpeechSchema["properties"] as? [String: Any])
            #expect(generateSpeechProperties["source_format"] == nil)
            let generateSpeechContext = try #require(generateSpeechProperties["request_context"] as? [String: Any])
            let generateSpeechContextProperties = try #require(generateSpeechContext["properties"] as? [String: Any])
            #expect(generateSpeechContextProperties["reqPurpose"] == nil)
            let prefacePolicy = try #require(generateSpeechContextProperties["prefacePolicy"] as? [String: Any])
            #expect(prefacePolicy["enum"] as? [String] == ["default", "always", "never"])
            let qwenPreModelTextChunking = try #require(generateSpeechProperties["qwen_pre_model_text_chunking"] as? [String: Any])
            #expect(qwenPreModelTextChunking["type"] as? String == "boolean")

            let listResourcesEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpListResourcesRequestJSON(),
                        sessionID: sessionID,
                    ),
                ),
            )
            let listResourcesResult = try #require(mcpResultPayload(from: listResourcesEnvelope))
            let resources = try #require(listResourcesResult["resources"] as? [[String: Any]])
            let resourceURIs = Set(resources.compactMap { $0["uri"] as? String })
            #expect(resourceURIs == Set(MCPResourceCatalog.resources.map(\.uri)))
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://overview" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://text-profiles" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://text-profiles/style" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://voices/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://text-profiles/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://playback" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://playback/queue" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://playback/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://requests" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://configuration" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://status" })

            let listResourceTemplatesEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpListResourceTemplatesRequestJSON(),
                        sessionID: sessionID,
                    ),
                ),
            )
            let listResourceTemplatesResult = try #require(mcpResultPayload(from: listResourceTemplatesEnvelope))
            let templates = try #require(listResourceTemplatesResult["resourceTemplates"] as? [[String: Any]])
            let templateURIs = Set(templates.compactMap { $0["uriTemplate"] as? String })
            #expect(templateURIs == Set(MCPResourceCatalog.templates.map(\.uriTemplate)))
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak-swiftly://voices/{profile_name}" })
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak-swiftly://text-profiles/stored/{profile_id}" })
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak-swiftly://requests/{request_id}" })

            let listPromptsEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpListPromptsRequestJSON(),
                        sessionID: sessionID,
                    ),
                ),
            )
            let listPromptsResult = try #require(mcpResultPayload(from: listPromptsEnvelope))
            let prompts = try #require(listPromptsResult["prompts"] as? [[String: Any]])
            let promptNames = Set(prompts.compactMap { $0["name"] as? String })
            #expect(promptNames == Set(MCPPromptCatalog.prompts.map(\.name)))
            #expect(prompts.contains { $0["name"] as? String == "draft_profile_voice_description" })
            #expect(prompts.contains { $0["name"] as? String == "draft_text_profile" })
            #expect(prompts.contains { $0["name"] as? String == "draft_text_replacement" })
            #expect(prompts.contains { $0["name"] as? String == "draft_queue_playback_notice" })
            #expect(prompts.contains { $0["name"] as? String == "choose_surface_action" })
        }
    }
}
