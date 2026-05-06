import Foundation
import SpeakSwiftly

struct RuntimeConfigurationStore {
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

    private struct PersistedRuntimeConfiguration: Codable {
        enum CodingKeys: String, CodingKey {
            case speechBackend
            case qwenResidentModel
            case marvisResidentPolicy
            case defaultVoiceProfileName
        }

        let speechBackend: SpeakSwiftly.SpeechBackend
        let qwenResidentModel: SpeakSwiftly.QwenResidentModel
        let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
        let defaultVoiceProfileName: SpeakSwiftly.Name?

        init(
            speechBackend: SpeakSwiftly.SpeechBackend,
            qwenResidentModel: SpeakSwiftly.QwenResidentModel,
            marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy,
            defaultVoiceProfileName: SpeakSwiftly.Name?,
        ) {
            self.speechBackend = speechBackend
            self.qwenResidentModel = qwenResidentModel
            self.marvisResidentPolicy = marvisResidentPolicy
            self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            speechBackend = try container.decode(SpeakSwiftly.SpeechBackend.self, forKey: .speechBackend)
            qwenResidentModel = try container.decodeIfPresent(
                SpeakSwiftly.QwenResidentModel.self,
                forKey: .qwenResidentModel,
            ) ?? .base06B8Bit
            marvisResidentPolicy = try container.decodeIfPresent(
                SpeakSwiftly.MarvisResidentPolicy.self,
                forKey: .marvisResidentPolicy,
            ) ?? .dualResidentSerialized
            defaultVoiceProfileName = try Self.normalized(
                container.decodeIfPresent(SpeakSwiftly.Name.self, forKey: .defaultVoiceProfileName),
            )
        }

        static func normalized(_ profileName: SpeakSwiftly.Name?) -> SpeakSwiftly.Name? {
            guard let profileName else {
                return nil
            }

            let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private let environment: [String: String]
    private let fileSystem: FileSystem
    private let configurationURL: URL
    private let profileRootURL: URL
    private let defaultActiveRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend?
    private let defaultActiveQwenResidentModel: SpeakSwiftly.QwenResidentModel?
    private let defaultActiveMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy?

    init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeQwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
    ) {
        let profileRootOverride = environment["SPEAKSWIFTLY_PROFILE_ROOT"]
        self.environment = environment
        fileSystem = FileSystem(fileManager: fileManager)
        if let profileRootOverride,
           profileRootOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            profileRootURL = URL(fileURLWithPath: profileRootOverride, isDirectory: true)
            configurationURL = profileRootURL
                .deletingLastPathComponent()
                .appendingPathComponent("configuration.json", isDirectory: false)
        } else {
            let layout = ServerInstallLayout.defaultForCurrentUser(fileManager: fileManager)
            profileRootURL = layout.runtimeProfileRootURL
            configurationURL = layout.runtimeConfigurationFileURL
        }
        defaultActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend
        defaultActiveQwenResidentModel = activeQwenResidentModel
        defaultActiveMarvisResidentPolicy = activeMarvisResidentPolicy
    }

    func startupConfiguration(configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil) -> SpeakSwiftly.Configuration {
        let configuration = resolvedPersistedConfiguration()
        return .init(
            speechBackend: configuration.speechBackend,
            qwenResidentModel: configuration.qwenResidentModel,
            marvisResidentPolicy: configuration.marvisResidentPolicy,
            defaultVoiceProfile: configuration.defaultVoiceProfileName
                ?? configuredDefaultVoiceProfileName
                ?? SpeakSwiftly.DefaultVoiceProfiles.signal,
        )
    }

    func initialActiveRuntimeSpeechBackend() -> SpeakSwiftly.SpeechBackend {
        defaultActiveRuntimeSpeechBackend ?? resolvedPersistedConfiguration().speechBackend
    }

    func initialActiveQwenResidentModel() -> SpeakSwiftly.QwenResidentModel {
        defaultActiveQwenResidentModel ?? resolvedPersistedConfiguration().qwenResidentModel
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
        activeQwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) -> RuntimeConfigurationSnapshot {
        let resolution = resolvedPersistedConfiguration()
        let resolvedActiveRuntimeSpeechBackend = activeRuntimeSpeechBackend ?? initialActiveRuntimeSpeechBackend()
        let resolvedActiveQwenResidentModel = activeQwenResidentModel ?? initialActiveQwenResidentModel()
        let resolvedActiveMarvisResidentPolicy = activeMarvisResidentPolicy ?? initialActiveMarvisResidentPolicy()
        let resolvedActiveDefaultVoiceProfileName = activeDefaultVoiceProfileName
            ?? initialActiveDefaultVoiceProfileName(configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName)
        let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment)
        let qwenResidentModelEnvironmentOverride = SpeakSwiftly.QwenResidentModel.configured(in: environment)

