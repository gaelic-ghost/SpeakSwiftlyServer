import Foundation
import Hummingbird
import SpeakSwiftly

// MARK: - ServerWorkerStatusEvent

/// Worker readiness or mode change emitted on the shared job event stream.
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

// MARK: - ServerQueuedEvent

/// Queue-placement event emitted when a request cannot start immediately.
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

// MARK: - ServerStartedEvent

/// Start event emitted when a queued request begins execution.
public struct ServerStartedEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = "started"
    public let op: String
}

// MARK: - ServerProgressEvent

/// Progress event emitted while a request advances through runtime stages.
public struct ServerProgressEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let event = "progress"
    public let stage: String
}

// MARK: - ServerSuccessEvent

/// Success-shaped event payload used for acknowledgements and completions.
public struct ServerSuccessEvent: Encodable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case generatedFile = "generated_file"
        case generatedFiles = "generated_files"
        case generatedBatch = "generated_batch"
        case generatedBatches = "generated_batches"
        case generationJob = "generation_job"
        case generationJobs = "generation_jobs"
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case profiles
        case textProfile = "text_profile"
        case textProfiles = "text_profiles"
        case textProfilePath = "text_profile_path"
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queue
        case playbackState = "playback_state"
        case status
        case speechBackend = "speech_backend"
        case clearedCount = "cleared_count"
        case cancelledRequestID = "cancelled_request_id"
    }

    public let id: String
    public let ok = true
    public let generatedFile: SpeakSwiftly.GeneratedFile?
    public let generatedFiles: [SpeakSwiftly.GeneratedFile]?
    public let generatedBatch: SpeakSwiftly.GeneratedBatch?
    public let generatedBatches: [SpeakSwiftly.GeneratedBatch]?
    public let generationJob: SpeakSwiftly.GenerationJob?
    public let generationJobs: [SpeakSwiftly.GenerationJob]?
    public let profileName: String?
    public let profilePath: String?
    public let profiles: [ProfileSnapshot]?
    public let textProfile: TextProfileSnapshot?
    public let textProfiles: [TextProfileSnapshot]?
    public let textProfilePath: String?
    public let activeRequest: ActiveRequestSnapshot?
    public let activeRequests: [ActiveRequestSnapshot]?
    public let queue: [QueuedRequestSnapshot]?
    public let playbackState: PlaybackStateSnapshot?
    public let status: SpeakSwiftly.StatusEvent?
    public let speechBackend: String?
    public let clearedCount: Int?
    public let cancelledRequestID: String?
}

// MARK: - ServerFailureEvent

/// Failure-shaped event payload emitted when a request cannot complete successfully.
public struct ServerFailureEvent: Encodable, Sendable, Equatable {
    public let id: String
    public let ok = false
    public let code: String
    public let message: String
}

// MARK: - ServerJobEvent

/// Union event type for one job's lifecycle on the shared event stream.
public enum ServerJobEvent: Sendable, Equatable, Encodable {
    case workerStatus(ServerWorkerStatusEvent)
    case queued(ServerQueuedEvent)
    case acknowledged(ServerSuccessEvent)
    case started(ServerStartedEvent)
    case progress(ServerProgressEvent)
    case completed(ServerSuccessEvent)
    case failed(ServerFailureEvent)

    /// Indicates whether the event ends the request lifecycle.
    public var isTerminal: Bool {
        switch self {
            case .completed, .failed:
                true
            default:
                false
        }
    }

    /// Returns the request identifier carried by the event, when the event is request-specific.
    public var id: String? {
        switch self {
            case .workerStatus:
                nil
            case let .queued(event):
                event.id
            case let .acknowledged(event):
                event.id
            case let .started(event):
                event.id
            case let .progress(event):
                event.id
            case let .completed(event):
                event.id
            case let .failed(event):
                event.id
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
            case let .workerStatus(event):
                try event.encode(to: encoder)
            case let .queued(event):
                try event.encode(to: encoder)
            case let .acknowledged(event):
                try event.encode(to: encoder)
            case let .started(event):
                try event.encode(to: encoder)
            case let .progress(event):
                try event.encode(to: encoder)
            case let .completed(event):
                try event.encode(to: encoder)
            case let .failed(event):
                try event.encode(to: encoder)
        }
    }
}

// MARK: - JobSnapshot

/// Snapshot of one retained request lifecycle, including latest and terminal events.
public struct JobSnapshot: ResponseEncodable, Sendable {
    public let requestID: String
    public let op: String
    public let submittedAt: String
    public let startedAt: String?
    public let status: String
    public let latestEvent: ServerJobEvent?
    public let terminalEvent: ServerJobEvent?
    public let history: [ServerJobEvent]

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case op = "operation"
        case submittedAt = "submitted_at"
        case startedAt = "started_at"
        case status
        case latestEvent = "latest_event"
        case terminalEvent = "terminal_event"
        case history
    }
}
