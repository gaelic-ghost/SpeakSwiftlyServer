import Foundation
import MCP
import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
import SSSHTTP
import SSSMCP
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
            #expect(toolNames == ["generate_speech"])
            #expect(tools.contains { $0["name"] as? String == "generate_speech" })
            #expect(tools.contains { $0["name"] as? String == "create_voice_profile_from_audio" } == false)
            #expect(tools.contains { $0["name"] as? String == "update_voice_profile_name" } == false)
            #expect(tools.contains { $0["name"] as? String == "reroll_voice_profile" } == false)
            #expect(tools.contains { $0["name"] as? String == "set_runtime_configuration" } == false)
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
            #expect(tools.contains { $0["name"] as? String == "clear_generation_queue" } == false)
            #expect(tools.contains { $0["name"] as? String == "clear_playback_queue" } == false)
            #expect(tools.contains { $0["name"] as? String == "list_recent_generated_audio" } == false)
            #expect(tools.contains { $0["name"] as? String == "get_recent_generated_audio_chunks" } == false)
            #expect(tools.contains { $0["name"] as? String == "replay_recent_audio" } == false)
            #expect(tools.contains { $0["name"] as? String == "replay_recent_audio_all" } == false)
            #expect(tools.contains { $0["name"] as? String == "clear_recent_generated_audio" } == false)
            #expect(tools.contains { $0["name"] as? String == "select_network_audio_receiver" } == false)
            #expect(tools.contains { $0["name"] as? String == "clear_network_audio_receiver" } == false)
            #expect(tools.contains { $0["name"] as? String == "cancel_generation" } == false)
            #expect(tools.contains { $0["name"] as? String == "cancel_playback" } == false)
            #expect(tools.contains { $0["name"] as? String == "cancel_request" } == false)

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
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://voices/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://text-profiles/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://playback" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://playback/guide" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://voices" })
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://requests" } == false)
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://configuration" } == false)
            #expect(resources.contains { $0["uri"] as? String == "speak-swiftly://status" } == false)

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
            #expect(templateURIs == ["speak-swiftly://requests/{request_id}"])
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak-swiftly://voices/{profile_name}" } == false)
            #expect(templates.contains { $0["uriTemplate"] as? String == "speak-swiftly://text-profiles/stored/{profile_id}" } == false)
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
