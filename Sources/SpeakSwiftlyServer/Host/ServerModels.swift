import Foundation
import Hummingbird
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Request Models

struct SpeakRequestPayload: Decodable {
    let text: String
    let profileName: String?
    let textProfileName: String?
    let cwd: String?
    let repoRoot: String?
    let textFormat: String?
    let nestedSourceFormat: String?
    let sourceFormat: String?

    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case cwd
        case repoRoot = "repo_root"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case sourceFormat = "source_format"
    }

    func normalizationContext() throws -> SpeechNormalizationContext? {
        let resolvedTextFormat = try textFormat.flatMap(resolveRequestTextFormat(_:))
        let resolvedNestedSourceFormat = try nestedSourceFormat.flatMap {
            try resolveSourceFormat($0, fieldName: "nested_source_format")
        }
        let context = SpeechNormalizationContext(
            cwd: cwd,
            repoRoot: repoRoot,
            textFormat: resolvedTextFormat,
            nestedSourceFormat: resolvedNestedSourceFormat
        )
        guard
            context.cwd != nil
                || context.repoRoot != nil
                || context.textFormat != nil
                || context.nestedSourceFormat != nil
        else {
            return nil
        }
        return context
    }

    func sourceFormatModel() throws -> TextForSpeech.SourceFormat? {
        try sourceFormat.flatMap { try resolveSourceFormat($0, fieldName: "source_format") }
    }
}

struct CreateProfileRequestPayload: Decodable {
    let profileName: String
    let vibe: String
    let text: String
    let voiceDescription: String
    let outputPath: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case text
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
        case cwd
    }

    func vibeModel() throws -> SpeakSwiftly.Vibe {
        try resolveVibe(vibe, fieldName: "vibe")
    }
}

struct CreateCloneRequestPayload: Decodable {
    let profileName: String
    let vibe: String
    let referenceAudioPath: String
    let transcript: String?
    let cwd: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case referenceAudioPath = "reference_audio_path"
        case transcript
        case cwd
    }

    func vibeModel() throws -> SpeakSwiftly.Vibe {
        try resolveVibe(vibe, fieldName: "vibe")
    }
}

struct GenerateBatchRequestPayload: Decodable {
    let profileName: String?
    let items: [BatchItemRequestPayload]

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case items
    }
}

struct BatchItemRequestPayload: Decodable {
    let artifactID: String?
    let text: String
    let textProfileName: String?
    let cwd: String?
    let repoRoot: String?
    let textFormat: String?
    let nestedSourceFormat: String?
    let sourceFormat: String?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileName = "text_profile_name"
        case cwd
        case repoRoot = "repo_root"
        case textFormat = "text_format"
        case nestedSourceFormat = "nested_source_format"
        case sourceFormat = "source_format"
    }

    func model() throws -> SpeakSwiftly.BatchItem {
        .init(
            artifactID: artifactID,
            text: text,
            textProfileName: textProfileName,
            textContext: try normalizationContext(),
            sourceFormat: try sourceFormatModel()
        )
    }

    private func normalizationContext() throws -> SpeechNormalizationContext? {
        let resolvedTextFormat = try textFormat.flatMap(resolveRequestTextFormat(_:))
        let resolvedNestedSourceFormat = try nestedSourceFormat.flatMap {
            try resolveSourceFormat($0, fieldName: "nested_source_format")
        }
        let context = SpeechNormalizationContext(
            cwd: cwd,
            repoRoot: repoRoot,
            textFormat: resolvedTextFormat,
            nestedSourceFormat: resolvedNestedSourceFormat
        )
        guard
            context.cwd != nil
                || context.repoRoot != nil
                || context.textFormat != nil
                || context.nestedSourceFormat != nil
        else {
            return nil
        }
        return context
    }

    private func sourceFormatModel() throws -> TextForSpeech.SourceFormat? {
        try sourceFormat.flatMap { try resolveSourceFormat($0, fieldName: "source_format") }
    }
}

struct RuntimeConfigurationUpdatePayload: Decodable {
    let speechBackend: String

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
    }

    func speechBackendModel() throws -> SpeakSwiftly.SpeechBackend {
        try resolveSpeechBackend(speechBackend, fieldName: "speech_backend")
    }
}

struct RequestAcceptedResponse: ResponseEncodable, Sendable {
    let requestID: String
    let requestURL: String
    let eventsURL: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestURL = "request_url"
        case eventsURL = "events_url"
    }
}

struct RequestListResponse: ResponseEncodable, Sendable {
    let requests: [JobSnapshot]
}

struct RuntimeStatusResponse: ResponseEncodable, Sendable {
    let status: SpeakSwiftly.StatusEvent
}

struct RuntimeBackendResponse: ResponseEncodable, Sendable {
    let speechBackend: String

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
    }
}

// MARK: - Helpers

enum TimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

enum NormalizationFormat: Sendable {
    case text(TextForSpeech.TextFormat)
    case source(TextForSpeech.SourceFormat)
}

func resolveNormalizationFormat(_ rawValue: String) throws -> NormalizationFormat {
    if let format = TextForSpeech.TextFormat(rawValue: rawValue) {
        return .text(format)
    }
    if let format = TextForSpeech.SourceFormat(rawValue: rawValue) {
        return .source(format)
    }

    let supportedFormats = (
        TextForSpeech.TextFormat.allCases.map(\.rawValue)
        + TextForSpeech.SourceFormat.allCases.map(\.rawValue)
    ).joined(separator: ", ")
    throw HTTPError(
        .badRequest,
        message: "Text replacement format '\(rawValue)' is not supported. Expected one of: \(supportedFormats)."
    )
}

private func resolveRequestTextFormat(_ rawValue: String) throws -> TextForSpeech.TextFormat {
    guard let format = TextForSpeech.TextFormat(rawValue: rawValue) else {
        let supportedFormats = TextForSpeech.TextFormat.allCases.map(\.rawValue)
        throw HTTPError(
            .badRequest,
            message: "Speech request text_format '\(rawValue)' is not supported. Expected one of: \(supportedFormats.joined(separator: ", "))."
        )
    }
    return format
}

private func resolveSourceFormat(
    _ rawValue: String,
    fieldName: String
) throws -> TextForSpeech.SourceFormat {
    guard let format = TextForSpeech.SourceFormat(rawValue: rawValue) else {
        let supportedFormats = TextForSpeech.SourceFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Speech request \(fieldName) '\(rawValue)' is not supported. Expected one of: \(supportedFormats)."
        )
    }
    return format
}

private func resolveVibe(
    _ rawValue: String,
    fieldName: String
) throws -> SpeakSwiftly.Vibe {
    guard let vibe = SpeakSwiftly.Vibe(rawValue: rawValue) else {
        let supportedVibes = SpeakSwiftly.Vibe.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Voice profile field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedVibes)."
        )
    }
    return vibe
}

private func resolveSpeechBackend(
    _ rawValue: String,
    fieldName: String
) throws -> SpeakSwiftly.SpeechBackend {
    guard let speechBackend = SpeakSwiftly.SpeechBackend(rawValue: rawValue) else {
        let supportedBackends = SpeakSwiftly.SpeechBackend.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedBackends)."
        )
    }
    return speechBackend
}
