import Foundation
import Hummingbird
import SpeakSwiftly

/// High-level readiness and profile-cache status for the shared host.
public struct HostOverviewSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case service
        case environment
        case defaultVoiceProfileName = "default_voice_profile_name"
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

    public let service: String
    public let environment: String
    public let defaultVoiceProfileName: String?
    public let serverMode: String
    public let workerMode: String
    public let workerStage: String
    public let workerReady: Bool
    public let startupError: String?
    public let profileCacheState: String
    public let profileCacheWarning: String?
    public let profileCount: Int
    public let lastProfileRefreshAt: String?

    func replacing(defaultVoiceProfileName: String?) -> Self {
        .init(
            service: service,
            environment: environment,
            defaultVoiceProfileName: defaultVoiceProfileName,
            serverMode: serverMode,
            workerMode: workerMode,
            workerStage: workerStage,
            workerReady: workerReady,
            startupError: startupError,
            profileCacheState: profileCacheState,
            profileCacheWarning: profileCacheWarning,
            profileCount: profileCount,
            lastProfileRefreshAt: lastProfileRefreshAt,
        )
    }
}

/// Active and queued work for one host queue.
public struct QueueStatusSnapshot: Codable, Sendable, Equatable {
    public let queueType: String
    public let activeCount: Int
    public let queuedCount: Int
    public let activeRequest: ActiveRequestSnapshot?
    public let activeRequests: [ActiveRequestSnapshot]
    public let queuedRequests: [QueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeCount = "active_count"
        case queuedCount = "queued_count"
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queuedRequests = "queued_requests"
    }
}

/// App-facing playback state reported by the shared runtime.
public struct PlaybackStatusSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
        case isStableForConcurrentGeneration = "is_stable_for_concurrent_generation"
        case isRebuffering = "is_rebuffering"
        case stableBufferedAudioMS = "stable_buffered_audio_ms"
        case stableBufferTargetMS = "stable_buffer_target_ms"
    }

    public let state: String
    public let activeRequest: ActiveRequestSnapshot?
    public let isStableForConcurrentGeneration: Bool
    public let isRebuffering: Bool
    public let stableBufferedAudioMS: Int?
    public let stableBufferTargetMS: Int?

    init(
        state: String,
        activeRequest: ActiveRequestSnapshot?,
        isStableForConcurrentGeneration: Bool,
        isRebuffering: Bool,
        stableBufferedAudioMS: Int?,
        stableBufferTargetMS: Int?,
    ) {
        self.state = state
        self.activeRequest = activeRequest
        self.isStableForConcurrentGeneration = isStableForConcurrentGeneration
        self.isRebuffering = isRebuffering
        self.stableBufferedAudioMS = stableBufferedAudioMS
        self.stableBufferTargetMS = stableBufferTargetMS
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

/// Timing markers for one completed refresh cycle of the host state snapshots.
public struct RuntimeRefreshSnapshot: Codable, Sendable, Equatable {
    public let sequenceID: Int
    public let source: String
    public let startedAt: String
    public let generationQueueRefreshedAt: String
    public let playbackQueueRefreshedAt: String
    public let playbackStateRefreshedAt: String
    public let completedAt: String

    enum CodingKeys: String, CodingKey {
        case sequenceID = "sequence_id"
        case source
        case startedAt = "started_at"
        case generationQueueRefreshedAt = "generation_queue_refreshed_at"
        case playbackQueueRefreshedAt = "playback_queue_refreshed_at"
        case playbackStateRefreshedAt = "playback_state_refreshed_at"
        case completedAt = "completed_at"
    }
}

/// Summary of one generation job that is currently active in the runtime.
public struct CurrentGenerationJobSnapshot: Codable, Sendable, Equatable {
    public let jobID: String
    public let op: String
    public let profileName: String?
    public let submittedAt: String
    public let startedAt: String?
    public let latestStage: String?
    public let elapsedGenerationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case op
        case profileName = "profile_name"
        case submittedAt = "submitted_at"
        case startedAt = "started_at"
        case latestStage = "latest_stage"
        case elapsedGenerationSeconds = "elapsed_generation_seconds"
    }
}

