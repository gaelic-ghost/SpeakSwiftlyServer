import Configuration
import Foundation
import SystemPackage

// MARK: - Config Store

struct ConfigStore: Sendable {
    let reader: ConfigReader

    init(environment: [String: String] = ProcessInfo.processInfo.environment) async throws {
        var providers: [any ConfigProvider] = [
            EnvironmentVariablesProvider(environmentVariables: environment),
        ]

        if let configFilePath = environment["APP_CONFIG_FILE"], !configFilePath.isEmpty {
            providers.append(try await FileProvider<YAMLSnapshot>(filePath: FilePath(configFilePath)))
        }

        providers.append(InMemoryProvider(values: Self.defaults))
        self.reader = ConfigReader(providers: providers)
    }

    private static let defaults: [AbsoluteConfigKey: ConfigValue] = [
        .init(["app", "name"]): "speak-swiftly-server",
        .init(["app", "environment"]): "development",
        .init(["app", "host"]): "127.0.0.1",
        .init(["app", "port"]): 7337,
        .init(["app", "sseHeartbeatSeconds"]): 10.0,
        .init(["app", "completedJobTTLSeconds"]): 900.0,
        .init(["app", "completedJobMaxCount"]): 200,
        .init(["app", "jobPruneIntervalSeconds"]): 60.0,
        .init(["app", "http", "enabled"]): true,
        .init(["app", "http", "host"]): "127.0.0.1",
        .init(["app", "http", "port"]): 7337,
        .init(["app", "http", "sseHeartbeatSeconds"]): 10.0,
        .init(["app", "mcp", "enabled"]): false,
        .init(["app", "mcp", "path"]): "/mcp",
        .init(["app", "mcp", "serverName"]): "speak-to-user-mcp",
        .init(["app", "mcp", "title"]): "SpeakSwiftlyMCP",
    ]
}
