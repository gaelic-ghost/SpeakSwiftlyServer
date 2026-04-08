import Foundation
import Hummingbird
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Request Models

struct SpeakRequestPayload: Decodable {
    let text: String
    let profileName: String
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

struct JobCreatedResponse: ResponseEncodable, Sendable {
    let jobID: String
    let jobURL: String
    let eventsURL: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case jobURL = "job_url"
        case eventsURL = "events_url"
    }
}

struct JobListResponse: ResponseEncodable, Sendable {
    let jobs: [JobSnapshot]
}

// MARK: - Profile Models

public struct ProfileSnapshot: Codable, Sendable, Equatable {
    public let profileName: String
    public let vibe: String
    public let createdAt: String
    public let voiceDescription: String
    public let sourceText: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case createdAt = "created_at"
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }

    init(profile: SpeakSwiftly.ProfileSummary) {
        self.profileName = profile.profileName
        self.vibe = profile.vibe.rawValue
        self.createdAt = TimestampFormatter.string(from: profile.createdAt)
        self.voiceDescription = profile.voiceDescription
        self.sourceText = profile.sourceText
    }
}

struct ProfileListResponse: ResponseEncodable, Sendable {
    let profiles: [ProfileSnapshot]
}

// MARK: - Text Profile Models

struct TextReplacementSnapshot: Codable, Sendable, Equatable {
    let id: String
    let text: String
    let replacement: String
    let match: String
    let phase: String
    let isCaseSensitive: Bool
    let formats: [String]
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case replacement
        case match
        case phase
        case isCaseSensitive = "is_case_sensitive"
        case formats
        case priority
    }

    init(replacement: TextForSpeech.Replacement) {
        self.id = replacement.id
        self.text = replacement.text
        self.replacement = replacement.replacement
        self.match = replacement.match.rawValue
        self.phase = replacement.phase.rawValue
        self.isCaseSensitive = replacement.isCaseSensitive
        self.formats = replacement.formats.map(\.rawValue).sorted()
        self.priority = replacement.priority
    }

    func model() throws -> TextForSpeech.Replacement {
        guard let match = TextForSpeech.Replacement.Match(rawValue: match) else {
            throw HTTPError(
                .badRequest,
                message: "Text replacement '\(id)' used unsupported match '\(match)'. Expected one of: exact_phrase, whole_token."
            )
        }
        guard let phase = TextForSpeech.Replacement.Phase(rawValue: phase) else {
            throw HTTPError(
                .badRequest,
                message: "Text replacement '\(id)' used unsupported phase '\(phase)'. Expected one of: before_built_ins, after_built_ins."
            )
        }

        let resolvedFormats = try Set(formats.map(resolveTextFormat(_:)))
        return TextForSpeech.Replacement(
            text,
            with: replacement,
            id: id,
            as: match,
            in: phase,
            caseSensitive: isCaseSensitive,
            for: resolvedFormats,
            priority: priority
        )
    }
}

struct TextProfileSnapshot: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let replacements: [TextReplacementSnapshot]

    init(profile: TextForSpeech.Profile) {
        self.id = profile.id
        self.name = profile.name
        self.replacements = profile.replacements.map(TextReplacementSnapshot.init(replacement:))
    }

    func model() throws -> TextForSpeech.Profile {
        try .init(
            id: id,
            name: name,
            replacements: replacements.map { try $0.model() }
        )
    }
}

struct TextProfilesSnapshot: ResponseEncodable, Sendable, Equatable {
    let persistenceURL: String?
    let baseProfile: TextProfileSnapshot
    let activeProfile: TextProfileSnapshot
    let storedProfiles: [TextProfileSnapshot]
    let effectiveProfile: TextProfileSnapshot

    enum CodingKeys: String, CodingKey {
        case persistenceURL = "persistence_url"
        case baseProfile = "base_profile"
        case activeProfile = "active_profile"
        case storedProfiles = "stored_profiles"
        case effectiveProfile = "effective_profile"
    }
}

struct TextProfileListResponse: ResponseEncodable, Sendable {
    let textProfiles: TextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }
}

struct TextProfileResponse: ResponseEncodable, Sendable {
    let profile: TextProfileSnapshot
}

struct CreateTextProfileRequestPayload: Decodable {
    let id: String
    let name: String
    let replacements: [TextReplacementSnapshot]
}

struct StoreTextProfileRequestPayload: Decodable {
    let profile: TextProfileSnapshot
}

struct UseTextProfileRequestPayload: Decodable {
    let profile: TextProfileSnapshot
}

