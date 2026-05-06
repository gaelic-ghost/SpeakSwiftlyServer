import Configuration
import Foundation
import SpeakSwiftly

struct RuntimeStartupConfiguration {
    let speechBackend: SpeakSwiftly.SpeechBackend
    let qwenResidentModel: SpeakSwiftly.QwenResidentModel
    let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
    let defaultVoiceProfileName: SpeakSwiftly.Name?

    init(
        speechBackend: SpeakSwiftly.SpeechBackend = .qwen3,
        qwenResidentModel: SpeakSwiftly.QwenResidentModel = .base06B8Bit,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy = .dualResidentSerialized,
        defaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) {
        self.speechBackend = speechBackend
        self.qwenResidentModel = qwenResidentModel
        self.marvisResidentPolicy = marvisResidentPolicy
        self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
    }

    init(config: ConfigReader, fallbackDefaultVoiceProfileName: SpeakSwiftly.Name?) throws {
        speechBackend = try Self.optionalRawValue(
            config,
            key: "speechBackend",
            fallback: SpeakSwiftly.SpeechBackend.qwen3,
            label: "speech backend",
        )
        qwenResidentModel = try Self.optionalRawValue(
            config,
            key: "qwenResidentModel",
            fallback: SpeakSwiftly.QwenResidentModel.base06B8Bit,
            label: "Qwen resident model",
        )
        marvisResidentPolicy = try Self.optionalRawValue(
            config,
            key: "marvisResidentPolicy",
            fallback: SpeakSwiftly.MarvisResidentPolicy.dualResidentSerialized,
            label: "Marvis resident policy",
        )
        defaultVoiceProfileName = try Self.optionalString(config, key: "defaultVoiceProfileName")
            ?? Self.normalized(fallbackDefaultVoiceProfileName)
    }

    static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func optionalRawValue<Value: RawRepresentable>(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: Value,
        label: String,
    ) throws -> Value where Value.RawValue == String {
        guard let rawValue = try optionalString(config, key: key) else {
            return fallback
        }
        guard let value = Value(rawValue: rawValue) else {
            throw ServerConfigurationError(
                "Configuration value 'APP_RUNTIME_\(String(describing: key).uppercased())' has unsupported \(label) '\(rawValue)'.",
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
        .init(
            speechBackend: speechBackend,
            qwenResidentModel: qwenResidentModel,
            marvisResidentPolicy: marvisResidentPolicy,
            defaultVoiceProfile: defaultVoiceProfileName
                ?? Self.normalized(configuredDefaultVoiceProfileName)
                ?? SpeakSwiftly.DefaultVoiceProfiles.signal,
        )
    }
}
