import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

func exposedSpeechBackendIdentifiers() -> [String] {
    SpeakSwiftly.SpeechBackend.allCases.map(\.rawValue)
}

func supportedSpeechBackendDescription() -> String {
    exposedSpeechBackendIdentifiers().joined(separator: ", ")
}

func legacySpeechBackendNormalizationNote() -> String {
    "The legacy value '\(SpeakSwiftly.SpeechBackend.legacyQwenCustomVoiceRawValue)' is still accepted and normalized to 'qwen3'."
}

func exposedQwenResidentModelIdentifiers() -> [String] {
    SpeakSwiftly.QwenResidentModel.allCases.map(\.rawValue)
}

func supportedQwenResidentModelDescription() -> String {
    exposedQwenResidentModelIdentifiers().joined(separator: ", ")
}

func exposedMarvisResidentPolicyIdentifiers() -> [String] {
    SpeakSwiftly.MarvisResidentPolicy.allCases.map(\.rawValue)
}

func supportedMarvisResidentPolicyDescription() -> String {
    exposedMarvisResidentPolicyIdentifiers().joined(separator: ", ")
}

func makeSpeechRequestContext(
    cwd: String?,
    repoRoot: String?,
    requestContext: SpeakSwiftly.RequestContext?,
) -> SpeakSwiftly.RequestContext? {
    let merged = SpeakSwiftly.RequestContext(
        source: requestContext?.source,
        app: requestContext?.app,
        agent: requestContext?.agent,
        project: requestContext?.project,
        topic: requestContext?.topic,
        cwd: cwd ?? requestContext?.cwd,
        repoRoot: repoRoot ?? requestContext?.repoRoot,
        attributes: requestContext?.attributes ?? [:],
    )
    guard
        merged.source != nil
        || merged.app != nil
        || merged.agent != nil
        || merged.project != nil
        || merged.topic != nil
        || merged.cwd != nil
        || merged.repoRoot != nil
        || !merged.attributes.isEmpty
    else {
        return nil
    }

    return merged
}

func makeSpeechSourceFormat(_ rawValue: String?) throws -> TextForSpeech.SourceFormat? {
    try rawValue.flatMap { try resolveSourceFormat($0, fieldName: "source_format") }
}

struct SpeakRequestPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case sourceFormat = "source_format"
        case requestContext = "request_context"
        case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
    }

    let text: String
    let profileName: String?
    let textProfileID: String?
    let cwd: String?
    let repoRoot: String?
    let sourceFormat: String?
    let requestContext: SpeakSwiftly.RequestContext?
    let qwenPreModelTextChunking: Bool?

    func resolvedRequestContext() -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
        )
    }

    func sourceFormatModel() throws -> TextForSpeech.SourceFormat? {
        try makeSpeechSourceFormat(sourceFormat)
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
    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case sourceFormat = "source_format"
        case requestContext = "request_context"
    }

    let artifactID: String?
    let text: String
    let textProfileID: String?
    let cwd: String?
    let repoRoot: String?
    let sourceFormat: String?
    let requestContext: SpeakSwiftly.RequestContext?

    func model() throws -> SpeakSwiftly.BatchItem {
        try .init(
            artifactID: artifactID,
            text: text,
            textProfile: textProfileID,
            sourceFormat: sourceFormatModel(),
            requestContext: resolvedRequestContext(),
        )
    }

    private func resolvedRequestContext() -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
        )
    }

    private func sourceFormatModel() throws -> TextForSpeech.SourceFormat? {
        try makeSpeechSourceFormat(sourceFormat)
    }
}

struct RuntimeConfigurationUpdatePayload: Decodable {
    let speechBackend: String
    let qwenResidentModel: String?
    let marvisResidentPolicy: String?

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
        case qwenResidentModel = "qwen_resident_model"
        case marvisResidentPolicy = "marvis_resident_policy"
    }

    func speechBackendModel() throws -> SpeakSwiftly.SpeechBackend {
        try resolveSpeechBackend(speechBackend, fieldName: "speech_backend")
    }

    func qwenResidentModelModel() throws -> SpeakSwiftly.QwenResidentModel? {
        try qwenResidentModel.map {
            try resolveQwenResidentModel($0, fieldName: "qwen_resident_model")
        }
    }

    func marvisResidentPolicyModel() throws -> SpeakSwiftly.MarvisResidentPolicy? {
        try marvisResidentPolicy.map {
            try resolveMarvisResidentPolicy($0, fieldName: "marvis_resident_policy")
        }
    }
}

struct RequestAcceptedResponse: ResponseEncodable {
    let requestID: String
    let requestURL: String
    let eventsURL: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestURL = "request_url"
        case eventsURL = "events_url"
    }
}

struct RequestListResponse: ResponseEncodable {
    let requests: [JobSnapshot]
}

struct RuntimeStatusResponse: ResponseEncodable {
    let status: SpeakSwiftly.StatusEvent
    let runtimeBackendTransition: RuntimeBackendTransitionSnapshot

    enum CodingKeys: String, CodingKey {
        case status
        case runtimeBackendTransition = "runtime_backend_transition"
    }
}

struct RuntimeBackendResponse: ResponseEncodable {
    let speechBackend: String

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
    }
}

enum TimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

enum NormalizationFormat {
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
            + TextForSpeech.SourceFormat.allCases.map(\.rawValue),
    ).joined(separator: ", ")
    throw HTTPError(
        .badRequest,
        message: "Text replacement format '\(rawValue)' is not supported. Expected one of: \(supportedFormats).",
    )
}

private func resolveSourceFormat(
    _ rawValue: String,
    fieldName: String,
) throws -> TextForSpeech.SourceFormat {
    guard let format = TextForSpeech.SourceFormat(rawValue: rawValue) else {
        let supportedFormats = TextForSpeech.SourceFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Speech request \(fieldName) '\(rawValue)' is not supported. Expected one of: \(supportedFormats).",
        )
    }

    return format
}

private func resolveVibe(
    _ rawValue: String,
    fieldName: String,
) throws -> SpeakSwiftly.Vibe {
    guard let vibe = SpeakSwiftly.Vibe(rawValue: rawValue) else {
        let supportedVibes = SpeakSwiftly.Vibe.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Voice profile field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedVibes).",
        )
    }

    return vibe
}

private func resolveSpeechBackend(
    _ rawValue: String,
    fieldName: String,
) throws -> SpeakSwiftly.SpeechBackend {
    guard let speechBackend = SpeakSwiftly.SpeechBackend.normalized(rawValue: rawValue) else {
        throw HTTPError(
            .badRequest,
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedSpeechBackendDescription()). \(legacySpeechBackendNormalizationNote())",
        )
    }

    return speechBackend
}

private func resolveQwenResidentModel(
    _ rawValue: String,
    fieldName: String,
) throws -> SpeakSwiftly.QwenResidentModel {
    guard let qwenResidentModel = SpeakSwiftly.QwenResidentModel(rawValue: rawValue) else {
        throw HTTPError(
            .badRequest,
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedQwenResidentModelDescription()).",
        )
    }

    return qwenResidentModel
}

private func resolveMarvisResidentPolicy(
    _ rawValue: String,
    fieldName: String,
) throws -> SpeakSwiftly.MarvisResidentPolicy {
    guard let marvisResidentPolicy = SpeakSwiftly.MarvisResidentPolicy(rawValue: rawValue) else {
        throw HTTPError(
            .badRequest,
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedMarvisResidentPolicyDescription()).",
        )
    }

    return marvisResidentPolicy
}
