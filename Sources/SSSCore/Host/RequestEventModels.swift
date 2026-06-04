import Foundation
import SpeakSwiftly

/// Worker readiness or mode change emitted on the shared job event stream.
package struct ServerWorkerStatusEvent: Encodable, Equatable {
    package let event = "worker_status"
    package let stage: String
    package let workerMode: String

    enum CodingKeys: String, CodingKey {
        case event
        case stage
        case workerMode = "worker_mode"
    }
}

/// Queue-placement event emitted when a request cannot start immediately.
package struct ServerQueuedEvent: Encodable, Equatable {
    package let id: String
    package let event = "queued"
    package let reason: String
    package let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case reason
        case queuePosition = "queue_position"
    }
}

/// Start event emitted when a queued request begins execution.
package struct ServerStartedEvent: Encodable, Equatable {
    package let id: String
    package let event = "started"
    package let op: String
}

/// Progress event emitted while a request advances through runtime stages.
package struct ServerProgressEvent: Encodable, Equatable {
    package let id: String
    package let event = "progress"
    package let stage: String
    package let playbackEvent: PlaybackEventSnapshot?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case stage
        case playbackEvent = "playback_event"
    }

    init(id: String, stage: String, playbackEvent: PlaybackEventSnapshot? = nil) {
        self.id = id
        self.stage = stage
        self.playbackEvent = playbackEvent
    }
}

/// Success-shaped event payload used for acknowledgements and completions.
package struct ServerSuccessEvent: Encodable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case ok
        case artifact
        case artifacts
        case generationJob = "generation_job"
        case generationJobs = "generation_jobs"
        case recentGeneratedAudio = "recent_generated_audio"
        case recentGeneratedAudioChunks = "recent_generated_audio_chunks"
        case replayRequestIDs = "replay_request_ids"
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
        case runtime
        case speechBackend = "speech_backend"
        case clearedCount = "cleared_count"
        case cancelledRequestID = "cancelled_request_id"
    }

    package let id: String
    package let ok = true
    package let artifact: SpeakSwiftly.GenerationArtifact?
    package let artifacts: [SpeakSwiftly.GenerationArtifact]?
    package let generationJob: SpeakSwiftly.GenerationJob?
    package let generationJobs: [SpeakSwiftly.GenerationJob]?
    package let recentGeneratedAudio: SpeakSwiftly.RecentGeneratedAudioSnapshot?
    package let recentGeneratedAudioChunks: [SpeakSwiftly.GeneratedAudioChunk]?
    package let replayRequestIDs: [String]?
    package let profileName: String?
    package let profilePath: String?
    package let profiles: [ProfileSnapshot]?
    package let textProfile: TextProfileSnapshot?
    package let textProfiles: [TextProfileSnapshot]?
    package let textProfilePath: String?
    package let activeRequest: ActiveRequestSnapshot?
    package let activeRequests: [ActiveRequestSnapshot]?
    package let queue: [QueuedRequestSnapshot]?
    package let playbackState: PlaybackStatusSnapshot?
    package let runtime: SpeakSwiftly.RuntimeSnapshot?
    package let speechBackend: String?
    package let clearedCount: Int?
    package let cancelledRequestID: String?

    init(
        id: String,
        artifact: SpeakSwiftly.GenerationArtifact? = nil,
        artifacts: [SpeakSwiftly.GenerationArtifact]? = nil,
        generationJob: SpeakSwiftly.GenerationJob? = nil,
        generationJobs: [SpeakSwiftly.GenerationJob]? = nil,
        recentGeneratedAudio: SpeakSwiftly.RecentGeneratedAudioSnapshot? = nil,
        recentGeneratedAudioChunks: [SpeakSwiftly.GeneratedAudioChunk]? = nil,
        replayRequestIDs: [String]? = nil,
        profileName: String? = nil,
        profilePath: String? = nil,
        profiles: [ProfileSnapshot]? = nil,
        textProfile: TextProfileSnapshot? = nil,
        textProfiles: [TextProfileSnapshot]? = nil,
        textProfilePath: String? = nil,
        activeRequest: ActiveRequestSnapshot? = nil,
        activeRequests: [ActiveRequestSnapshot]? = nil,
        queue: [QueuedRequestSnapshot]? = nil,
        playbackState: PlaybackStatusSnapshot? = nil,
        runtime: SpeakSwiftly.RuntimeSnapshot? = nil,
        speechBackend: String? = nil,
        clearedCount: Int? = nil,
        cancelledRequestID: String? = nil,
    ) {
        self.id = id
        self.artifact = artifact
        self.artifacts = artifacts
        self.generationJob = generationJob
        self.generationJobs = generationJobs
        self.recentGeneratedAudio = recentGeneratedAudio
        self.recentGeneratedAudioChunks = recentGeneratedAudioChunks
        self.replayRequestIDs = replayRequestIDs
        self.profileName = profileName
        self.profilePath = profilePath
        self.profiles = profiles
        self.textProfile = textProfile
        self.textProfiles = textProfiles
        self.textProfilePath = textProfilePath
        self.activeRequest = activeRequest
        self.activeRequests = activeRequests
        self.queue = queue
        self.playbackState = playbackState
        self.runtime = runtime
        self.speechBackend = speechBackend
        self.clearedCount = clearedCount
        self.cancelledRequestID = cancelledRequestID
    }
}

/// Failure-shaped event payload emitted when a request cannot complete successfully.
package struct ServerFailureEvent: Encodable, Equatable {
    package let id: String
    package let ok = false
    package let code: String
    package let message: String
}

/// Union event type for one job's lifecycle on the shared event stream.
package enum ServerJobEvent: Equatable, Encodable {
    case workerStatus(ServerWorkerStatusEvent)
    case queued(ServerQueuedEvent)
    case acknowledged(ServerSuccessEvent)
    case started(ServerStartedEvent)
    case progress(ServerProgressEvent)
    case completed(ServerSuccessEvent)
    case failed(ServerFailureEvent)

    /// Indicates whether the event ends the request lifecycle.
    package var isTerminal: Bool {
        switch self {
            case .completed, .failed:
                true
            default:
                false
        }
    }

    /// Returns the request identifier carried by the event, when the event is request-specific.
    package var id: String? {
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

    package func encode(to encoder: Encoder) throws {
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
package struct JobSnapshot: Encodable {
    package let requestID: String
    package let op: String
    package let submittedAt: String
    package let startedAt: String?
    package let status: String
    package let latestEvent: ServerJobEvent?
    package let terminalEvent: ServerJobEvent?
    package let history: [ServerJobEvent]

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
