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
            http: try HTTPConfig.load(environment: environment, defaults: server),
            mcp: MCPConfig.load(environment: environment)
        )
    }
}
