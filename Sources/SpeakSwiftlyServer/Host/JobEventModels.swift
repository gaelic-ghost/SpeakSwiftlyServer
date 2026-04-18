import Foundation
import Hummingbird
import SpeakSwiftly

/// Worker readiness or mode change emitted on the shared job event stream.
struct ServerWorkerStatusEvent: Encodable, Equatable {
    let event = "worker_status"
    let stage: String
    let workerMode: String

    enum CodingKeys: String, CodingKey {
        case event
        case stage
        case workerMode = "worker_mode"
    }
}

/// Queue-placement event emitted when a request cannot start immediately.
struct ServerQueuedEvent: Encodable, Equatable {
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

/// Start event emitted when a queued request begins execution.
struct ServerStartedEvent: Encodable, Equatable {
    let id: String
    let event = "started"
    let op: String
}

/// Progress event emitted while a request advances through runtime stages.
struct ServerProgressEvent: Encodable, Equatable {
    let id: String
    let event = "progress"
    let stage: String
}

/// Success-shaped event payload used for acknowledgements and completions.
struct ServerSuccessEvent: Encodable, Equatable {
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

    let id: String
    let ok = true
    let generatedFile: SpeakSwiftly.GeneratedFile?
    let generatedFiles: [SpeakSwiftly.GeneratedFile]?
    let generatedBatch: SpeakSwiftly.GeneratedBatch?
    let generatedBatches: [SpeakSwiftly.GeneratedBatch]?
    let generationJob: SpeakSwiftly.GenerationJob?
    let generationJobs: [SpeakSwiftly.GenerationJob]?
    let profileName: String?
    let profilePath: String?
    let profiles: [ProfileSnapshot]?
    let textProfile: TextProfileSnapshot?
    let textProfiles: [TextProfileSnapshot]?
    let textProfilePath: String?
    let activeRequest: ActiveRequestSnapshot?
    let activeRequests: [ActiveRequestSnapshot]?
    let queue: [QueuedRequestSnapshot]?
    let playbackState: PlaybackStateSnapshot?
    let status: SpeakSwiftly.StatusEvent?
    let speechBackend: String?
    let clearedCount: Int?
    let cancelledRequestID: String?
}

/// Failure-shaped event payload emitted when a request cannot complete successfully.
struct ServerFailureEvent: Encodable, Equatable {
    let id: String
    let ok = false
    let code: String
    let message: String
}

/// Union event type for one job's lifecycle on the shared event stream.
enum ServerJobEvent: Equatable, Encodable {
    case workerStatus(ServerWorkerStatusEvent)
    case queued(ServerQueuedEvent)
    case acknowledged(ServerSuccessEvent)
    case started(ServerStartedEvent)
    case progress(ServerProgressEvent)
    case completed(ServerSuccessEvent)
    case failed(ServerFailureEvent)

    /// Indicates whether the event ends the request lifecycle.
    var isTerminal: Bool {
        switch self {
            case .completed, .failed:
                true
            default:
                false
        }
    }

    /// Returns the request identifier carried by the event, when the event is request-specific.
    var id: String? {
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

    func encode(to encoder: Encoder) throws {
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

/// Snapshot of one retained request lifecycle, including latest and terminal events.
struct JobSnapshot: ResponseEncodable {
    let requestID: String
    let op: String
    let submittedAt: String
    let startedAt: String?
    let status: String
    let latestEvent: ServerJobEvent?
    let terminalEvent: ServerJobEvent?
    let history: [ServerJobEvent]

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
