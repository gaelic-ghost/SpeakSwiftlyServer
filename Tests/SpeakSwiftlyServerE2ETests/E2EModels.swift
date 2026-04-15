import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - E2EReadinessSnapshot

struct E2EReadinessSnapshot: Decodable {
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case workerReady = "worker_ready"
    }
}

// MARK: - E2EJobCreatedResponse

struct E2EJobCreatedResponse: Decodable {
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
    }

    var jobID: String { requestID }
}

// MARK: - E2EProfileListResponse

struct E2EProfileListResponse: Decodable {
    let profiles: [E2EProfileSnapshot]
}

// MARK: - E2EProfileSnapshot

struct E2EProfileSnapshot: Decodable {
    let profileName: String
    let vibe: String?
    let voiceDescription: String?
    let sourceText: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }
}

// MARK: - E2ETransportStatus

struct E2ETransportStatus: Decodable {
    let name: String
    let state: String
    let advertisedAddress: String?

    enum CodingKeys: String, CodingKey {
        case name
        case state
        case advertisedAddress = "advertised_address"
    }
}

// MARK: - E2EHealthSnapshot

struct E2EHealthSnapshot: Decodable {
    let status: String
    let workerMode: String
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case workerMode = "worker_mode"
        case workerReady = "worker_ready"
    }
}

// MARK: - E2EStatusSnapshot

struct E2EStatusSnapshot: Decodable {
    let workerMode: String
    let cachedProfiles: [E2EProfileSnapshot]
    let transports: [E2ETransportStatus]
    let generationQueue: E2EQueueStatusSnapshot
    let playbackQueue: E2EQueueStatusSnapshot
    let playback: E2EPlaybackStatusSnapshot

    enum CodingKeys: String, CodingKey {
        case workerMode = "worker_mode"
        case cachedProfiles = "cached_profiles"
        case transports
        case generationQueue = "generation_queue"
        case playbackQueue = "playback_queue"
        case playback
    }
}

// MARK: - E2EQueueStatusSnapshot

struct E2EQueueStatusSnapshot: Decodable {
    let activeRequest: E2EActiveRequestSnapshot?
    let activeRequests: [E2EActiveRequestSnapshot]
    let queuedRequests: [E2EQueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queuedRequests = "queued_requests"
    }
}

// MARK: - E2EPlaybackStatusSnapshot

struct E2EPlaybackStatusSnapshot: Decodable {
    let state: String
    let activeRequest: E2EActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

// MARK: - E2EActiveRequestSnapshot

struct E2EActiveRequestSnapshot: Decodable, Equatable {
    let id: String
    let op: String
    let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }
}

// MARK: - E2EQueuedRequestSnapshot

struct E2EQueuedRequestSnapshot: Decodable, Equatable {
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
}

// MARK: - E2EQueueSnapshotResponse

struct E2EQueueSnapshotResponse: Decodable {
    let queueType: String
    let activeRequest: E2EActiveRequestSnapshot?
    let activeRequests: [E2EActiveRequestSnapshot]
    let queue: [E2EQueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case activeRequests = "active_requests"
        case queue
    }
}

// MARK: - E2EPlaybackStateResponse

struct E2EPlaybackStateResponse: Decodable {
    let playback: E2EPlaybackStateSnapshot
}

// MARK: - E2EPlaybackStateSnapshot

struct E2EPlaybackStateSnapshot: Decodable {
    let state: String
    let activeRequest: E2EActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

// MARK: - E2EQueueClearedResponse

struct E2EQueueClearedResponse: Decodable {
    let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case clearedCount = "cleared_count"
    }
}

// MARK: - E2EQueueCancellationResponse

struct E2EQueueCancellationResponse: Decodable {
    let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case cancelledRequestID = "cancelled_request_id"
    }
}

// MARK: - E2ERequestListResponse

struct E2ERequestListResponse: Decodable {
    let requests: [E2EJobSnapshot]
}

// MARK: - E2ETextProfileListResponse

struct E2ETextProfileListResponse: Decodable {
    let textProfiles: E2ETextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }
}

// MARK: - E2ETextProfileResponse

struct E2ETextProfileResponse: Decodable {
    let profile: E2ETextProfileSnapshot
}

// MARK: - E2ETextProfilesSnapshot

struct E2ETextProfilesSnapshot: Decodable {
    let builtInStyle: String
    let baseProfile: E2ETextProfileSnapshot
    let activeProfile: E2ETextProfileSnapshot
    let storedProfiles: [E2ETextProfileSnapshot]
    let effectiveProfile: E2ETextProfileSnapshot

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
        case baseProfile = "base_profile"
        case activeProfile = "active_profile"
        case storedProfiles = "stored_profiles"
        case effectiveProfile = "effective_profile"
    }
}

// MARK: - E2ETextProfileStyleResponse

struct E2ETextProfileStyleResponse: Decodable {
    let textProfileStyle: E2ETextProfileStyleSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfileStyle = "text_profile_style"
    }
}

// MARK: - E2ETextProfileSnapshot

struct E2ETextProfileSnapshot: Decodable, Equatable {
    let id: String
    let name: String
    let replacements: [E2ETextReplacementSnapshot]
}

// MARK: - E2ETextProfileStyleSnapshot

struct E2ETextProfileStyleSnapshot: Decodable, Equatable {
    let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }
}

// MARK: - E2ETextReplacementSnapshot

struct E2ETextReplacementSnapshot: Decodable, Equatable {
    let id: String
    let text: String
    let replacement: String
    let match: String
    let phase: String
    let isCaseSensitive: Bool
    let formats: [String]
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case replacement
        case match
        case phase
        case isCaseSensitive = "is_case_sensitive"
        case formats
        case priority
    }
}

// MARK: - E2EJobSnapshot

struct E2EJobSnapshot: Decodable {
    let requestID: String
    let status: String
    let history: [E2EJobEvent]
    let terminalEvent: E2EJobEvent?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case history
        case terminalEvent = "terminal_event"
    }

    var jobID: String { requestID }
}

// MARK: - E2EJobEvent

struct E2EJobEvent: Decodable {
    let id: String?
    let event: String?
    let op: String?
    let stage: String?
    let ok: Bool?
    let reason: String?
    let profileName: String?
    let profilePath: String?
    let message: String?
    let code: String?
    let cancelledRequestID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case op
        case stage
        case ok
        case reason
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case message
        case code
        case cancelledRequestID = "cancelled_request_id"
    }
}
