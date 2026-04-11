import Foundation
import Hummingbird
import SpeakSwiftlyCore

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
        self.op = canonicalOperationName(summary.op)
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
        self.op = canonicalOperationName(summary.op)
        self.profileName = summary.profileName
        self.queuePosition = summary.queuePosition
    }

    init(id: String, op: String, profileName: String?, queuePosition: Int) {
        self.id = id
        self.op = op
        self.profileName = profileName
        self.queuePosition = queuePosition
    }
}

struct QueueSnapshotResponse: ResponseEncodable, Sendable {
    let queueType: String
    let activeRequest: ActiveRequestSnapshot?
    let activeRequests: [ActiveRequestSnapshot]
    let queue: [QueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queue
    }
}

public struct PlaybackStateSnapshot: Codable, Sendable, Equatable {
    public let state: String
    public let activeRequest: ActiveRequestSnapshot?
    public let isStableForConcurrentGeneration: Bool
    public let isRebuffering: Bool
    public let stableBufferedAudioMS: Int?
    public let stableBufferTargetMS: Int?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
        case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
        case isRebuffering = "is_rebuffering"
        case stableBufferedAudioMS = "stable_buffered_audio_ms"
        case stableBufferTargetMS = "stable_buffer_target_ms"
    }

    init(summary: SpeakSwiftly.PlaybackStateSnapshot) {
        self.state = summary.state.rawValue
        self.activeRequest = summary.activeRequest.map(ActiveRequestSnapshot.init(summary:))
        self.isStableForConcurrentGeneration = summary.isStableForConcurrentGeneration
        self.isRebuffering = summary.isRebuffering
        self.stableBufferedAudioMS = summary.stableBufferedAudioMS
        self.stableBufferTargetMS = summary.stableBufferTargetMS
    }
}

struct PlaybackStateResponse: ResponseEncodable, Sendable {
    let playback: PlaybackStateSnapshot
}

extension PlaybackStateSnapshot {
    init(status: PlaybackStatusSnapshot) {
        self.state = status.state
        self.activeRequest = status.activeRequest
        self.isStableForConcurrentGeneration = status.isStableForConcurrentGeneration
        self.isRebuffering = status.isRebuffering
        self.stableBufferedAudioMS = status.stableBufferedAudioMS
        self.stableBufferTargetMS = status.stableBufferTargetMS
    }
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
    let defaultVoiceProfileName: String?
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
    let runtimeRefresh: RuntimeRefreshSnapshot?
    let generationQueue: QueueStatusSnapshot
    let playbackQueue: QueueStatusSnapshot
    let playback: PlaybackStatusSnapshot
    let currentGenerationJobs: [CurrentGenerationJobSnapshot]
    let runtimeConfiguration: RuntimeConfigurationSnapshot
    let transports: [TransportStatusSnapshot]
    let recentErrors: [RecentErrorSnapshot]

    enum CodingKeys: String, CodingKey {
        case service
        case environment
        case defaultVoiceProfileName = "default_voice_profile_name"
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
        case runtimeRefresh = "runtime_refresh"
        case generationQueue = "generation_queue"
        case playbackQueue = "playback_queue"
        case playback
        case currentGenerationJobs = "current_generation_jobs"
        case runtimeConfiguration = "runtime_configuration"
        case transports
        case recentErrors = "recent_errors"
    }
}
