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
            #expect(tools.contains { $0["name"] as? String == "get_runtime_configuration" })
            #expect(tools.contains { $0["name"] as? String == "set_runtime_configuration" })
            #expect(tools.contains { $0["name"] as? String == "get_staged_runtime_config" })
            #expect(tools.contains { $0["name"] as? String == "set_staged_config" })
            #expect(tools.contains { $0["name"] as? String == "get_runtime_overview" })
            #expect(tools.contains { $0["name"] as? String == "clear_generation_queue" })
            #expect(tools.contains { $0["name"] as? String == "clear_playback_queue" })
            #expect(tools.contains { $0["name"] as? String == "cancel_generation" })
            #expect(tools.contains { $0["name"] as? String == "cancel_playback" })
            let cancelRequestTool = try #require(tools.first { $0["name"] as? String == "cancel_request" })
            #expect((cancelRequestTool["description"] as? String)?.contains("Optionally set scope") == true)
            let cancelRequestSchema = try #require(cancelRequestTool["inputSchema"] as? [String: Any])
            let cancelRequestProperties = try #require(cancelRequestSchema["properties"] as? [String: Any])
            let cancelRequestScope = try #require(cancelRequestProperties["scope"] as? [String: Any])
            let cancelRequestScopeEnum = try #require(cancelRequestScope["enum"] as? [String])
            #expect(cancelRequestScopeEnum == ["generation", "playback"])
            let getRuntimeOverviewTool = try #require(tools.first { $0["name"] as? String == "get_runtime_overview" })
            #expect((getRuntimeOverviewTool["description"] as? String)?.contains("Prefer reading speak://runtime/overview") == true)
            let listVoiceProfilesTool = try #require(tools.first { $0["name"] as? String == "list_voice_profiles" })
            #expect((listVoiceProfilesTool["description"] as? String)?.contains("Prefer reading speak://voices") == true)
            let getPlaybackStateTool = try #require(tools.first { $0["name"] as? String == "get_playback_state" })
            #expect((getPlaybackStateTool["description"] as? String)?.contains("Prefer reading speak://runtime/overview") == true)
            let getRuntimeConfigurationTool = try #require(tools.first { $0["name"] as? String == "get_runtime_configuration" })
            #expect((getRuntimeConfigurationTool["description"] as? String)?.contains("Prefer reading speak://runtime/configuration") == true)
            let getStagedRuntimeConfigTool = try #require(tools.first { $0["name"] as? String == "get_staged_runtime_config" })
            #expect((getStagedRuntimeConfigTool["description"] as? String)?.contains("Compatibility alias") == true)
            let setRuntimeConfigurationTool = try #require(tools.first { $0["name"] as? String == "set_runtime_configuration" })
            #expect((setRuntimeConfigurationTool["description"] as? String)?.contains("Persist runtime startup choices") == true)
            let setStagedConfigTool = try #require(tools.first { $0["name"] as? String == "set_staged_config" })
            #expect((setStagedConfigTool["description"] as? String)?.contains("Compatibility alias") == true)
            let setRuntimeConfigurationSchema = try #require(setRuntimeConfigurationTool["inputSchema"] as? [String: Any])
            let setRuntimeConfigurationProperties = try #require(setRuntimeConfigurationSchema["properties"] as? [String: Any])
            let setRuntimeConfigurationBackend = try #require(setRuntimeConfigurationProperties["speech_backend"] as? [String: Any])
            let setRuntimeConfigurationBackendEnum = try #require(setRuntimeConfigurationBackend["enum"] as? [String])
            #expect(setRuntimeConfigurationBackendEnum == ["qwen3", "chatterbox_turbo", "marvis"])
            let setRuntimeConfigurationQwenModel = try #require(setRuntimeConfigurationProperties["qwen_resident_model"] as? [String: Any])
            let setRuntimeConfigurationQwenModelEnum = try #require(setRuntimeConfigurationQwenModel["enum"] as? [String])
            #expect(setRuntimeConfigurationQwenModelEnum == ["base_0_6b_8bit", "base_1_7b_8bit"])
            let setRuntimeConfigurationMarvisPolicy = try #require(setRuntimeConfigurationProperties["marvis_resident_policy"] as? [String: Any])
            let setRuntimeConfigurationMarvisPolicyEnum = try #require(setRuntimeConfigurationMarvisPolicy["enum"] as? [String])
            #expect(setRuntimeConfigurationMarvisPolicyEnum == ["dual_resident_serialized", "single_resident_dynamic"])

            let generateSpeechTool = try #require(tools.first { $0["name"] as? String == "generate_speech" })
            let generateSpeechSchema = try #require(generateSpeechTool["inputSchema"] as? [String: Any])
            let generateSpeechProperties = try #require(generateSpeechSchema["properties"] as? [String: Any])
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
            #expect(resources.contains { $0["uri"] as? String == "speak://runtime/overview" })
            #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles" })
            #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles/style" })
            #expect(resources.contains { $0["uri"] as? String == "speak://voices/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak://playback/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak://requests" })
            #expect(resources.contains { $0["uri"] as? String == "speak://runtime/configuration" })
            #expect(resources.contains { $0["uri"] as? String == "speak://runtime/status" })

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
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak://voices/{profile_name}" })
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak://text-profiles/stored/{profile_id}" })
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak://requests/{request_id}" })

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
