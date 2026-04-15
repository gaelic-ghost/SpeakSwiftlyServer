import Foundation
import MCP
@testable import SpeakSwiftlyServer
import Testing

// MARK: - MCP Session Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP supports multiple independent sessions`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration()
        let state = await MainActor.run { ServerState() }
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
            runtimeConfigurationStore: testRuntimeConfigurationStore(),
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

        let firstInitializeResponse = await mcpSurface.handle(
            mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-first")),
        )
        let firstSessionID = try #require(mcpSessionID(from: firstInitializeResponse))
        try await drainMCPResponse(firstInitializeResponse)

        let secondInitializeResponse = await mcpSurface.handle(
            mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-second")),
        )
        let secondSessionID = try #require(mcpSessionID(from: secondInitializeResponse))
        try await drainMCPResponse(secondInitializeResponse)

        #expect(firstSessionID != secondSessionID)

        let firstInitializedNotification = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: firstSessionID,
            ),
        )
        #expect(mcpStatusCode(from: firstInitializedNotification) == 202)

        let secondInitializedNotification = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: secondSessionID,
            ),
        )
        #expect(mcpStatusCode(from: secondInitializedNotification) == 202)

        let firstStatusEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpRuntimeOverviewToolRequestJSON(),
                    sessionID: firstSessionID,
                ),
            ),
        )
        let firstStatusPayload = try mcpToolPayload(from: firstStatusEnvelope)
        #expect(firstStatusPayload["worker_mode"] as? String == "ready")

        let secondToolsEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpListToolsRequestJSON(),
                    sessionID: secondSessionID,
                ),
            ),
        )
        let secondToolsResult = try #require(mcpResultPayload(from: secondToolsEnvelope))
        let secondTools = try #require(secondToolsResult["tools"] as? [[String: Any]])
        #expect(secondTools.contains { $0["name"] as? String == "get_runtime_overview" })

        let deleteFirstSessionResponse = await mcpSurface.handle(
            mcpDELETERequest(sessionID: firstSessionID),
        )
        #expect(mcpStatusCode(from: deleteFirstSessionResponse) == 200)

        let deletedSessionResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpRuntimeOverviewToolRequestJSON(),
                sessionID: firstSessionID,
            ),
        )
        #expect(mcpStatusCode(from: deletedSessionResponse) == 404)

        let survivingSessionEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpRuntimeOverviewToolRequestJSON(),
                    sessionID: secondSessionID,
                ),
            ),
        )
        let survivingSessionPayload = try mcpToolPayload(from: survivingSessionEnvelope)
        #expect(survivingSessionPayload["worker_mode"] as? String == "ready")

        await mcpSurface.stop()
        await host.shutdown()
    }
}
