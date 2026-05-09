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

struct SpeechRequestContextDefaults {
    var reqPurpose: SpeakSwiftly.RequestContext.RequestPurpose
    var source: String?
    var topic: String?
    var cwd: String?
    var repoRoot: String?
    var attributes: [String: String]
    var prefacePolicy: SpeakSwiftly.RequestContext.PrefacePolicy?

    init(
        reqPurpose: SpeakSwiftly.RequestContext.RequestPurpose = .speech,
        source: String? = nil,
        topic: String? = nil,
        cwd: String? = nil,
        repoRoot: String? = nil,
        attributes: [String: String] = [:],
        prefacePolicy: SpeakSwiftly.RequestContext.PrefacePolicy? = nil,
    ) {
        self.reqPurpose = reqPurpose
        self.source = source
        self.topic = topic
        self.cwd = cwd
        self.repoRoot = repoRoot
        self.attributes = attributes
        self.prefacePolicy = prefacePolicy
    }
}

func makeSpeechRequestContext(
    cwd: String?,
    repoRoot: String?,
    requestContext: SpeakSwiftly.RequestContext?,
    defaults: SpeechRequestContextDefaults = .init(),
) -> SpeakSwiftly.RequestContext? {
    let merged = SpeakSwiftly.RequestContext(
        reqPurpose: defaults.reqPurpose,
        source: requestContext?.source ?? defaults.source,
        topic: requestContext?.topic ?? defaults.topic,
        cwd: cwd ?? requestContext?.cwd ?? defaults.cwd,
        repoRoot: repoRoot ?? requestContext?.repoRoot ?? defaults.repoRoot,
        attributes: mergedRequestContextAttributes(
            defaults: defaults.attributes,
            request: requestContext?.attributes ?? [:],
        ),
        prefacePolicy: requestContext?.prefacePolicy ?? defaults.prefacePolicy,
    )
    guard
        merged.source != nil
        || merged.topic != nil
        || merged.cwd != nil
        || merged.repoRoot != nil
        || !merged.attributes.isEmpty
    else {
        return nil
    }

    return merged
}

private func mergedRequestContextAttributes(
    defaults: [String: String],
    request: [String: String],
) -> [String: String] {
    var attributes = defaults.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    for (key, value) in request where !key.isEmpty && !value.isEmpty {
        attributes[key] = value
    }
    return attributes
}

struct SpeakRequestPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case requestContext = "request_context"
        case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
    }

    let text: String
    let profileName: String?
    let textProfileID: String?
    let cwd: String?
    let repoRoot: String?
    let requestContext: SpeakSwiftly.RequestContext?
    let qwenPreModelTextChunking: Bool?

    func resolvedRequestContext(defaults: SpeechRequestContextDefaults = .init()) -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
            defaults: defaults,
        )
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
        case requestContext = "request_context"
    }

    let artifactID: String?
    let text: String
    let textProfileID: String?
    let cwd: String?
    let repoRoot: String?
    let requestContext: SpeakSwiftly.RequestContext?

    func model(requestContextDefaults: SpeechRequestContextDefaults = .init()) -> SpeakSwiftly.BatchItem {
        .init(
            artifactID: artifactID,
            text: text,
            textProfile: textProfileID,
            requestContext: resolvedRequestContext(defaults: requestContextDefaults),
        )
    }

    private func resolvedRequestContext(defaults: SpeechRequestContextDefaults = .init()) -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
            defaults: defaults,
        )
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
    let sequence: Int
    let capturedAt: Date
    let state: String
    let speechBackend: String
    let residentState: String
    let defaultVoiceProfile: String
    let storage: RuntimeStorageObservationSnapshot
    let runtimeBackendTransition: RuntimeBackendTransitionSnapshot

    init(
        runtime: SpeakSwiftly.RuntimeSnapshot,
        runtimeBackendTransition: RuntimeBackendTransitionSnapshot,
    ) {
        sequence = runtime.sequence
        capturedAt = runtime.capturedAt
        state = runtime.state.rawValue
        speechBackend = runtime.speechBackend.rawValue
        residentState = runtime.residentState.rawValue
        defaultVoiceProfile = runtime.defaultVoiceProfile
        storage = .init(runtime.storage)
        self.runtimeBackendTransition = runtimeBackendTransition
    }

    enum CodingKeys: String, CodingKey {
        case sequence
        case capturedAt = "captured_at"
        case state
        case speechBackend = "speech_backend"
        case residentState = "resident_state"
        case defaultVoiceProfile = "default_voice_profile"
        case storage
        case runtimeBackendTransition = "runtime_backend_transition"
    }
}

struct RuntimeStorageObservationSnapshot: Encodable {
    let stateRootPath: String
    let profileStoreRootPath: String
    let configurationPath: String
    let textProfilesPath: String
    let generatedFilesRootPath: String
    let generationJobsRootPath: String

    init(_ snapshot: SpeakSwiftly.RuntimeStorageSnapshot) {
        stateRootPath = snapshot.stateRootPath
        profileStoreRootPath = snapshot.profileStoreRootPath
        configurationPath = snapshot.configurationPath
        textProfilesPath = snapshot.textProfilesPath
        generatedFilesRootPath = snapshot.generatedFilesRootPath
        generationJobsRootPath = snapshot.generationJobsRootPath
    }

    enum CodingKeys: String, CodingKey {
        case stateRootPath = "state_root_path"
        case profileStoreRootPath = "profile_store_root_path"
        case configurationPath = "configuration_path"
        case textProfilesPath = "text_profiles_path"
        case generatedFilesRootPath = "generated_files_root_path"
        case generationJobsRootPath = "generation_jobs_root_path"
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
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedSpeechBackendDescription()).",
        )
    }

    return speechBackend
}
