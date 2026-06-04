import Foundation
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
        op = canonicalOperationName(summary.kind.rawValue)
        profileName = summary.voiceProfile
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
        op = canonicalOperationName(summary.kind.rawValue)
        profileName = summary.voiceProfile
        queuePosition = summary.queuePosition
    }

    init(id: String, op: String, profileName: String?, queuePosition: Int) {
        self.id = id
        self.op = op
        self.profileName = profileName
        self.queuePosition = queuePosition
    }
}

package struct QueueSnapshotResponse: Encodable {
    package let queueType: String
    package let activeRequest: ActiveRequestSnapshot?
    package let activeRequests: [ActiveRequestSnapshot]
    package let queue: [QueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queue
    }

    init(snapshot: QueueStatusSnapshot) {
        queueType = snapshot.queueType
        activeRequest = snapshot.activeRequest
        activeRequests = snapshot.activeRequests
        queue = snapshot.queuedRequests
    }
}

package extension QueueStatusSnapshot {
    static func empty(queueType: String) -> QueueStatusSnapshot {
        .init(
            queueType: queueType,
            activeCount: 0,
            queuedCount: 0,
            activeRequest: nil,
            activeRequests: [],
            queuedRequests: [],
        )
    }
}

package struct PlaybackStateResponse: Encodable {
    package let playback: PlaybackStatusSnapshot
}

package struct QueueClearedResponse: Encodable {
    package let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case clearedCount = "cleared_count"
    }
}

package struct QueueCancellationResponse: Encodable {
    package let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case cancelledRequestID = "cancelled_request_id"
    }
}

package enum RequestCancellationScope: String, CaseIterable, Decodable {
    case generation
    case playback

    package var queueType: SpeakSwiftly.QueueType {
        switch self {
            case .generation:
                .generation
            case .playback:
                .playback
        }
    }

    package static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    package static var supportedValuesDescription: String {
        allCases.map(\.rawValue).joined(separator: ", ")
    }
}

package struct HealthSnapshot: Encodable {
    package let status: String
    package let service: String
    package let environment: String
    package let serverMode: String
    package let workerMode: String
    package let workerStage: String
    package let workerReady: Bool
    package let startupError: String?

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

package struct ReadinessSnapshot: Encodable {
    package let status: String
    package let serverMode: String
    package let workerMode: String
    package let workerStage: String
    package let workerReady: Bool
    package let startupError: String?
    package let profileCacheState: String
    package let profileCacheWarning: String?
    package let profileCount: Int
    package let lastProfileRefreshAt: String?

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

package struct StatusSnapshot: Encodable {
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
        case runtimeBackendTransition = "runtime_backend_transition"
        case currentGenerationJobs = "current_generation_jobs"
        case runtimeConfiguration = "runtime_configuration"
        case remoteGeneration = "remote_generation"
        case transports
        case networkAudioDestinations = "network_audio_destinations"
        case networkAudioReceiverSelection = "network_audio_receiver_selection"
        case recentErrors = "recent_errors"
    }

    package let service: String
    package let environment: String
    package let defaultVoiceProfileName: String?
    package let serverMode: String
    package let workerMode: String
    package let workerStage: String
    package let profileCacheState: String
    package let profileCacheWarning: String?
    package let workerFailureSummary: String?
    package let cachedProfiles: [ProfileSnapshot]
    package let lastProfileRefreshAt: String?
    package let host: String
    package let port: Int
    package let runtimeRefresh: RuntimeRefreshSnapshot?
    package let generationQueue: QueueStatusSnapshot
    package let playbackQueue: QueueStatusSnapshot
    package let playback: PlaybackStatusSnapshot
    package let runtimeBackendTransition: RuntimeBackendTransitionSnapshot
    package let currentGenerationJobs: [CurrentGenerationJobSnapshot]
    package let runtimeConfiguration: RuntimeConfigurationSnapshot
    package let remoteGeneration: RemoteGenerationStatusSnapshot
    package let transports: [TransportStatusSnapshot]
    package let networkAudioDestinations: [NetworkAudioDestinationSnapshot]
    package let networkAudioReceiverSelection: NetworkAudioReceiverSelectionSnapshot
    package let recentErrors: [RecentErrorSnapshot]
}
