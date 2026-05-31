import Foundation

package struct ProfileCacheStatusSnapshot: Codable, Equatable {
    package let state: String
    package let warning: String?
    package let profileCount: Int
    package let lastRefreshAt: String?

    enum CodingKeys: String, CodingKey {
        case state
        case warning
        case profileCount = "profile_count"
        case lastRefreshAt = "last_refresh_at"
    }
}

package struct TextProfilesStatusSnapshot: Codable, Equatable {
    package let activeProfileID: String
    package let storedProfileCount: Int

    enum CodingKeys: String, CodingKey {
        case activeProfileID = "active_profile_id"
        case storedProfileCount = "stored_profile_count"
    }
}

package struct RuntimeConfigurationStatusSnapshot: Codable, Equatable {
    package let activeRuntimeSpeechBackend: String
    package let nextRuntimeSpeechBackend: String
    package let activeDuckMediaVolume: String
    package let nextDuckMediaVolume: String
    package let activeDefaultVoiceProfileName: String?
    package let nextDefaultVoiceProfileName: String?
    package let persistedSpeechBackend: String?
    package let persistedDuckMediaVolume: String?
    package let persistedDefaultVoiceProfileName: String?
    package let environmentSpeechBackendOverride: String?
    package let persistedConfigurationPath: String
    package let persistedConfigurationState: String

    enum CodingKeys: String, CodingKey {
        case activeRuntimeSpeechBackend = "active_runtime_speech_backend"
        case nextRuntimeSpeechBackend = "next_runtime_speech_backend"
        case activeDuckMediaVolume = "active_duck_media_volume"
        case nextDuckMediaVolume = "next_duck_media_volume"
        case activeDefaultVoiceProfileName = "active_default_voice_profile_name"
        case nextDefaultVoiceProfileName = "next_default_voice_profile_name"
        case persistedSpeechBackend = "persisted_speech_backend"
        case persistedDuckMediaVolume = "persisted_duck_media_volume"
        case persistedDefaultVoiceProfileName = "persisted_default_voice_profile_name"
        case environmentSpeechBackendOverride = "environment_speech_backend_override"
        case persistedConfigurationPath = "persisted_configuration_path"
        case persistedConfigurationState = "persisted_configuration_state"
    }
}

package struct JobEventUpdate: Equatable {
    package let jobID: String
    package let event: ServerJobEvent
    package let historyIndex: Int
    package let terminal: Bool
}

package enum HostEvent {
    case transportChanged(TransportStatusSnapshot)
    case jobChanged(JobSnapshot)
    case jobEvent(JobEventUpdate)
    case playbackChanged(PlaybackStatusSnapshot)
    case profileCacheChanged(ProfileCacheStatusSnapshot)
    case textProfilesChanged(TextProfilesStatusSnapshot)
    case runtimeConfigurationChanged(RuntimeConfigurationStatusSnapshot)
    case recentErrorRecorded(RecentErrorSnapshot)
}
