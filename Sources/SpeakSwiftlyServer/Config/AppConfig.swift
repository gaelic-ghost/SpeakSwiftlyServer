import Foundation

// MARK: - App Config

struct AppConfig: Sendable {
    let server: ServerConfiguration
    let http: HTTPConfig
    let mcp: MCPConfig

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> AppConfig {
        let server = try ServerConfiguration.load(environment: environment)
        return .init(
            server: server,
            http: .init(
                enabled: true,
                host: server.host,
                port: server.port,
                sseHeartbeatSeconds: server.sseHeartbeatSeconds
            ),
            mcp: .init(
                enabled: false,
                path: "/mcp",
                serverName: "speak-to-user-mcp",
                title: "SpeakSwiftlyMCP"
            )
        )
    }
}