        return .init(
            activeRuntimeSpeechBackend: resolvedActiveRuntimeSpeechBackend.rawValue,
            nextRuntimeSpeechBackend: resolution.speechBackend.rawValue,
            activeQwenResidentModel: resolvedActiveQwenResidentModel.rawValue,
            nextQwenResidentModel: resolution.qwenResidentModel.rawValue,
            activeMarvisResidentPolicy: resolvedActiveMarvisResidentPolicy.rawValue,
            nextMarvisResidentPolicy: resolution.marvisResidentPolicy.rawValue,
            activeDefaultVoiceProfileName: resolvedActiveDefaultVoiceProfileName,
            nextDefaultVoiceProfileName: resolution.defaultVoiceProfileName,
            environmentSpeechBackendOverride: environmentOverride?.rawValue,
            environmentQwenResidentModelOverride: qwenResidentModelEnvironmentOverride?.rawValue,
            persistedSpeechBackend: resolution.persistedSpeechBackend?.rawValue,
            persistedQwenResidentModel: resolution.persistedQwenResidentModel?.rawValue,
            persistedMarvisResidentPolicy: resolution.persistedMarvisResidentPolicy?.rawValue,
            persistedDefaultVoiceProfileName: resolution.persistedDefaultVoiceProfileName,
            profileRootPath: profileRootURL.path,
            persistedConfigurationPath: configurationURL.path,
            persistedConfigurationExists: resolution.configurationExists,
            persistedConfigurationState: resolution.configurationState.rawValue,
            persistedConfigurationError: resolution.configurationError,
            persistedConfigurationAppliesOnRestart: true,
            activeRuntimeMatchesNextRuntime: resolvedActiveRuntimeSpeechBackend == resolution.speechBackend
                && resolvedActiveQwenResidentModel == resolution.qwenResidentModel
                && resolvedActiveMarvisResidentPolicy == resolution.marvisResidentPolicy,
            persistedConfigurationWillAffectNextRuntimeStart: environmentOverride == nil
                && qwenResidentModelEnvironmentOverride == nil,
        )
    }

    func save(
        speechBackend: SpeakSwiftly.SpeechBackend,
        qwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeQwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        activeDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        do {
            try savePersistedConfiguration(
                .init(
                    speechBackend: speechBackend,
                    qwenResidentModel: qwenResidentModel
                        ?? current?.qwenResidentModel
                        ?? resolvedPersistedConfiguration().qwenResidentModel,
                    marvisResidentPolicy: marvisResidentPolicy
                        ?? current?.marvisResidentPolicy
                        ?? resolvedPersistedConfiguration().marvisResidentPolicy,
                    defaultVoiceProfileName: current?.defaultVoiceProfileName,
                ),
            )
        } catch {
            throw RuntimeConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted runtime configuration to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeQwenResidentModel: activeQwenResidentModel,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName,
        )
    }

    func saveDefaultVoiceProfileName(
        _ defaultVoiceProfileName: SpeakSwiftly.Name?,
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeQwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        activeMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
        configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) throws -> RuntimeConfigurationSnapshot {
        let current = loadPersistedRuntimeConfiguration()
        do {
            try savePersistedConfiguration(
                .init(
                    speechBackend: current?.speechBackend ?? resolvedPersistedConfiguration().speechBackend,
                    qwenResidentModel: current?.qwenResidentModel ?? resolvedPersistedConfiguration().qwenResidentModel,
                    marvisResidentPolicy: current?.marvisResidentPolicy
                        ?? resolvedPersistedConfiguration().marvisResidentPolicy,
                    defaultVoiceProfileName: defaultVoiceProfileName,
                ),
            )
        } catch {
            throw RuntimeConfigurationStoreError(
                "SpeakSwiftlyServer could not save the persisted default voice profile to '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
        return snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeQwenResidentModel: activeQwenResidentModel,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
            activeDefaultVoiceProfileName: PersistedRuntimeConfiguration.normalized(defaultVoiceProfileName)
                ?? configuredDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuredDefaultVoiceProfileName,
        )
    }

    private func resolvedPersistedConfiguration() -> Resolution {
        Self.resolvePersistedConfiguration(
            environment: environment,
            configurationURL: configurationURL,
            fileSystem: fileSystem,
        )
    }

    private func loadPersistedRuntimeConfiguration() -> PersistedRuntimeConfiguration? {
        let configurationExists = fileSystem.fileExists(atPath: configurationURL.path)
        return Self.loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists,
        )
        .persistedConfiguration
    }

    private func savePersistedConfiguration(_ configuration: PersistedRuntimeConfiguration) throws {
        let directoryURL = configurationURL.deletingLastPathComponent()
        try fileSystem.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try data.write(to: configurationURL, options: .atomic)
    }
}

