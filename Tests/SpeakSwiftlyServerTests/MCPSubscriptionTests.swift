import Foundation
import MCP
@testable import SpeakSwiftlyServer
import Testing

// MARK: - MCP Subscription Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP resource subscriptions emit updated notifications`() async throws {
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
        await host.markTransportStarting(name: "http")
        await host.markTransportStarting(name: "mcp")

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
        await host.markTransportListening(name: "mcp")

        let initializeResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let sessionID = try #require(mcpSessionID(from: initializeResponse))
        try await drainMCPResponse(initializeResponse)

        let initializedNotificationResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: sessionID,
            ),
        )
        #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

        let streamResponse = await mcpSurface.handle(mcpGETRequest(sessionID: sessionID))
        guard case let .stream(stream, _) = streamResponse else {
            Issue.record("Expected the embedded MCP GET transport to return a standalone streaming response.")
            await mcpSurface.stop()
            await host.shutdown()
            return
        }

        var streamIterator = stream.makeAsyncIterator()
        _ = try await nextMCPStreamEnvelope(from: &streamIterator)

        let subscribeEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpSubscribeResourceRequestJSON(uri: "speak://runtime/overview"),
                    sessionID: sessionID,
                ),
            ),
        )
        #expect(subscribeEnvelope["result"] != nil)

        await host.markTransportFailed(
            name: "http",
            message: "SpeakSwiftlyServer test transport failure for MCP resource subscription coverage.",
        )

        let updatedNotification = try await nextMCPStreamEnvelope(from: &streamIterator)
        #expect(updatedNotification["method"] as? String == "notifications/resources/updated")
        let notificationParams = try #require(updatedNotification["params"] as? [String: Any])
        #expect(notificationParams["uri"] as? String == "speak://runtime/overview")

        await mcpSurface.stop()
        await host.shutdown()
    }
}
