import Configuration
import Foundation
import ServiceLifecycle

package struct ServerConfigStore {
    package enum Update {
        case reloaded(AppConfig)
        case rejected(String)
    }

    package let services: [any Service]

    let reader: ConfigReader

    private let environment: [String: String]
    private let defaultProfile: ServerConfigDefaultProfile
    private let monitoredConfigurationURL: URL?
    private let reloadMonitor: ServerConfigFileMonitor?

    // MARK: - Initialization

    package init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultProfile: ServerConfigDefaultProfile? = nil,
        configurationURL: URL? = nil,
    ) async throws {
        self.environment = environment

        var services = [any Service]()
        var providers: [any ConfigProvider] = [
            EnvironmentVariablesProvider(environmentVariables: environment),
        ]
        let resolvedDefaultProfile = ServerConfigDefaultProfile.resolve(
            explicitProfile: defaultProfile,
            environment: environment,
        )
        self.defaultProfile = resolvedDefaultProfile

        var monitoredConfigurationURL: URL?
        var reloadMonitor: ServerConfigFileMonitor?

        if let configurationURL {
            let persistence = ServerConfigPersistence(configurationURL: configurationURL)
            try persistence.seedIfMissing()
            let provider = try await Self.yamlProvider(fileURL: persistence.configurationURL)
            let monitor = try ServerConfigFileMonitor(
                fileURL: persistence.configurationURL,
                pollInterval: Self.reloadPollInterval(from: environment),
            )
            providers.append(provider)
            services.append(monitor)
            monitoredConfigurationURL = persistence.configurationURL
            reloadMonitor = monitor
        } else if let configFilePath = environment["APP_CONFIG_FILE"], !configFilePath.isEmpty {
            let configFileURL = URL(fileURLWithPath: configFilePath).standardizedFileURL
            let provider = try await Self.yamlProvider(fileURL: configFileURL)
            let monitor = try ServerConfigFileMonitor(
                fileURL: configFileURL,
                pollInterval: Self.reloadPollInterval(from: environment),
            )
            providers.append(provider)
            services.append(monitor)
            monitoredConfigurationURL = configFileURL
            reloadMonitor = monitor
        }

        providers.append(InMemoryProvider(values: resolvedDefaultProfile.configDefaults))
        reader = ConfigReader(providers: providers)
        self.services = services
        self.monitoredConfigurationURL = monitoredConfigurationURL
        self.reloadMonitor = reloadMonitor
    }

    // MARK: - Helpers

    private static func finishedUpdateStream() -> AsyncThrowingStream<Update, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    private static func reloadPollInterval(from environment: [String: String]) -> Duration {
        guard let rawValue = environment["APP_CONFIG_RELOAD_INTERVAL_SECONDS"], !rawValue.isEmpty else {
            return .seconds(2)
        }
        guard let seconds = Double(rawValue), seconds > 0 else {
            return .seconds(2)
        }

        return .milliseconds(Int((seconds * 1000).rounded()))
    }

    private static func yamlProvider(fileURL: URL) async throws -> FileProvider<YAMLSnapshot> {
        try await FileProvider<YAMLSnapshot>(filePath: .init(fileURL.path))
    }

    private static func loadAppConfig(
        environment: [String: String],
        defaultProfile: ServerConfigDefaultProfile,
        configurationURL: URL,
    ) async throws -> AppConfig {
        let providers: [any ConfigProvider] = try await [
            EnvironmentVariablesProvider(environmentVariables: environment),
            yamlProvider(fileURL: configurationURL),
            InMemoryProvider(values: defaultProfile.configDefaults),
        ]
        return try AppConfig(config: ConfigReader(providers: providers).scoped(to: "app"))
    }

    // MARK: - Loading

    package func loadAppConfig() throws -> AppConfig {
        try AppConfig(config: reader.scoped(to: "app"))
    }

    package func updates() -> AsyncThrowingStream<Update, Error> {
        guard let reloadMonitor, let monitoredConfigurationURL else {
            return Self.finishedUpdateStream()
        }

        let environment = environment
        let defaultProfile = defaultProfile
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await _ in reloadMonitor.updates() {
                        do {
                            let appConfig = try await Self.loadAppConfig(
                                environment: environment,
                                defaultProfile: defaultProfile,
                                configurationURL: monitoredConfigurationURL,
                            )
                            continuation.yield(.reloaded(appConfig))
                        } catch {
                            continuation.yield(.rejected(String(describing: error)))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

public enum ServerConfigDefaultProfile: String, CaseIterable, Sendable {
    case standaloneExecutable = "standalone-executable"
    case launchAgent = "launch-agent"
    case embeddedSession = "embedded-session"

    package static let environmentKey = "SPEAKSWIFTLY_SERVER_DEFAULT_PROFILE"

    var port: Int {
        switch self {
            case .standaloneExecutable:
                7338
            case .launchAgent:
                7337
            case .embeddedSession:
                7339
        }
    }

    var configDefaults: [AbsoluteConfigKey: ConfigValue] {
        [
            .init(["app", "name"]): "speak-swiftly-server",
            .init(["app", "environment"]): "development",
            .init(["app", "host"]): "127.0.0.1",
            .init(["app", "port"]): ConfigValue(integerLiteral: port),
            .init(["app", "sseHeartbeatSeconds"]): 10.0,
            .init(["app", "completedJobTTLSeconds"]): 900.0,
            .init(["app", "completedJobMaxCount"]): 200,
            .init(["app", "jobPruneIntervalSeconds"]): 60.0,
            .init(["app", "http", "enabled"]): true,
            .init(["app", "mcp", "enabled"]): false,
            .init(["app", "mcp", "path"]): "/mcp",
            .init(["app", "mcp", "serverName"]): "speak-swiftly-mcp",
            .init(["app", "mcp", "title"]): "Speak Swiftly",
            .init(["app", "networkAudioReceiver", "enabled"]): false,
            .init(["app", "networkAudioReceiver", "serviceName"]): "SpeakSwiftly Audio Receiver",
            .init(["app", "networkAudioReceiver", "port"]): 0,
            .init(["app", "networkAudioReceiver", "sharedToken"]): "",
            .init(["app", "remoteGeneration", "allowRemoteStreamRequests"]): false,
            .init(["app", "remoteGeneration", "sharedToken"]): "",
        ]
    }

    static func resolve(
        explicitProfile: ServerConfigDefaultProfile?,
        environment: [String: String],
    ) -> ServerConfigDefaultProfile {
        if let explicitProfile {
            return explicitProfile
        }

        guard let rawValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return .standaloneExecutable
        }

        return ServerConfigDefaultProfile(rawValue: rawValue) ?? .standaloneExecutable
    }
}