/// Status for one published operator transport such as HTTP or MCP.
public struct TransportStatusSnapshot: Codable, Sendable, Equatable {
    public let name: String
    public let enabled: Bool
    public let state: String
    public let host: String?
    public let port: Int?
    public let path: String?
    public let advertisedAddress: String?

    enum CodingKeys: String, CodingKey {
        case name
        case enabled
        case state
        case host
        case port
        case path
        case advertisedAddress = "advertised_address"
    }
}

/// One retained host or transport error suitable for operator display.
public struct RecentErrorSnapshot: Codable, Sendable, Equatable {
    public let occurredAt: String
    public let source: String
    public let code: String
    public let message: String

    enum CodingKeys: String, CodingKey {
        case occurredAt = "occurred_at"
        case source
        case code
        case message
    }
}

/// The active and next-start runtime configuration state exposed by the host.
public struct RuntimeConfigurationSnapshot: Codable, ResponseEncodable, Sendable, Equatable {
    public let activeRuntimeSpeechBackend: String
    public let nextRuntimeSpeechBackend: String
    public let activeDefaultVoiceProfileName: String?
    public let nextDefaultVoiceProfileName: String?
    public let environmentSpeechBackendOverride: String?
    public let persistedSpeechBackend: String?
    public let persistedDefaultVoiceProfileName: String?
    public let profileRootPath: String
    public let persistedConfigurationPath: String
    public let persistedConfigurationExists: Bool
    public let persistedConfigurationState: String
    public let persistedConfigurationError: String?
    public let persistedConfigurationAppliesOnRestart: Bool
    public let activeRuntimeMatchesNextRuntime: Bool
    public let persistedConfigurationWillAffectNextRuntimeStart: Bool

    enum CodingKeys: String, CodingKey {
        case activeRuntimeSpeechBackend = "active_runtime_speech_backend"
        case nextRuntimeSpeechBackend = "next_runtime_speech_backend"
        case activeDefaultVoiceProfileName = "active_default_voice_profile_name"
        case nextDefaultVoiceProfileName = "next_default_voice_profile_name"
        case environmentSpeechBackendOverride = "environment_speech_backend_override"
        case persistedSpeechBackend = "persisted_speech_backend"
        case persistedDefaultVoiceProfileName = "persisted_default_voice_profile_name"
        case profileRootPath = "profile_root_path"
        case persistedConfigurationPath = "persisted_configuration_path"
        case persistedConfigurationExists = "persisted_configuration_exists"
        case persistedConfigurationState = "persisted_configuration_state"
        case persistedConfigurationError = "persisted_configuration_error"
        case persistedConfigurationAppliesOnRestart = "persisted_configuration_applies_on_restart"
        case activeRuntimeMatchesNextRuntime = "active_runtime_matches_next_runtime"
        case persistedConfigurationWillAffectNextRuntimeStart = "persisted_configuration_will_affect_next_runtime_start"
    }
}

/// Aggregate snapshot of the host state that bundles overview, queues, runtime, transport, and error data.
public struct HostStateSnapshot: Codable, Sendable, Equatable {
    public let overview: HostOverviewSnapshot
    public let runtimeRefresh: RuntimeRefreshSnapshot?
    public let generationQueue: QueueStatusSnapshot
    public let playbackQueue: QueueStatusSnapshot
    public let playback: PlaybackStatusSnapshot
    public let currentGenerationJobs: [CurrentGenerationJobSnapshot]
    public let runtimeConfiguration: RuntimeConfigurationSnapshot
    public let transports: [TransportStatusSnapshot]
    public let recentErrors: [RecentErrorSnapshot]

    enum CodingKeys: String, CodingKey {
        case overview
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
