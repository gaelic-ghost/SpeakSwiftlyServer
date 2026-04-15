import Foundation

// MARK: - ProfileCacheStatusSnapshot

struct ProfileCacheStatusSnapshot: Codable, Equatable {
    let state: String
    let warning: String?
    let profileCount: Int
    let lastRefreshAt: String?

    enum CodingKeys: String, CodingKey {
        case state
        case warning
        case profileCount = "profile_count"
        case lastRefreshAt = "last_refresh_at"
    }
}

// MARK: - TextProfilesStatusSnapshot

struct TextProfilesStatusSnapshot: Codable, Equatable {
    let activeProfileID: String
    let storedProfileCount: Int

    enum CodingKeys: String, CodingKey {
        case activeProfileID = "active_profile_id"
        case storedProfileCount = "stored_profile_count"
    }
}

// MARK: - RuntimeConfigurationStatusSnapshot

struct RuntimeConfigurationStatusSnapshot: Codable, Equatable {
    let activeRuntimeSpeechBackend: String
    let nextRuntimeSpeechBackend: String
    let activeDefaultVoiceProfileName: String?
    let nextDefaultVoiceProfileName: String?
    let persistedSpeechBackend: String?
    let persistedDefaultVoiceProfileName: String?
    let environmentSpeechBackendOverride: String?
    let persistedConfigurationPath: String
    let persistedConfigurationState: String

    enum CodingKeys: String, CodingKey {
        case activeRuntimeSpeechBackend = "active_runtime_speech_backend"
        case nextRuntimeSpeechBackend = "next_runtime_speech_backend"
        case activeDefaultVoiceProfileName = "active_default_voice_profile_name"
        case nextDefaultVoiceProfileName = "next_default_voice_profile_name"
        case persistedSpeechBackend = "persisted_speech_backend"
        case persistedDefaultVoiceProfileName = "persisted_default_voice_profile_name"
        case environmentSpeechBackendOverride = "environment_speech_backend_override"
        case persistedConfigurationPath = "persisted_configuration_path"
        case persistedConfigurationState = "persisted_configuration_state"
    }
}

// MARK: - JobEventUpdate

struct JobEventUpdate: Equatable {
    let jobID: String
    let event: ServerJobEvent
    let historyIndex: Int
    let terminal: Bool
}

// MARK: - HostEvent

enum HostEvent {
    case transportChanged(TransportStatusSnapshot)
    case jobChanged(JobSnapshot)
    case jobEvent(JobEventUpdate)
    case playbackChanged(PlaybackStatusSnapshot)
    case profileCacheChanged(ProfileCacheStatusSnapshot)
    case textProfilesChanged(TextProfilesStatusSnapshot)
    case runtimeConfigurationChanged(RuntimeConfigurationStatusSnapshot)
    case recentErrorRecorded(RecentErrorSnapshot)
}