struct TextReplacementRequestPayload: Decodable {
    let replacement: TextReplacementSnapshot
}

// MARK: - Queue Models

public struct ActiveRequestSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let op: String
    public let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }

    init(summary: SpeakSwiftly.ActiveRequest) {
        self.id = summary.id
        self.op = summary.op
        self.profileName = summary.profileName
    }

    init(id: String, op: String, profileName: String?) {
        self.id = id
        self.op = op
        self.profileName = profileName
    }
}

public struct QueuedRequestSnapshot: Codable, Sendable, Equatable {
    public let id: String
    public let op: String
    public let profileName: String?
    public let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case queuePosition = "queue_position"
    }

    init(summary: SpeakSwiftly.QueuedRequest) {
        self.id = summary.id
        self.op = summary.op
        self.profileName = summary.profileName
        self.queuePosition = summary.queuePosition
    }
}

struct QueueSnapshotResponse: ResponseEncodable, Sendable {
    let queueType: String
    let activeRequest: ActiveRequestSnapshot?
    let queue: [QueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case queue
    }
}

public struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
    public let state: String
    public let activeRequest: ActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }

    init(summary: SpeakSwiftly.PlaybackStateSnapshot) {
        self.state = summary.state.rawValue
        self.activeRequest = summary.activeRequest.map(ActiveRequestSnapshot.init(summary:))
    }
}

struct PlaybackStateResponse: ResponseEncodable, Sendable {
    let playback: PlaybackStateSnapshot
}

struct QueueClearedResponse: ResponseEncodable, Sendable {
    let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case clearedCount = "cleared_count"
    }
}

struct QueueCancellationResponse: ResponseEncodable, Sendable {
    let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case cancelledRequestID = "cancelled_request_id"
    }
}

// MARK: - Status Models

struct HealthSnapshot: ResponseEncodable, Sendable {
    let status: String
    let service: String
    let environment: String
    let serverMode: String
    let workerMode: String
    let workerStage: String
    let workerReady: Bool
    let startupError: String?

    enum CodingKeys: String, CodingKey {
        case status
        case service
        case environment
        case serverMode = "server_mode"
        case workerMode = "worker_mode"
        case workerStage = "worker_stage"
        case workerReady = "worker_ready"
        case startupError = "startup_error"
    }
}

struct ReadinessSnapshot: ResponseEncodable, Sendable {
    let status: String
    let serverMode: String
    let workerMode: String
    let workerStage: String
    let workerReady: Bool
    let startupError: String?
    let profileCacheState: String
    let profileCacheWarning: String?
    let profileCount: Int
    let lastProfileRefreshAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case serverMode = "server_mode"
        case workerMode = "worker_mode"
        case workerStage = "worker_stage"
        case workerReady = "worker_ready"
        case startupError = "startup_error"
        case profileCacheState = "profile_cache_state"
        case profileCacheWarning = "profile_cache_warning"
        case profileCount = "profile_count"
        case lastProfileRefreshAt = "last_profile_refresh_at"
    }
}

struct StatusSnapshot: ResponseEncodable, Sendable {
    let service: String
    let environment: String
    let serverMode: String
    let workerMode: String
    let workerStage: String
    let profileCacheState: String
    let profileCacheWarning: String?
    let workerFailureSummary: String?
    let cachedProfiles: [ProfileSnapshot]
    let lastProfileRefreshAt: String?
    let host: String
    let port: Int
    let generationQueue: QueueStatusSnapshot
    let playbackQueue: QueueStatusSnapshot
    let playback: PlaybackStatusSnapshot
    let currentGenerationJob: CurrentGenerationJobSnapshot?
    let transports: [TransportStatusSnapshot]
    let recentErrors: [RecentErrorSnapshot]

    enum CodingKeys: String, CodingKey {
        case service
        case environment
        case serverMode = "server_mode"
        case workerMode = "worker_mode"
        case workerStage = "worker_stage"
        case profileCacheState = "profile_cache_state"
        case profileCacheWarning = "profile_cache_warning"
        case workerFailureSummary = "worker_failure_summary"
        case cachedProfiles = "cached_profiles"
        case lastProfileRefreshAt = "last_profile_refresh_at"
        case host
        case port
        case generationQueue = "generation_queue"
        case playbackQueue = "playback_queue"
        case playback
        case currentGenerationJob = "current_generation_job"
        case transports
        case recentErrors = "recent_errors"
    }
}

// MARK: - Job Event Models

