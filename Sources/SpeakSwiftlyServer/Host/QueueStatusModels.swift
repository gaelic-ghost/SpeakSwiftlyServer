import Foundation
import Hummingbird
import SpeakSwiftly

/// The active request currently running in a host queue.
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
        id = summary.id
        op = canonicalOperationName(summary.op)
        profileName = summary.profileName
    }

    init(id: String, op: String, profileName: String?) {
        self.id = id
        self.op = op
        self.profileName = profileName
    }
}

/// A queued request waiting for work in a host queue.
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
        id = summary.id
        op = canonicalOperationName(summary.op)
        profileName = summary.profileName
        queuePosition = summary.queuePosition
    }

    init(id: String, op: String, profileName: String?, queuePosition: Int) {
        self.id = id
        self.op = op
        self.profileName = profileName
        self.queuePosition = queuePosition
    }
}

struct QueueSnapshotResponse: ResponseEncodable {
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

/// Transport-facing playback state snapshot used by HTTP and MCP control surfaces.
struct PlaybackStateSnapshot: Codable, Equatable {
    let state: String
    let activeRequest: ActiveRequestSnapshot?
    let isStableForConcurrentGeneration: Bool
    let isRebuffering: Bool
    let stableBufferedAudioMS: Int?
    let stableBufferTargetMS: Int?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
        case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
        case isRebuffering = "is_rebuffering"
        case stableBufferedAudioMS = "stable_buffered_audio_ms"
        case stableBufferTargetMS = "stable_buffer_target_ms"
    }

    init(summary: SpeakSwiftly.PlaybackStateSnapshot) {
        state = summary.state.rawValue
        activeRequest = summary.activeRequest.map(ActiveRequestSnapshot.init(summary:))
        isStableForConcurrentGeneration = summary.isStableForConcurrentGeneration
        isRebuffering = summary.isRebuffering
        stableBufferedAudioMS = summary.stableBufferedAudioMS
        stableBufferTargetMS = summary.stableBufferTargetMS
    }
}

struct PlaybackStateResponse: ResponseEncodable {
    let playback: PlaybackStateSnapshot
}

extension PlaybackStateSnapshot {
    init(status: PlaybackStatusSnapshot) {
        state = status.state
        activeRequest = status.activeRequest
        isStableForConcurrentGeneration = status.isStableForConcurrentGeneration
        isRebuffering = status.isRebuffering
        stableBufferedAudioMS = status.stableBufferedAudioMS
        stableBufferTargetMS = status.stableBufferTargetMS
    }
}

struct QueueClearedResponse: ResponseEncodable {
    let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case clearedCount = "cleared_count"
    }
}

struct QueueCancellationResponse: ResponseEncodable {
    let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case cancelledRequestID = "cancelled_request_id"
    }
}

struct HealthSnapshot: ResponseEncodable {
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

struct ReadinessSnapshot: ResponseEncodable {
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

struct StatusSnapshot: ResponseEncodable {
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
}
