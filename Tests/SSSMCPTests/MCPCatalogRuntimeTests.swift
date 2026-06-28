import Foundation
import MCP
import SpeakSwiftly
import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
import SSSHTTP
import SSSMCP
import Testing

// MARK: - MCP Catalog Runtime Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP routes drive live speech tool and overview resource`() async throws {
        try await Self.withEmbeddedMCPSurface { runtime, _, mcpSurface, sessionID in
            let queueSpeechToolEnvelope = try await mcpEnvelope(
                from: mcpSurface.handle(
                    mcpPOSTRequest(
                        body: mcpCallToolRequestJSON(
                            name: "generate_speech",
                            argumentsJSON: #"{"text":"Inspect MCP resources","profile_name":"default","text_profile_id":"mcp-text","request_context":{"source":"mcp","topic":"catalog-runtime","prefacePolicy":"never","attributes":{"caller.app":"SpeakSwiftlyServerLibraryTests","caller.project":"SpeakSwiftlyServer","surface":"mcp"}},"cwd":"./Tests","repo_root":".","qwen_pre_model_text_chunking":true}"#,
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
            #expect(queuedSpeechInvocation.qwenPreModelTextChunking == true)
            #expect(
                queuedSpeechInvocation.requestContext
                    == SpeakSwiftly.RequestContext(
                        reqPurpose: .speech,
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
                        prefacePolicy: .never,
                    ),
            )

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
            #expect(statusRuntimeConfiguration["active_qwen_resident_model"] == nil)
            #expect(statusRuntimeConfiguration["next_qwen_resident_model"] == nil)
            let transports = try #require(statusResourcePayload["transports"] as? [[String: Any]])
            #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })
        }
    }
}
