import Configuration
import Foundation
import SpeakSwiftly

public struct ServerConfigPersistence: @unchecked Sendable {
    public let configurationURL: URL
    public let profileRootURL: URL

    private let fileManager: FileManager

    public init(
        configurationURL: URL? = nil,
        profileRootURL: URL? = nil,
        fileManager: FileManager = .default,
    ) {
        let defaults = ServerStorageDefaults.defaultForCurrentUser(fileManager: fileManager)
        self.configurationURL = (configurationURL ?? defaults.configurationURL).standardizedFileURL
        self.profileRootURL = (profileRootURL ?? defaults.profileRootURL).standardizedFileURL
        self.fileManager = fileManager
    }

    public static func defaultForCurrentUser(fileManager: FileManager = .default) -> ServerConfigPersistence {
        ServerConfigPersistence(fileManager: fileManager)
    }

    static func renderYAML(appConfig: AppConfig, runtime: RuntimeStartupConfiguration? = nil) -> String {
        let runtime = runtime ?? appConfig.runtime
        let defaultVoiceProfileName = runtime.defaultVoiceProfileName.map { "'\($0)'" } ?? ""
        return """
        app:
          name: \(appConfig.server.name)
          environment: \(appConfig.server.environment)
          host: \(appConfig.server.host)
          port: \(appConfig.server.port)
          sseHeartbeatSeconds: \(appConfig.server.sseHeartbeatSeconds.cleanYAMLNumber)
          completedJobTTLSeconds: \(appConfig.server.completedJobTTLSeconds.cleanYAMLNumber)
          completedJobMaxCount: \(appConfig.server.completedJobMaxCount)
          jobPruneIntervalSeconds: \(appConfig.server.jobPruneIntervalSeconds.cleanYAMLNumber)
          runtime:
            speechBackend: \(runtime.speechBackend.rawValue)
            duckMediaVolume: \(runtime.duckMediaVolume.rawValue)
            defaultVoiceProfileName: \(defaultVoiceProfileName)
          http:
            enabled: \(appConfig.http.enabled ? "true" : "false")
            host: \(appConfig.http.host)
            port: \(appConfig.http.port)
            sseHeartbeatSeconds: \(appConfig.http.sseHeartbeatSeconds.cleanYAMLNumber)
          mcp:
            enabled: \(appConfig.mcp.enabled ? "true" : "false")
            path: \(appConfig.mcp.path)
            serverName: \(appConfig.mcp.serverName)
            title: \(appConfig.mcp.title)
          networkAudioReceiver:
            enabled: \(appConfig.networkAudioReceiver.enabled ? "true" : "false")
            serviceName: '\(appConfig.networkAudioReceiver.serviceName)'
            port: \(appConfig.networkAudioReceiver.port)
            sharedToken: ''

        """
    }

    @discardableResult
    public func seedIfMissing() throws -> Bool {
        guard fileManager.fileExists(atPath: configurationURL.path) == false else {
            return false
        }
        guard let defaultConfigURL = Bundle.module.url(
            forResource: "default-server",
            withExtension: "yaml",
        ) else {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not seed the default config because bundled resource 'default-server.yaml' is missing from the SpeakSwiftlyServer module.",
            )
        }

        do {
            try fileManager.createDirectory(
                at: configurationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try fileManager.copyItem(at: defaultConfigURL, to: configurationURL)
            return true
        } catch {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not seed the default config at '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
    }

    func loadAppConfig() throws -> AppConfig {
        let data: Data
        do {
            data = try Data(contentsOf: configurationURL)
        } catch {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not read persisted config at '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }

        do {
            let snapshot = try YAMLSnapshot(
                data: data.bytes,
                providerName: "ServerConfigPersistence",
                parsingOptions: .default,
            )
            let reader = ConfigReader(provider: StaticConfigSnapshotProvider(currentSnapshot: snapshot))
            return try AppConfig(config: reader.scoped(to: "app"))
        } catch let error as ServerConfigurationError {
            throw error
        } catch {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not decode persisted config at '\(configurationURL.path)'. Likely cause: \(error)",
            )
        }
    }

    func saveRuntimeConfiguration(_ runtime: RuntimeStartupConfiguration) throws {
        try seedIfMissing()
        let currentConfig = try loadAppConfig()
        let renderedConfig = Self.renderYAML(appConfig: currentConfig, runtime: runtime)
        do {
            try renderedConfig.write(to: configurationURL, atomically: true, encoding: .utf8)
        } catch {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not save persisted runtime configuration to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
    }
}

private extension Double {
    var cleanYAMLNumber: String {
        if rounded() == self {
            return String(Int(self))
        }
        return String(self)
    }
}

private struct StaticConfigSnapshotProvider: ConfigProvider {
    let providerName = "StaticConfigSnapshotProvider"
    let currentSnapshot: any ConfigSnapshot

    func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        try currentSnapshot.value(forKey: key, type: type)
    }

    func fetchValue(forKey key: AbsoluteConfigKey, type: ConfigType) async throws -> LookupResult {
        try value(forKey: key, type: type)
    }

    func snapshot() -> any ConfigSnapshot {
        currentSnapshot
    }

    nonisolated(nonsending) func watchValue<Return: ~Copyable>(
        forKey key: AbsoluteConfigKey,
        type: ConfigType,
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<Result<LookupResult, any Error>, Never>) async throws -> Return,
    ) async throws -> Return {
        let stream = AsyncStream<Result<LookupResult, any Error>> { continuation in
            continuation.yield(Result { try currentSnapshot.value(forKey: key, type: type) })
            continuation.finish()
        }
        return try await updatesHandler(.init(stream))
    }

    nonisolated(nonsending) func watchSnapshot<Return: ~Copyable>(
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<any ConfigSnapshot, Never>) async throws -> Return,
    ) async throws -> Return {
        let stream = AsyncStream<any ConfigSnapshot> { continuation in
            continuation.yield(currentSnapshot)
            continuation.finish()
        }
        return try await updatesHandler(.init(stream))
    }
}
