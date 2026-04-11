import Foundation
import SpeakSwiftlyCore

// MARK: - Runtime Configuration Store

struct RuntimeConfigurationStore: Sendable {
    private struct PersistedRuntimeConfiguration: Codable, Sendable {
        let speechBackend: SpeakSwiftly.SpeechBackend
        let defaultVoiceProfileName: SpeakSwiftly.Name?

        init(
            speechBackend: SpeakSwiftly.SpeechBackend,
            defaultVoiceProfileName: SpeakSwiftly.Name?
        ) {
            self.speechBackend = speechBackend
            self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
        }

        private static func normalized(_ profileName: SpeakSwiftly.Name?) -> SpeakSwiftly.Name? {
            guard let profileName else {
                return nil
            }
            let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private let environment: [String: String]
    private let configurationURL: URL
    private let profileRootURL: URL
    private let defaultActiveRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil
    ) {
        let profileRootOverride = environment["SPEAKSWIFTLY_PROFILE_ROOT"]
        self.environment = environment
        if let profileRootOverride,
           profileRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            self.profileRootURL = URL(fileURLWithPath: profileRootOverride, isDirectory: true)
            self.configurationURL = self.profileRootURL
                .deletingLastPathComponent()
                .appendingPathComponent("configuration.json", isDirectory: false)
        } else {
            let layout = ServerInstallLayout.defaultForCurrentUser(fileManager: fileManager)
            self.profileRootURL = layout.runtimeProfileRootURL
            self.configurationURL = layout.runtimeConfigurationFileURL
        }
        self.defaultActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend
    }

    func startupConfiguration() -> SpeakSwiftly.Configuration {
        .init(speechBackend: resolvedPersistedConfiguration().speechBackend)
    }

    func initialActiveRuntimeSpeechBackend() -> SpeakSwiftly.SpeechBackend {
        defaultActiveRuntimeSpeechBackend ?? resolvedPersistedConfiguration().speechBackend
    }

    func initialActiveDefaultVoiceProfileName(
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name?
    ) -> SpeakSwiftly.Name? {
        resolvedPersistedConfiguration().defaultVoiceProfileName ?? configuredDefaultVoiceProfileName
    }

    func snapshot(
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil
    ) -> RuntimeConfigurationSnapshot {
        let resolution = resolvedPersistedConfiguration()
        let resolvedActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend ?? initialActiveRuntimeSpeechBackend()
        let resolvedActiveDefaultVoiceProfileName = activeDefaultVoiceProfileName
            ?? initialActiveDefaultVoiceProfileName(configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName)
        let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment)

        return .init(
            activeRuntimeSpeechBackend: resolvedActiveRuntimeSpeechBackend.rawValue,
            nextRuntimeSpeechBackend: resolution.speechBackend.rawValue,
            activeDefaultVoiceProfileName: resolvedActiveDefaultVoiceProfileName,
            nextDefaultVoiceProfileName: resolution.defaultVoiceProfileName,
            environmentSpeechBackendOverride: environmentOverride?.rawValue,
            persistedSpeechBackend: resolution.persistedSpeechBackend?.rawValue,
            persistedDefaultVoiceProfileName: resolution.persistedDefaultVoiceProfileName,
            profileRootPath: profileRootURL.path,
            persistedConfigurationPath: configurationURL.path,
            persistedConfigurationExists: resolution.configurationExists,
            persistedConfigurationState: resolution.configurationState.rawValue,
            persistedConfigurationError: resolution.configurationError,
            persistedConfigurationAppliesOnRestart: true,
            activeRuntimeMatchesNextRuntime: resolvedActiveRuntimeSpeechBackend == resolution.speechBackend,
            persistedConfigurationWillAffectNextRuntimeStart: environmentOverride == nil
        )
    }

    func save(
        speechBackend: SpeakSwiftly.SpeechBackend,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        do {
            try savePersistedConfiguration(
                .init(
                    speechBackend: speechBackend,
                    defaultVoiceProfileName: current?.defaultVoiceProfileName
                )
            )
        } catch {
            throw RuntimeConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted runtime configuration to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)"
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName
        )
    }

    func saveDefaultVoiceProfileName(
        _ defaultVoiceProfileName: SpeakSwiftly.Name?,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        do {
            try savePersistedConfiguration(
                .init(
                    speechBackend: current?.speechBackend ?? resolvedPersistedConfiguration().speechBackend,
                    defaultVoiceProfileName: defaultVoiceProfileName
                )
            )
        } catch {
            throw RuntimeConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted default voice profile to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)"
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDefaultVoiceProfileName: defaultVoiceProfileName ?? configuredDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName
        )
    }

    private func resolvedPersistedConfiguration() -> Resolution {
        Self.resolvePersistedConfiguration(
            environment: environment,
            configurationURL: configurationURL
        )
    }

    private func loadPersistedRuntimeConfiguration() -> PersistedRuntimeConfiguration? {
        let configurationExists = FileManager.default.fileExists(atPath: configurationURL.path)
        return Self.loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists
        ).persistedConfiguration
    }

    private func savePersistedConfiguration(_ configuration: PersistedRuntimeConfiguration) throws {
        let directoryURL = configurationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
    }
}

