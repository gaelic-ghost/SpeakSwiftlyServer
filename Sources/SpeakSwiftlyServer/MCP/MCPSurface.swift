import Foundation
import Hummingbird
import MCP

struct MCPSurface {
    private let sessions: MCPSessionRegistry

    // MARK: - Construction

    static func build(
        configuration: MCPConfig,
        host: ServerHost,
    ) async -> MCPSurface? {
        guard configuration.enabled else {
            return nil
        }

        return .init(
            sessions: .init(
                configuration: configuration,
                host: host,
            ),
        )
    }

    // MARK: - Server Assembly

    static func buildServer(
        configuration: MCPConfig,
        host: ServerHost,
        subscriptionBroker: MCPSubscriptionBroker,
    ) async -> Server {
        let server = Server(
            name: configuration.serverName,
            version: "0.1.0",
            title: configuration.title,
            instructions: """
            Shared-process SpeakSwiftly MCP surface backed by the same ServerHost used by the app-facing HTTP API. Read status, job, profile, text-profile, and runtime resources for operator-visible state, use the tools to queue speech, inspect queues, control playback, and manage both voice and text profiles, and use the built-in prompts for reusable voice-design, text-normalization authoring, and operator acknowledgement workflows without starting a second runtime owner.
            """,
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: true, listChanged: false),
                tools: .init(listChanged: false),
            ),
        )

        await registerToolHandlers(
            on: server,
            host: host,
            subscriptionBroker: subscriptionBroker,
        )
        await registerResourceHandlers(
            on: server,
            host: host,
            subscriptionBroker: subscriptionBroker,
        )
        await registerPromptHandlers(on: server)

        return server
    }

    func mount(on router: Router<BasicRequestContext>) {
        let mcpPath = RouterPath(sessions.path)

        router.get(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.post(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.delete(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }
    }

    func start() async throws {
        await sessions.start()
    }

    func stop() async {
        await sessions.stop()
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        await sessions.handle(request)
    }
}
