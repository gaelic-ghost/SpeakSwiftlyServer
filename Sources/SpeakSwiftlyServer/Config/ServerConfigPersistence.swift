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
        let defaults = RuntimeStorageDefaults.defaultForCurrentUser(fileManager: fileManager)
        self.configurationURL = (configurationURL ?? defaults.configurationURL).standardizedFileURL
        self.profileRootURL = (profileRootURL ?? defaults.profileRootURL).standardizedFileURL
        self.fileManager = fileManager
    }

    public static func defaultForCurrentUser(fileManager: FileManager = .default) -> ServerConfigPersistence {
        ServerConfigPersistence(fileManager: fileManager)
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
            let reader = ConfigReader(provider: SnapshotConfigProvider(currentSnapshot: snapshot))
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
            qwenResidentModel: \(runtime.qwenResidentModel.rawValue)
            marvisResidentPolicy: \(runtime.marvisResidentPolicy.rawValue)
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

        """
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
