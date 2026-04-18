import Configuration
import Foundation
import ServiceLifecycle
import SystemPackage

struct ConfigStore {
    enum Update {
        case reloaded(AppConfig)
        case rejected(String)
    }

    let reader: ConfigReader
    let services: [any Service]

    private let reloadingProvider: ReloadingFileProvider<YAMLSnapshot>?

    // MARK: - Initialization

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaultProfile: AppRuntimeDefaultProfile? = nil,
    ) async throws {
        var services = [any Service]()
        var providers: [any ConfigProvider] = [
            EnvironmentVariablesProvider(environmentVariables: environment),
        ]
        let resolvedDefaultProfile = AppRuntimeDefaultProfile.resolve(
            explicitProfile: defaultProfile,
            environment: environment,
        )

        var reloadingProvider: ReloadingFileProvider<YAMLSnapshot>?

        if let configFilePath = environment["APP_CONFIG_FILE"], !configFilePath.isEmpty {
            let provider = try await ReloadingFileProvider<YAMLSnapshot>(
                filePath: FilePath(configFilePath),
                allowMissing: false,
                pollInterval: Self.reloadPollInterval(from: environment),
            )
            providers.append(provider)
            services.append(provider)
            reloadingProvider = provider
        }

        providers.append(InMemoryProvider(values: resolvedDefaultProfile.configDefaults))
        reader = ConfigReader(providers: providers)
        self.services = services
        self.reloadingProvider = reloadingProvider
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

    // MARK: - Loading

    func loadAppConfig() throws -> AppConfig {
        try AppConfig(config: reader.scoped(to: "app"))
    }

    func updates() -> AsyncThrowingStream<Update, Error> {
        guard reloadingProvider != nil else {
            return Self.finishedUpdateStream()
        }

        let config = reader.scoped(to: "app")
        return AsyncThrowingStream { continuation in
            let task = Task {
                var didConsumeInitialSnapshot = false

                do {
                    try await config.watchSnapshot { snapshots in
                        for try await _ in snapshots {
                            if !didConsumeInitialSnapshot {
                                didConsumeInitialSnapshot = true
                                continue
                            }

                            do {
                                try continuation.yield(.reloaded(AppConfig(config: config)))
                            } catch {
                                continuation.yield(.rejected(String(describing: error)))
                            }
                        }

                        continuation.finish()
                    }
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
