import Foundation
import Hummingbird
import SpeakSwiftlyCore

// MARK: - API Models

struct SpeakRequestPayload: Decodable {
    let text: String
    let profileName: String

    enum CodingKeys: String, CodingKey {
        case text
        case profileName = "profile_name"
    }
}

struct CreateProfileRequestPayload: Decodable {
    let profileName: String
    let text: String
    let voiceDescription: String
    let outputPath: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case text
        case voiceDescription = "voice_description"
        case outputPath = "output_path"
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

struct ProfileSnapshot: Codable, Sendable, Equatable {
    let profileName: String
    let createdAt: String
    let voiceDescription: String
    let sourceText: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case createdAt = "created_at"
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }

    init(profile: ProfileSummary) {
        self.profileName = profile.profileName
        self.createdAt = TimestampFormatter.string(from: profile.createdAt)
        self.voiceDescription = profile.voiceDescription
        self.sourceText = profile.sourceText
    }
}

struct ProfileListResponse: ResponseEncodable, Sendable {
    let profiles: [ProfileSnapshot]
}

struct ActiveRequestSnapshot: Codable, Sendable, Equatable {
    let id: String
    let op: String
    let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }

    init(summary: ActiveWorkerRequestSummary) {
        self.id = summary.id
        self.op = summary.op
        self.profileName = summary.profileName
    }
}

struct QueuedRequestSnapshot: Codable, Sendable, Equatable {
    let id: String
    let op: String
    let profileName: String?
    let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case queuePosition = "queue_position"
    }

    init(summary: QueuedWorkerRequestSummary) {
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

struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
    let state: String
    let activeRequest: ActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }

    init(summary: PlaybackStateSummary) {
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
    }
}

struct ServerWorkerStatusEvent: Encodable, Sendable, Equatable {
    let event = "worker_status"
    let stage: String
    let workerMode: String

    enum CodingKeys: String, CodingKey {
        case event
        case stage
        case workerMode = "worker_mode"
    }
}

struct ServerQueuedEvent: Encodable, Sendable, Equatable {
    let id: String
    let event = "queued"
    let reason: String
    let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case reason
        case queuePosition = "queue_position"
    }
}

struct ServerStartedEvent: Encodable, Sendable, Equatable {
    let id: String
    let event = "started"
    let op: String
}

struct ServerProgressEvent: Encodable, Sendable, Equatable {
    let id: String
    let event = "progress"
    let stage: String
}

struct ServerSuccessEvent: Encodable, Sendable, Equatable {
    let id: String
    let ok = true
    let profileName: String?
    let profilePath: String?
    let profiles: [ProfileSnapshot]?
    let activeRequest: ActiveRequestSnapshot?
    let queue: [QueuedRequestSnapshot]?
    let playbackState: PlaybackStateSnapshot?
    let clearedCount: Int?
    let cancelledRequestID: String?

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

struct ServerFailureEvent: Encodable, Sendable, Equatable {
    let id: String
    let ok = false
    let code: String
    let message: String
}

enum ServerJobEvent: Sendable, Equatable, Encodable {
    case workerStatus(ServerWorkerStatusEvent)
    case queued(ServerQueuedEvent)
    case acknowledged(ServerSuccessEvent)
    case started(ServerStartedEvent)
    case progress(ServerProgressEvent)
    case completed(ServerSuccessEvent)
    case failed(ServerFailureEvent)

    var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            true
        default:
            false
        }
    }

    var id: String? {
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

    func encode(to encoder: Encoder) throws {
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

struct JobSnapshot: ResponseEncodable, Sendable {
    let jobID: String
    let op: String
    let submittedAt: String
    let status: String
    let latestEvent: ServerJobEvent?
    let terminalEvent: ServerJobEvent?
    let history: [ServerJobEvent]

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case op
        case submittedAt = "submitted_at"
        case status
        case latestEvent = "latest_event"
        case terminalEvent = "terminal_event"
        case history
    }
}

enum TimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }
}
