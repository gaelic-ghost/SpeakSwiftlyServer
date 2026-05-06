import Configuration
import Foundation

struct AppConfig {
    let server: ServerConfiguration
    let runtime: RuntimeStartupConfiguration
    let http: HTTPConfig
    let mcp: MCPConfig

    // MARK: - Initialization

    init(
        server: ServerConfiguration,
        runtime: RuntimeStartupConfiguration = .init(),
        http: HTTPConfig,
        mcp: MCPConfig,
    ) {
        self.server = server
        self.runtime = runtime
        self.http = http
        self.mcp = mcp
    }

    init(config: ConfigReader) throws {
        let server = try ServerConfiguration(config: config)
        self.server = server
        runtime = try RuntimeStartupConfiguration(
            config: config.scoped(to: "runtime"),
            fallbackDefaultVoiceProfileName: server.defaultVoiceProfileName,
        )
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
        defaultProfile: ServerConfigDefaultProfile? = nil,
        configurationURL: URL? = nil,
    ) async throws -> AppConfig {
        let store = try await ServerConfigStore(
            environment: environment,
            defaultProfile: defaultProfile,
            configurationURL: configurationURL,
        )
        return try store.loadAppConfig()
    }
}
