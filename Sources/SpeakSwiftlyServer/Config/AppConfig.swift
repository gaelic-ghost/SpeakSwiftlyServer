import Configuration
import Foundation

// MARK: - App Config

struct AppConfig: Sendable {
    let server: ServerConfiguration
    let http: HTTPConfig
    let mcp: MCPConfig

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> AppConfig {
        let store = try await ConfigStore(environment: environment)
        let config = store.reader.scoped(to: "app")
        let server = try ServerConfiguration(config: config)
        return .init(
            server: server,
            http: try HTTPConfig(config: config.scoped(to: "http")),
            mcp: try MCPConfig(config: config.scoped(to: "mcp"))
        )
    }
}
