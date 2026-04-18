import Configuration
import Foundation

struct AppConfig {
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
        let server = try ServerConfiguration(config: config)
        self.server = server
        http = try HTTPConfig(
            config: config.scoped(to: "http"),
            fallbackHost: server.host,
            fallbackPort: server.port,
            fallbackSSEHeartbeatSeconds: server.sseHeartbeatSeconds,
        )
        mcp = try MCPConfig(config: config.scoped(to: "mcp"))
    }

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultProfile: AppRuntimeDefaultProfile? = nil,
    ) async throws -> AppConfig {
        let store = try await ConfigStore(environment: environment, defaultProfile: defaultProfile)
        return try store.loadAppConfig()
    }
}