private extension RuntimeConfigurationStore {
    enum ConfigurationState: String {
        case missing
        case loaded
        case invalid
    }

    struct Resolution {
        let speechBackend: SpeakSwiftly.SpeechBackend
        let qwenResidentModel: SpeakSwiftly.QwenResidentModel
        let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
        let defaultVoiceProfileName: SpeakSwiftly.Name?
        let persistedSpeechBackend: SpeakSwiftly.SpeechBackend?
        let persistedQwenResidentModel: SpeakSwiftly.QwenResidentModel?
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
    ) -> Resolution {
        let configurationExists = fileSystem.fileExists(atPath: configurationURL.path)
        let persistedState = loadPersistedConfiguration(
            from: configurationURL,
            configurationExists: configurationExists,
        )

        if let environmentOverride = SpeakSwiftly.SpeechBackend.configured(in: environment) {
            return .init(
                speechBackend: environmentOverride,
                qwenResidentModel: SpeakSwiftly.QwenResidentModel.configured(in: environment)
                    ?? persistedState.persistedQwenResidentModel
                    ?? .base06B8Bit,
                marvisResidentPolicy: persistedState.persistedMarvisResidentPolicy ?? .dualResidentSerialized,
                defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                persistedSpeechBackend: persistedState.persistedSpeechBackend,
                persistedQwenResidentModel: persistedState.persistedQwenResidentModel,
                persistedMarvisResidentPolicy: persistedState.persistedMarvisResidentPolicy,
                persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                configurationExists: configurationExists,
                configurationState: persistedState.configurationState,
                configurationError: persistedState.configurationError,
            )
        }

        if let persistedSpeechBackend = persistedState.persistedSpeechBackend {
            return .init(
                speechBackend: persistedSpeechBackend,
                qwenResidentModel: SpeakSwiftly.QwenResidentModel.configured(in: environment)
                    ?? persistedState.persistedQwenResidentModel
                    ?? .base06B8Bit,
                marvisResidentPolicy: persistedState.persistedMarvisResidentPolicy ?? .dualResidentSerialized,
                defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                persistedSpeechBackend: persistedSpeechBackend,
                persistedQwenResidentModel: persistedState.persistedQwenResidentModel,
                persistedMarvisResidentPolicy: persistedState.persistedMarvisResidentPolicy,
                persistedDefaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
                configurationExists: configurationExists,
                configurationState: .loaded,
                configurationError: nil,
            )
        }

        return .init(
            speechBackend: .qwen3,
            qwenResidentModel: SpeakSwiftly.QwenResidentModel.configured(in: environment)
                ?? persistedState.persistedQwenResidentModel
                ?? .base06B8Bit,
            marvisResidentPolicy: persistedState.persistedMarvisResidentPolicy ?? .dualResidentSerialized,
            defaultVoiceProfileName: persistedState.persistedDefaultVoiceProfileName,
            persistedSpeechBackend: nil,
            persistedQwenResidentModel: persistedState.persistedQwenResidentModel,
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
    ) -> (
        persistedConfiguration: PersistedRuntimeConfiguration?,
        persistedSpeechBackend: SpeakSwiftly.SpeechBackend?,
        persistedQwenResidentModel: SpeakSwiftly.QwenResidentModel?,
        persistedMarvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy?,
        persistedDefaultVoiceProfileName: SpeakSwiftly.Name?,
        configurationState: ConfigurationState,
        configurationError: String?,
    ) {
        guard configurationExists else {
            return (nil, nil, nil, nil, nil, .missing, nil)
        }

        do {
            let data = try Data(contentsOf: configurationURL)
            let configuration = try JSONDecoder().decode(PersistedRuntimeConfiguration.self, from: data)
            return (
                configuration,
                configuration.speechBackend,
                configuration.qwenResidentModel,
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
                nil,
                .invalid,
                "SpeakSwiftlyServer could not decode the persisted runtime configuration at '\(configurationURL.path)'. Likely cause: \(error.localizedDescription)",
            )
        }
    }
}

struct RuntimeConfigurationStoreError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
