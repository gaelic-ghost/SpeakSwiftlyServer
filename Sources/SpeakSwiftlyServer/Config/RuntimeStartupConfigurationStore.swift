import Foundation
import SpeakSwiftly

struct RuntimeStartupConfigurationStore {
    private final class FileSystem: @unchecked Sendable {
        private let fileManager: FileManager

        init(fileManager: FileManager) {
            self.fileManager = fileManager
        }

        func fileExists(atPath path: String) -> Bool {
            fileManager.fileExists(atPath: path)
        }

        func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: withIntermediateDirectories,
            )
        }
    }

    private let environment: [String: String]
    private let fileSystem: FileSystem
    private let persistence: ServerConfigPersistence
    private let configurationURL: URL
    private let profileRootURL: URL
    private let defaultActiveRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend?
    private let defaultActiveMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        configurationURL: URL? = nil,
        profileRootURL: URL? = nil,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
    ) {
        let profileRootOverride = environment["SPEAKSWIFTLY_PROFILE_ROOT"]
        self.environment = environment
        fileSystem = FileSystem(fileManager: fileManager)
        let resolvedProfileRootURL: URL
        let resolvedConfigurationURL: URL
        if let profileRootURL {
            resolvedProfileRootURL = profileRootURL.standardizedFileURL
            resolvedConfigurationURL = (configurationURL ?? ServerStorageDefaults.defaultForCurrentUser(fileManager: fileManager).configurationURL)
                .standardizedFileURL
        } else if let profileRootOverride,
                  profileRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let overriddenProfileRootURL = URL(fileURLWithPath: profileRootOverride, isDirectory: true)
            resolvedConfigurationURL = (configurationURL ?? overriddenProfileRootURL
                .deletingLastPathComponent()
                .appendingPathComponent("server.yaml", isDirectory: false))
                .standardizedFileURL
            resolvedProfileRootURL = overriddenProfileRootURL.standardizedFileURL
        } else {
            let defaults = ServerStorageDefaults.defaultForCurrentUser(fileManager: fileManager)
            resolvedProfileRootURL = defaults.profileRootURL.standardizedFileURL
            resolvedConfigurationURL = (configurationURL ?? defaults.configurationURL).standardizedFileURL
        }
        self.profileRootURL = resolvedProfileRootURL
        self.configurationURL = resolvedConfigurationURL
        persistence = ServerConfigPersistence(
            configurationURL: self.configurationURL,
            profileRootURL: self.profileRootURL,
            fileManager: fileManager,
        )
        defaultActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend
        defaultActiveMarvisResidentPolicy = activeMarvisResidentPolicy
    }

    func startupConfiguration(configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil) -> SpeakSwiftly.Configuration {
        let configuration = resolvedPersistedConfiguration()
        return RuntimeStartupConfiguration(
            speechBackend: configuration.speechBackend,
            marvisResidentPolicy: configuration.marvisResidentPolicy,
            defaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        .speakSwiftlyConfiguration(configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName)
    }

    func runtimeStateRootURL() -> URL {
        guard profileRootURL.lastPathComponent == "profiles" else {
            return profileRootURL
        }

        return profileRootURL.deletingLastPathComponent()
    }

    func profileStoreRootURL() -> URL {
        guard profileRootURL.lastPathComponent != "profiles" else {
            return profileRootURL
        }

        return profileRootURL.appendingPathComponent("profiles", isDirectory: true)
    }

    func initialActiveRuntimeSpeechBackend() -> SpeakSwiftly.SpeechBackend {
        defaultActiveRuntimeSpeechBackend ?? resolvedPersistedConfiguration().speechBackend
    }

    func initialActiveMarvisResidentPolicy() -> SpeakSwiftly.MarvisResidentPolicy {
        defaultActiveMarvisResidentPolicy ?? resolvedPersistedConfiguration().marvisResidentPolicy
    }

    func initialActiveDefaultVoiceProfileName(
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name?,
    ) -> SpeakSwiftly.Name? {
        resolvedPersistedConfiguration().defaultVoiceProfileName ?? configuredDefaultVoiceProfileName
    }

    func snapshot(
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) -> RuntimeConfigurationSnapshot {
        let resolution = resolvedPersistedConfiguration()
        let resolvedActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend ?? initialActiveRuntimeSpeechBackend()
        let resolvedActiveMarvisResidentPolicy = activeMarvisResidentPolicy ?? initialActiveMarvisResidentPolicy()
        let resolvedActiveDefaultVoiceProfileName = activeDefaultVoiceProfileName
            ?? initialActiveDefaultVoiceProfileName(configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName)
        let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment)
            ?? SpeakSwiftly.SpeechBackend.configuredFromLegacyQwenResidentModelEnvironment(in: environment)

        return .init(
            activeRuntimeSpeechBackend: resolvedActiveRuntimeSpeechBackend.rawValue,
            nextRuntimeSpeechBackend: resolution.speechBackend.rawValue,
            activeQwenResidentModel: RuntimeStartupConfiguration.legacyQwenResidentModelRawValue(for: resolvedActiveRuntimeSpeechBackend),
            nextQwenResidentModel: RuntimeStartupConfiguration.legacyQwenResidentModelRawValue(for: resolution.speechBackend),
            activeMarvisResidentPolicy: resolvedActiveMarvisResidentPolicy.rawValue,
            nextMarvisResidentPolicy: resolution.marvisResidentPolicy.rawValue,
            activeDefaultVoiceProfileName: resolvedActiveDefaultVoiceProfileName,
            nextDefaultVoiceProfileName: resolution.defaultVoiceProfileName,
            environmentSpeechBackendOverride: environmentOverride?.rawValue,
            environmentQwenResidentModelOverride: nil,
            persistedSpeechBackend: resolution.persistedSpeechBackend?.rawValue,
            persistedQwenResidentModel: resolution.persistedSpeechBackend.map(RuntimeStartupConfiguration.legacyQwenResidentModelRawValue(for:)),
            persistedMarvisResidentPolicy: resolution.persistedMarvisResidentPolicy?.rawValue,
            persistedDefaultVoiceProfileName: resolution.persistedDefaultVoiceProfileName,
            profileRootPath: profileRootURL.path,
            persistedConfigurationPath: configurationURL.path,
            persistedConfigurationExists: resolution.configurationExists,
            persistedConfigurationState: resolution.configurationState.rawValue,
            persistedConfigurationError: resolution.configurationError,
            persistedConfigurationAppliesOnRestart: true,
            activeRuntimeMatchesNextRuntime: resolvedActiveRuntimeSpeechBackend == resolution.speechBackend
                && resolvedActiveMarvisResidentPolicy == resolution.marvisResidentPolicy,
            persistedConfigurationWillAffectNextRuntimeStart: environmentOverride == nil,
        )
    }

    func save(
        speechBackend: SpeakSwiftly.SpeechBackend,
        qwenSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        let persistedSpeechBackend = speechBackend == .qwen3_smol
            ? qwenSpeechBackend ?? speechBackend
            : speechBackend
        do {
            try savePersistedConfiguration(
                RuntimeStartupConfiguration(
                    speechBackend: persistedSpeechBackend,
                    marvisResidentPolicy: marvisResidentPolicy
                        ?? current?.marvisResidentPolicy
                        ?? resolvedPersistedConfiguration().marvisResidentPolicy,
                    defaultVoiceProfileName: current?.defaultVoiceProfileName,
                ),
            )
        } catch {
            throw RuntimeStartupConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted runtime configuration to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName,
        )
    }

    func saveDefaultVoiceProfileName(
        _ defaultVoiceProfileName: SpeakSwiftly.Name?,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        do {
            try savePersistedConfiguration(
                RuntimeStartupConfiguration(
                    speechBackend: current?.speechBackend ?? resolvedPersistedConfiguration().speechBackend,
                    marvisResidentPolicy: current?.marvisResidentPolicy
                        ?? resolvedPersistedConfiguration().marvisResidentPolicy,
                    defaultVoiceProfileName: defaultVoiceProfileName,
                ),
            )
        } catch {
            throw RuntimeStartupConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted default voice profile to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
            activeDefaultVoiceProfileName: RuntimeStartupConfiguration.normalized(defaultVoiceProfileName)
                ?? configuredDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName,
        )
    }

    private func resolvedPersistedConfiguration() -> Resolution {
        Self.resolvePersistedConfiguration(
            environment: environment,
            configurationURL: configurationURL,
            fileSystem: fileSystem,
            persistence: persistence,
        )
    }

    private func loadPersistedRuntimeConfiguration() -> RuntimeStartupConfiguration? {
        let configurationExists = fileSystem.fileExists(atPath: configurationURL.path)
        return Self.loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists,
            persistence: persistence,
        )
        .persistedConfiguration
    }

    private func savePersistedConfiguration(_ configuration: RuntimeStartupConfiguration) throws {
        try fileSystem.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try persistence.saveRuntimeConfiguration(configuration)
    }
}

