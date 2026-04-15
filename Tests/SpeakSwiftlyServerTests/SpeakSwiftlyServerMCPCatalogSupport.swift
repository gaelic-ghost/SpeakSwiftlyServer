import Foundation
import MCP
import Testing
@testable import SpeakSwiftlyServer

// MARK: - MCP Catalog Support

extension ServerTests {
    @available(macOS 14, *)
    static func withEmbeddedMCPSurface(
        _ body: @Sendable (
            MockRuntime,
            ServerHost,
            MCPSurface,
            String
        ) async throws -> Void
    ) async throws {
        let runtime = MockRuntime(speakBehavior: .holdOpen)
        let configuration = testConfiguration()
        let state = await MainActor.run { ServerState() }
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
                title: "SpeakSwiftly Test MCP"
            ),
            runtime: runtime,
            runtimeConfigurationStore: .init(
                environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
                activeRuntimeSpeechBackend: .qwen3
            ),
            state: state
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
                    title: "SpeakSwiftly Test MCP"
                ),
                host: host
            )
        )

        try await mcpSurface.start()
        await host.markTransportListening(name: "mcp")
        let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
        try await drainMCPResponse(initializeMCPResponse)

        let initializedNotificationResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: initializeSessionID
            )
        )
        #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

        try await body(runtime, host, mcpSurface, initializeSessionID)
    }
}