private extension RuntimeConfigurationStore {
    enum ConfigurationState: String, Sendable {
        case missing
        case loaded
        case invalid
    }

    struct Resolution: Sendable {
        let speechBackend: SpeakSwiftly.SpeechBackend
        let defaultVoiceProfileName: SpeakSwiftly.Name?
        let persistedSpeechBackend: SpeakSwiftly.SpeechBackend?
        let persistedDefaultVoiceProfileName: SpeakSwiftly.Name?
        let configurationExists: Bool
        let configurationState: ConfigurationState
        let configurationError: String?
    }

    static func resolvePersistedConfiguration(
        environment: [String: String],
        configurationURL: URL
    ) -> Resolution {
        let fileManager = FileManager.default
        let configurationExists = fileManager.fileExists(atPath: configurationURL.path)
        let persistedState = loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists
        )

        if let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment) {
            return .init(
                speechBackend: environmentOverride,
                defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                persistedSpeechBackend: persistedState.persistedSpeechBackend,
                persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                configurationExists: configurationExists,
                configurationState: persistedState.configurationState,
                configurationError: persistedState.configurationError
            )
        }

        if let persistedSpeechBackend = persistedState.persistedSpeechBackend {
            return .init(
                speechBackend: persistedSpeechBackend,
                defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                persistedSpeechBackend: persistedSpeechBackend,
                persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                configurationExists: configurationExists,
                configurationState: .loaded,
                configurationError: nil
            )
        }

        return .init(
            speechBackend: .qwen3,
            defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
            persistedSpeechBackend: nil,
            persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
            configurationExists: configurationExists,
            configurationState: persistedState.configurationState,
            configurationError: persistedState.configurationError
        )
    }

    private static func loadPersistedConfiguration(
        from configurationURL: URL,
        configurationExists: Bool
    ) -> (
        persistedConfiguration: PersistedRuntimeConfiguration?,
        persistedSpeechBackend: SpeakSwiftly.SpeechBackend?,
        persistedDefaultVoiceProfileName: SpeakSwiftly.Name?,
        configurationState: ConfigurationState,
        configurationError: String?
    ) {
        guard configurationExists else {
            return (nil, nil, nil, .missing, nil)
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            let configuration = try JSONDecoder().decode(PersistedRuntimeConfiguration.self, from: data)
            return (
                configuration,
                configuration.speechBackend,
                configuration.defaultVoiceProfileName,
                .loaded,
                nil
            )
        } catch {
            return (
                nil,
                nil,
                nil,
                .invalid,
                "SpeakSwiftlyServer could not decode the persisted runtime configuration at '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)"
            )
        }
    }
}

struct RuntimeConfigurationStoreError: LocalizedError, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