private extension RuntimeStartupConfigurationStore {
    enum ConfigurationState: String {
        case missing
        case loaded
        case invalid
    }

    struct Resolution {
        let speechBackend: SpeakSwiftly.SpeechBackend
        let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
        let defaultVoiceProfileName: SpeakSwiftly.Name?
        let persistedSpeechBackend: SpeakSwiftly.SpeechBackend?
        let persistedMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy?
        let persistedDefaultVoiceProfileName: SpeakSwiftly.Name?
        let configurationExists: Bool
        let configurationState: ConfigurationState
        let configurationError: String?
    }

    private static func resolvePersistedConfiguration(
        environment: [String: String],
        configurationURL: URL,
        fileSystem: FileSystem,
        persistence: ServerConfigPersistence,
    ) -> Resolution {
        let configurationExists = fileSystem.fileExists(atPath: configurationURL.path)
        let persistedState = loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists,
            persistence: persistence,
        )

        let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment)
            ?? SpeakSwiftly.SpeechBackend.configuredFromLegacyQwenResidentModelEnvironment(in: environment)

        return .init(
            speechBackend: environmentOverride
                ?? persistedState.persistedSpeechBackend
                ?? .qwen3_smol,
            marvisResidentPolicy: persistedState.persistedMarvisResidentPolicy ?? .dualResidentSerialized,
            defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
            persistedSpeechBackend: persistedState.persistedSpeechBackend,
            persistedMarvisResidentPolicy: persistedState.persistedMarvisResidentPolicy,
            persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
            configurationExists: configurationExists,
            configurationState: persistedState.configurationState,
            configurationError: persistedState.configurationError,
        )
    }

    private static func loadPersistedConfiguration(
        from configurationURL: URL,
        configurationExists: Bool,
        persistence: ServerConfigPersistence,
    ) -> (
        persistedConfiguration: RuntimeStartupConfiguration?,
        persistedSpeechBackend: SpeakSwiftly.SpeechBackend?,
        persistedMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy?,
        persistedDefaultVoiceProfileName: SpeakSwiftly.Name?,
        configurationState: ConfigurationState,
        configurationError: String?,
    ) {
        guard configurationExists else {
            return (nil, nil, nil, nil, .missing, nil)
        }

        do {
            let configuration = try persistence.loadAppConfig().runtime
            return (
                configuration,
                configuration.speechBackend,
                configuration.marvisResidentPolicy,
                configuration.defaultVoiceProfileName,
                .loaded,
                nil,
            )
        } catch {
            return (
                nil,
                nil,
                nil,
                nil,
                .invalid,
                "SpeakSwiftlyServer could not decode the persisted runtime configuration at '\(configurationURL.path)'. Likely cause: \(error)",
            )
        }
    }
}

struct RuntimeStartupConfigurationStoreError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
