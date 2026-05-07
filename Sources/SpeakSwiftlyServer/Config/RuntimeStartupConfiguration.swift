import Configuration
import Foundation
import SpeakSwiftly

struct RuntimeStartupConfiguration {
    let speechBackend: SpeakSwiftly.SpeechBackend
    let marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy
    let defaultVoiceProfileName: SpeakSwiftly.Name?

    init(
        speechBackend: SpeakSwiftly.SpeechBackend = .qwen3_smol,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy = .dualResidentSerialized,
        defaultVoiceProfileName: SpeakSwiftly.Name? = nil,
    ) {
        self.speechBackend = speechBackend
        self.marvisResidentPolicy = marvisResidentPolicy
        self.defaultVoiceProfileName = Self.normalized(defaultVoiceProfileName)
    }

    init(config: ConfigReader, fallbackDefaultVoiceProfileName: SpeakSwiftly.Name?) throws {
        let rawSpeechBackend = try Self.optionalString(config, key: "speechBackend")
        let rawLegacyQwenResidentModel = try Self.optionalString(config, key: "qwenResidentModel")
        speechBackend = try Self.resolvedSpeechBackend(
            rawSpeechBackend: rawSpeechBackend,
            rawLegacyQwenResidentModel: rawLegacyQwenResidentModel,
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

    static func resolvedSpeechBackend(
        rawSpeechBackend: String?,
        rawLegacyQwenResidentModel: String?,
    ) throws -> SpeakSwiftly.SpeechBackend {
        let speechBackend: SpeakSwiftly.SpeechBackend = try rawSpeechBackend.map {
            try Self.speechBackend($0, label: "speech backend")
        } ?? SpeakSwiftly.SpeechBackend.qwen3_smol

        guard isQwenSpeechBackend(speechBackend),
              let legacyQwenResidentModel = try rawLegacyQwenResidentModel.map({
                  try Self.speechBackend(forLegacyQwenResidentModel: $0)
              })
        else {
            return speechBackend
        }

        return legacyQwenResidentModel
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

    static func isQwenSpeechBackend(_ speechBackend: SpeakSwiftly.SpeechBackend) -> Bool {
        switch speechBackend {
            case .qwen3_smol,
                 .qwen3_smol_6bit,
                 .qwen3_smol_8bit,
                 .qwen3_smol_bf16,
                 .qwen3_BIG,
                 .qwen3_BIG_6bit,
                 .qwen3_BIG_8bit,
                 .qwen3_BIG_bf16:
                true
            case .chatterboxTurbo,
                 .marvis:
                false
        }
    }

    static func speechBackend(forLegacyQwenResidentModel rawValue: String) throws -> SpeakSwiftly.SpeechBackend {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "base_0_6b_8bit":
                return .qwen3_smol
            case "base_1_7b_8bit":
                return .qwen3_BIG
            default:
                throw ServerConfigurationError(
                    "Configuration value 'APP_RUNTIME_QWENRESIDENTMODEL' has unsupported legacy Qwen resident model '\(rawValue)'. Use a Qwen speech_backend value instead.",
                )
        }
    }

    static func legacyQwenResidentModelRawValue(for speechBackend: SpeakSwiftly.SpeechBackend) -> String {
        switch speechBackend {
            case .qwen3_BIG, .qwen3_BIG_6bit, .qwen3_BIG_8bit, .qwen3_BIG_bf16:
                "base_1_7b_8bit"
            default:
                "base_0_6b_8bit"
        }
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
        let systemProfileResourceRoots = SpeakSwiftly.SupportResources
            .systemProfileRootURL(in: .module)
            .map { [$0] } ?? []

        return .init(
            speechBackend: speechBackend,
            marvisResidentPolicy: marvisResidentPolicy,
            defaultVoiceProfile: defaultVoiceProfileName
                ?? Self.normalized(configuredDefaultVoiceProfileName)
                ?? SpeakSwiftly.DefaultVoiceProfiles.signal,
            systemProfileResourceRoots: systemProfileResourceRoots,
        )
    }
}
