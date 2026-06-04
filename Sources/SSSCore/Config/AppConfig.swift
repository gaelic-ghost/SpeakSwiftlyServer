import Configuration
import Foundation

package struct AppConfig {
    package let server: ServerConfiguration
    package let runtime: RuntimeStartupConfiguration
    package let http: HTTPConfig
    package let listeners: HTTPListenersConfig
    package let mcp: MCPConfig
    package let networkAudioReceiver: NetworkAudioReceiverConfig
    package let remoteGeneration: RemoteGenerationConfig

    // MARK: - Initialization

    init(
        server: ServerConfiguration,
        runtime: RuntimeStartupConfiguration = .init(),
        http: HTTPConfig,
        listeners: HTTPListenersConfig? = nil,
        mcp: MCPConfig,
        networkAudioReceiver: NetworkAudioReceiverConfig,
        remoteGeneration: RemoteGenerationConfig = .init(
            allowRemoteStreamRequests: false,
            sharedToken: nil,
        ),
    ) {
        self.server = server
        self.runtime = runtime
        self.http = http
        self.listeners = listeners ?? .init(
            localhost: http,
            lan: .init(
                enabled: false,
                host: "0.0.0.0",
                port: 0,
                sseHeartbeatSeconds: http.sseHeartbeatSeconds,
                advertiseBonjour: true,
                serviceName: "\(server.name) LAN",
            ),
        )
        self.mcp = mcp
        self.networkAudioReceiver = networkAudioReceiver
        self.remoteGeneration = remoteGeneration
    }

    init(config: ConfigReader) throws {
        let server = try ServerConfiguration(config: config)
        self.server = server
        runtime = try RuntimeStartupConfiguration(
            config: config.scoped(to: "runtime"),
            fallbackDefaultVoiceProfileName: server.defaultVoiceProfileName,
        )
        let legacyHTTP = try HTTPConfig(
            config: config.scoped(to: "http"),
            fallbackHost: server.host,
            fallbackPort: server.port,
            fallbackSSEHeartbeatSeconds: server.sseHeartbeatSeconds,
        )
        listeners = try HTTPListenersConfig(
            config: config.scoped(to: "listeners"),
            legacyHTTPConfig: legacyHTTP,
            fallbackServiceName: server.name,
        )
        http = listeners.localhost
        mcp = try MCPConfig(config: config.scoped(to: "mcp"))
        networkAudioReceiver = try NetworkAudioReceiverConfig(
            config: config.scoped(to: "networkAudioReceiver"),
            fallbackServiceName: server.name,
        )
        remoteGeneration = try RemoteGenerationConfig(config: config.scoped(to: "remoteGeneration"))
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