public struct ServerWorkerStatusEvent: Encodable, Sendable, Equatable {
    public let event = "worker_status"
    public let stage: String
    public let workerMode: String

    enum CodingKeys: String, CodingKey {
        case event
        case stage
        case workerMode = "worker_mode"
    }
}

public struct ServerQueuedEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = "queued"
    public let reason: String
    public let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case reason
        case queuePosition = "queue_position"
    }
}

public struct ServerStartedEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = "started"
    public let op: String
}

public struct ServerProgressEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = "progress"
    public let stage: String
}

public struct ServerSuccessEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let ok = true
    public let profileName: String?
    public let profilePath: String?
    public let profiles: [ProfileSnapshot]?
    public let activeRequest: ActiveRequestSnapshot?
    public let queue: [QueuedRequestSnapshot]?
    public let playbackState: PlaybackStateSnapshot?
    public let clearedCount: Int?
    public let cancelledRequestID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case profiles
        case activeRequest = "active_request"
        case queue
        case playbackState = "playback_state"
        case clearedCount = "cleared_count"
        case cancelledRequestID = "cancelled_request_id"
    }
}

public struct ServerFailureEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let ok = false
    public let code: String
    public let message: String
}

public enum ServerJobEvent: Sendable, Equatable, Encodable {
    case workerStatus(ServerWorkerStatusEvent)
    case queued(ServerQueuedEvent)
    case acknowledged(ServerSuccessEvent)
    case started(ServerStartedEvent)
    case progress(ServerProgressEvent)
    case completed(ServerSuccessEvent)
    case failed(ServerFailureEvent)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            true
        default:
            false
        }
    }

    public var id: String? {
        switch self {
        case .workerStatus:
            nil
        case .queued(let event):
            event.id
        case .acknowledged(let event):
            event.id
        case .started(let event):
            event.id
        case .progress(let event):
            event.id
        case .completed(let event):
            event.id
        case .failed(let event):
            event.id
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .workerStatus(let event):
            try event.encode(to: encoder)
        case .queued(let event):
            try event.encode(to: encoder)
        case .acknowledged(let event):
            try event.encode(to: encoder)
        case .started(let event):
            try event.encode(to: encoder)
        case .progress(let event):
            try event.encode(to: encoder)
        case .completed(let event):
            try event.encode(to: encoder)
        case .failed(let event):
            try event.encode(to: encoder)
        }
    }
}

public struct JobSnapshot: ResponseEncodable, Sendable {
    public let jobID: String
    public let op: String
    public let submittedAt: String
    public let startedAt: String?
    public let status: String
    public let latestEvent: ServerJobEvent?
    public let terminalEvent: ServerJobEvent?
    public let history: [ServerJobEvent]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case op
        case submittedAt = "submitted_at"
        case startedAt = "started_at"
        case status
        case latestEvent = "latest_event"
        case terminalEvent = "terminal_event"
        case history
    }
}

// MARK: - Helpers

enum TimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}

private func resolveTextFormat(_ rawValue: String) throws -> TextForSpeech.Format {
    guard let format = TextForSpeech.Format(rawValue: rawValue) else {
        let supportedFormats = TextForSpeech.Format.allCases.map(\.rawValue).joined(separator: ", ")
        throw HTTPError(
            .badRequest,
            message: "Text replacement format '\(rawValue)' is not supported. Expected one of: \(supportedFormats)."
        )
    }
    return format
}

private func resolveRequestTextFormat(_ rawValue: String) throws -> TextForSpeech.TextFormat {
    if let format = TextForSpeech.TextFormat(rawValue: rawValue) {
        return format
    }
    if let legacyFormat = TextForSpeech.Format(rawValue: rawValue),
       let textFormat = legacyRequestTextFormat(for: legacyFormat)
    {
        return textFormat
    }

    let supportedFormats = TextForSpeech.TextFormat.allCases.map(\.rawValue)
    let legacyFormats = TextForSpeech.Format.allCases.map(\.rawValue)
    throw HTTPError(
        .badRequest,
        message: "Speech request text_format '\(rawValue)' is not supported. Expected one of: \((supportedFormats + legacyFormats).joined(separator: ", "))."
    )
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

private func legacyRequestTextFormat(for format: TextForSpeech.Format) -> TextForSpeech.TextFormat? {
    switch format {
    case .plain: .plain
    case .markdown: .markdown
    case .html: .html
    case .log: .log
    case .cli: .cli
    case .list: .list
    case .source, .swift, .python, .rust: nil
    }
}
