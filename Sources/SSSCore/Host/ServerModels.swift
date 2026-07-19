import Foundation
import SpeakSwiftly

package func exposedSpeechBackendIdentifiers() -> [String] {
    SpeakSwiftly.SpeechBackend.allCases.map(\.rawValue)
}

package func supportedSpeechBackendDescription() -> String {
    exposedSpeechBackendIdentifiers().joined(separator: ", ")
}

package struct SpeechRequestContextDefaults {
    package var reqPurpose: SpeakSwiftly.RequestContext.RequestPurpose
    package var source: String?
    package var topic: String?
    package var cwd: String?
    package var repoRoot: String?
    package var attributes: [String: String]
    package var prefacePolicy: SpeakSwiftly.RequestContext.PrefacePolicy?

    package init(
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

package struct SpeechRequestContextPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case source
        case topic
        case cwd
        case repoRoot
        case repoRootSnake = "repo_root"
        case attributes
        case prefacePolicy
    }

    package let source: String?
    package let topic: String?
    package let cwd: String?
    package let repoRoot: String?
    package let attributes: [String: String]
    package let prefacePolicy: SpeakSwiftly.RequestContext.PrefacePolicy?

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        topic = try container.decodeIfPresent(String.self, forKey: .topic)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        repoRoot = try container.decodeIfPresent(String.self, forKey: .repoRootSnake)
            ?? container.decodeIfPresent(String.self, forKey: .repoRoot)
        attributes = try container.decodeIfPresent([String: String].self, forKey: .attributes) ?? [:]
        prefacePolicy = try container.decodeIfPresent(
            SpeakSwiftly.RequestContext.PrefacePolicy.self,
            forKey: .prefacePolicy,
        )
    }

    init(
        source: String? = nil,
        topic: String? = nil,
        cwd: String? = nil,
        repoRoot: String? = nil,
        attributes: [String: String] = [:],
        prefacePolicy: SpeakSwiftly.RequestContext.PrefacePolicy? = nil,
    ) {
        self.source = source
        self.topic = topic
        self.cwd = cwd
        self.repoRoot = repoRoot
        self.attributes = attributes
        self.prefacePolicy = prefacePolicy
    }
}

package func makeSpeechRequestContext(
    cwd: String?,
    repoRoot: String?,
    requestContext: SpeechRequestContextPayload?,
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
        || merged.prefacePolicy != nil
        || defaults.reqPurpose != .speech
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

package struct SpeakRequestPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case requestContext = "request_context"
        case qwenPreModelTextChunking = "qwen_pre_model_text_chunking"
        case generationLocation = "generation_location"
    }

    package let text: String
    package let profileName: String?
    package let textProfileID: String?
    package let cwd: String?
    package let repoRoot: String?
    package let requestContext: SpeechRequestContextPayload?
    package let qwenPreModelTextChunking: Bool?
    package let generationLocation: GenerationLocation?

    package func resolvedRequestContext(defaults: SpeechRequestContextDefaults = .init()) -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
            defaults: defaults,
        )
    }
}

package struct CreateProfileRequestPayload: Decodable {
    package let profileName: String
    package let vibe: String
    package let text: String
    package let voiceDescription: String
    package let outputPath: String?
    package let cwd: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case text
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
        case cwd
    }

    package func vibeModel() throws -> SpeakSwiftly.Vibe {
        try resolveVibe(vibe, fieldName: "vibe")
    }
}

package struct CreateCloneRequestPayload: Decodable {
    package let profileName: String
    package let vibe: String
    package let referenceAudioPath: String
    package let transcript: String?
    package let cwd: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case referenceAudioPath = "reference_audio_path"
        case transcript
        case cwd
    }

    package func vibeModel() throws -> SpeakSwiftly.Vibe {
        try resolveVibe(vibe, fieldName: "vibe")
    }
}

package struct GenerateBatchRequestPayload: Decodable {
    package let profileName: String?
    package let items: [BatchItemRequestPayload]

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case items
    }
}

package struct BatchItemRequestPayload: Decodable {
    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileID = "text_profile_id"
        case cwd
        case repoRoot = "repo_root"
        case requestContext = "request_context"
    }

    package let artifactID: String?
    package let text: String
    package let textProfileID: String?
    package let cwd: String?
    package let repoRoot: String?
    package let requestContext: SpeechRequestContextPayload?

    package func model(requestContextDefaults: SpeechRequestContextDefaults = .init()) -> SpeakSwiftly.BatchItem {
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

package struct RuntimeConfigurationUpdatePayload: Decodable {
    package let speechBackend: String
    package let duckMediaVolume: String?

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
        case duckMediaVolume = "duck_media_volume"
    }

    package func speechBackendModel() throws -> SpeakSwiftly.SpeechBackend {
        try resolveSpeechBackend(speechBackend, fieldName: "speech_backend")
    }

    package func duckMediaVolumeModel(default defaultValue: SpeakSwiftly.DuckMediaVolume) throws -> SpeakSwiftly.DuckMediaVolume {
        try duckMediaVolume.map {
            try RuntimeStartupConfiguration.duckMediaVolume($0, label: "duck_media_volume")
        } ?? defaultValue
    }
}

package struct RequestAcceptedResponse: Encodable {
    package let requestID: String
    package let requestURL: String
    package let eventsURL: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case requestURL = "request_url"
        case eventsURL = "events_url"
    }

    package init(requestID: String, requestURL: String, eventsURL: String) {
        self.requestID = requestID
        self.requestURL = requestURL
        self.eventsURL = eventsURL
    }
}

package struct RequestListResponse: Encodable {
    package let requests: [JobSnapshot]

    package init(requests: [JobSnapshot]) {
        self.requests = requests
    }
}

package struct RuntimeStatusResponse: Encodable {
    package let sequence: Int
    package let capturedAt: Date
    package let state: String
    package let speechBackend: String
    package let residentState: String
    package let defaultVoiceProfile: String
    package let storage: RuntimeStorageObservationSnapshot
    package let runtimeBackendTransition: RuntimeBackendTransitionSnapshot

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

package struct RuntimeStorageObservationSnapshot: Encodable {
    package let stateRootPath: String
    package let profileStoreRootPath: String
    package let configurationPath: String
    package let textProfilesPath: String
    package let generatedFilesRootPath: String
    package let generationJobsRootPath: String

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

package struct RuntimeBackendResponse: Encodable {
    package let speechBackend: String

    enum CodingKeys: String, CodingKey {
        case speechBackend = "speech_backend"
    }
}

package enum TimestampFormatter {
    package static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

package enum NormalizationFormat {
    case text(SpeakSwiftly.TextFormat)
    case source(SpeakSwiftly.SourceFormat)
}

package func resolveNormalizationFormat(_ rawValue: String) throws -> NormalizationFormat {
    if let format = SpeakSwiftly.TextFormat(rawValue: rawValue) {
        return .text(format)
    }
    if let format = SpeakSwiftly.SourceFormat(rawValue: rawValue) {
        return .source(format)
    }

    let supportedFormats = (
        SpeakSwiftly.TextFormat.allCases.map(\.rawValue)
            + SpeakSwiftly.SourceFormat.allCases.map(\.rawValue),
    ).joined(separator: ", ")
    throw ServerRequestError(
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
        throw ServerRequestError(
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
        throw ServerRequestError(
            .badRequest,
            message: "Runtime configuration field '\(fieldName)' used unsupported value '\(rawValue)'. Expected one of: \(supportedSpeechBackendDescription()).",
        )
    }

    return speechBackend
}
