import Foundation
import Hummingbird
import SpeakSwiftly

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
