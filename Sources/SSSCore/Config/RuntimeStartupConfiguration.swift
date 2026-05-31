import Configuration
import Foundation
import SpeakSwiftly

package struct RuntimeStartupConfiguration {
    package let speechBackend: SpeakSwiftly.SpeechBackend
    package let duckMediaVolume: SpeakSwiftly.DuckMediaVolume
    package let defaultVoiceProfileName: SpeakSwiftly.Name?

    init(
        speechBackend: SpeakSwiftly.SpeechBackend = .qwen3_smol,
        duckMediaVolume: SpeakSwiftly.DuckMediaVolume = .off,
        defaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) {
        self.speechBackend = speechBackend
        self.duckMediaVolume = duckMediaVolume
        self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
    }

    init(config: ConfigReader, fallbackDefaultVoiceProfileName: SpeakSwiftly.Name?) throws {
        let rawSpeechBackend = try Self.optionalString(config, key: "speechBackend")
        speechBackend = try Self.resolvedSpeechBackend(rawSpeechBackend: rawSpeechBackend)
        let rawDuckMediaVolume = try Self.optionalString(config, key: "duckMediaVolume")
        duckMediaVolume = try Self.resolvedDuckMediaVolume(rawDuckMediaVolume: rawDuckMediaVolume)
        defaultVoiceProfileName = try Self.optionalString(config, key: "defaultVoiceProfileName")
            ?? Self.normalized(fallbackDefaultVoiceProfileName)
    }

    package static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    package static func resolvedSpeechBackend(
        rawSpeechBackend: String?,
    ) throws -> SpeakSwiftly.SpeechBackend {
        try rawSpeechBackend.map {
            try Self.speechBackend($0, label: "speech backend")
        } ?? SpeakSwiftly.SpeechBackend.qwen3_smol
    }

    package static func resolvedDuckMediaVolume(
        rawDuckMediaVolume: String?,
    ) throws -> SpeakSwiftly.DuckMediaVolume {
        try rawDuckMediaVolume.map {
            try Self.duckMediaVolume($0, label: "media volume ducking")
        } ?? .off
    }

    package static func speechBackend(
        _ rawValue: String,
        label: String,
    ) throws -> SpeakSwiftly.SpeechBackend {
        guard let value = SpeakSwiftly.SpeechBackend.normalized(rawValue: rawValue) else {
            throw ServerConfigurationError(
                "Configuration value for \(label) has unsupported value '\(rawValue)'.",
            )
        }

        return value
    }

    package static func duckMediaVolume(
        _ rawValue: String,
        label: String,
    ) throws -> SpeakSwiftly.DuckMediaVolume {
        guard let value = SpeakSwiftly.DuckMediaVolume(rawValue: rawValue) else {
            let supportedValues = SpeakSwiftly.DuckMediaVolume.allCases.map(\.rawValue).joined(separator: ", ")
            throw ServerConfigurationError(
                "Configuration value for \(label) has unsupported value '\(rawValue)'. Supported values: \(supportedValues).",
            )
        }

        return value
    }

    private static func optionalString(
        _ config: ConfigReader,
        key: ConfigKey,
    ) throws -> String? {
        do {
            return try normalized(config.requiredString(forKey: key))
        } catch {
            guard String(describing: error).contains("Missing required config value for key:") else {
                throw error
            }

            return nil
        }
    }

    package func speakSwiftlyConfiguration(configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil) -> SpeakSwiftly.Configuration {
        let systemProfileResourceRoots = SpeakSwiftly.SupportResources
            .systemProfileRootURL(in: .module)
            .map { [$0] } ?? []

        return .init(
            speechBackend: speechBackend,
            qwenConditioningStrategy: .preparedConditioning,
            defaultVoiceProfile: defaultVoiceProfileName
                ?? Self.normalized(configuredDefaultVoiceProfileName)
                ?? SpeakSwiftly.DefaultVoiceProfiles.signal,
            duckMediaVolume: duckMediaVolume,
            audioOutputDestination: .localPlayback,
            systemProfileResourceRoots: systemProfileResourceRoots,
        )
    }
}
