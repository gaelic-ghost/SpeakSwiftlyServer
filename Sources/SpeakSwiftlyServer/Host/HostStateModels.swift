import Foundation

// MARK: - Host State Models

public struct HostOverviewSnapshot: Codable, Sendable, Equatable {
    public let service: String
    public let environment: String
    public let serverMode: String
    public let workerMode: String
    public let workerStage: String
    public let workerReady: Bool
    public let startupError: String?
    public let profileCacheState: String
    public let profileCacheWarning: String?
    public let profileCount: Int
    public let lastProfileRefreshAt: String?

    enum CodingKeys: String, CodingKey {
        case service
        case environment
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

public struct QueueStatusSnapshot: Codable, Sendable, Equatable {
    public let queueType: String
    public let activeCount: Int
    public let queuedCount: Int
    public let activeRequest: ActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeCount = "active_count"
        case queuedCount = "queued_count"
        case activeRequest = "active_request"
    }
}

public struct PlaybackStatusSnapshot: Codable, Sendable, Equatable {
    public let state: String
    public let activeRequest: ActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

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

public struct HostStateSnapshot: Codable, Sendable, Equatable {
    public let overview: HostOverviewSnapshot
    public let generationQueue: QueueStatusSnapshot
    public let playbackQueue: QueueStatusSnapshot
    public let playback: PlaybackStatusSnapshot
    public let currentGenerationJob: CurrentGenerationJobSnapshot?
    public let transports: [TransportStatusSnapshot]
    public let recentErrors: [RecentErrorSnapshot]
}
