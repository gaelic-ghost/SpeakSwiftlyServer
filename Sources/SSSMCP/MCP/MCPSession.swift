import MCP
import SSSCore

package actor MCPSession {
    private let host: ServerHost
    private let transport: StatefulHTTPServerTransport
    private let server: Server
    private let subscriptionBroker: MCPSubscriptionBroker
    private let clientIdentity: MCPClientIdentity

    init(
        host: ServerHost,
        transport: StatefulHTTPServerTransport,
        server: Server,
        subscriptionBroker: MCPSubscriptionBroker,
        clientIdentity: MCPClientIdentity,
    ) {
        self.host = host
        self.transport = transport
        self.server = server
        self.subscriptionBroker = subscriptionBroker
        self.clientIdentity = clientIdentity
    }

    static func make(
        configuration: MCPConfig,
        host: ServerHost,
    ) async -> MCPSession {
        let transport = StatefulHTTPServerTransport()
        let subscriptionBroker = MCPSubscriptionBroker()
        let clientIdentity = MCPClientIdentity()
        let server = await MCPSurface.buildServer(
            configuration: configuration,
            host: host,
            subscriptionBroker: subscriptionBroker,
            clientIdentity: clientIdentity,
        )
        return .init(
            host: host,
            transport: transport,
            server: server,
            subscriptionBroker: subscriptionBroker,
            clientIdentity: clientIdentity,
        )
    }

    func start() async throws {
        try await server.start(transport: transport) { [clientIdentity] clientInfo, _ in
            await clientIdentity.record(clientInfo)
        }
        await subscriptionBroker.start(host: host, server: server)
    }

    func stop() async {
        await subscriptionBroker.stop()
        await server.stop()
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        await transport.handleRequest(request)
    }
}
