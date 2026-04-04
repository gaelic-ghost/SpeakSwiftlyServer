import Configuration
import Foundation

// MARK: - App Config

struct AppConfig: Sendable {
    let server: ServerConfiguration
    let http: HTTPConfig
    let mcp: MCPConfig

    // MARK: - Initialization

    init(server: ServerConfiguration, http: HTTPConfig, mcp: MCPConfig) {
        self.server = server
        self.http = http
        self.mcp = mcp
    }

    init(config: ConfigReader) throws {
        self.server = try ServerConfiguration(config: config)
        self.http = try HTTPConfig(config: config.scoped(to: "http"))
        self.mcp = try MCPConfig(config: config.scoped(to: "mcp"))
    }

    // MARK: - Loading

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) async throws -> AppConfig {
        let store = try await ConfigStore(environment: environment)
        return try store.loadAppConfig()
    }
}
