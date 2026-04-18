import MCP

actor MCPSession {
    private let host: ServerHost
    private let transport: StatefulHTTPServerTransport
    private let server: Server
    private let subscriptionBroker: MCPSubscriptionBroker

    init(
        host: ServerHost,
        transport: StatefulHTTPServerTransport,
        server: Server,
        subscriptionBroker: MCPSubscriptionBroker,
    ) {
        self.host = host
        self.transport = transport
        self.server = server
        self.subscriptionBroker = subscriptionBroker
    }

    static func make(
        configuration: MCPConfig,
        host: ServerHost,
    ) async -> MCPSession {
        let transport = StatefulHTTPServerTransport()
        let subscriptionBroker = MCPSubscriptionBroker()
        let server = await MCPSurface.buildServer(
            configuration: configuration,
            host: host,
            subscriptionBroker: subscriptionBroker,
        )
        return .init(
            host: host,
            transport: transport,
            server: server,
            subscriptionBroker: subscriptionBroker,
        )
    }

    func start() async throws {
        try await server.start(transport: transport)
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
