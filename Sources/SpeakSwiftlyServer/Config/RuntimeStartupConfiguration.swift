import Configuration
import Foundation
import SpeakSwiftly

struct RuntimeStartupConfiguration {
    let speechBackend: SpeakSwiftly.SpeechBackend
    let defaultVoiceProfileName: SpeakSwiftly.Name?

    init(
        speechBackend: SpeakSwiftly.SpeechBackend = .qwen3_smol,
        defaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) {
        self.speechBackend = speechBackend
        self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
    }

    init(config: ConfigReader, fallbackDefaultVoiceProfileName: SpeakSwiftly.Name?) throws {
        let rawSpeechBackend = try Self.optionalString(config, key: "speechBackend")
        speechBackend = try Self.resolvedSpeechBackend(rawSpeechBackend: rawSpeechBackend)
        defaultVoiceProfileName = try Self.optionalString(config, key: "defaultVoiceProfileName")
            ?? Self.normalized(fallbackDefaultVoiceProfileName)
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    static func resolvedSpeechBackend(
        rawSpeechBackend: String?,
    ) throws -> SpeakSwiftly.SpeechBackend {
        try rawSpeechBackend.map {
            try Self.speechBackend($0, label: "speech backend")
        } ?? SpeakSwiftly.SpeechBackend.qwen3_smol
    }

    static func speechBackend(
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

    func speakSwiftlyConfiguration(configuredDefaultVoiceProfileName: SpeakSwiftly.Name? = nil) -> SpeakSwiftly.Configuration {
        let systemProfileResourceRoots = SpeakSwiftly.SupportResources
            .systemProfileRootURL(in: .module)
            .map { [$0] } ?? []

        return .init(
            speechBackend: speechBackend,
            defaultVoiceProfile: defaultVoiceProfileName
                ?? Self.normalized(configuredDefaultVoiceProfileName)
                ?? SpeakSwiftly.DefaultVoiceProfiles.signal,
            systemProfileResourceRoots: systemProfileResourceRoots,
        )
    }
}
