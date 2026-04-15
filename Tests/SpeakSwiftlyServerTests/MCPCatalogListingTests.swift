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
            #expect(tools.contains { $0["name"] as? String == "get_staged_runtime_config" })
            #expect(tools.contains { $0["name"] as? String == "set_staged_config" })
            #expect(tools.contains { $0["name"] as? String == "get_runtime_overview" })

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
