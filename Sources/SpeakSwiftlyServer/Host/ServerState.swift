import Foundation
import Observation

// MARK: - Observable State

@Observable
@MainActor
public final class ServerState {
    struct Actions {
        let refreshVoiceProfiles: @MainActor @Sendable () async throws -> [ProfileSnapshot]
        let setDefaultVoiceProfileName: @MainActor @Sendable (String) async throws -> String
        let clearDefaultVoiceProfileName: @MainActor @Sendable () async -> Void
        let pausePlayback: @MainActor @Sendable () async throws -> PlaybackStatusSnapshot
        let resumePlayback: @MainActor @Sendable () async throws -> PlaybackStatusSnapshot
        let clearPlaybackQueue: @MainActor @Sendable () async throws -> Int
        let cancelPlaybackRequest: @MainActor @Sendable (String) async throws -> String

        static let unavailable = Actions(
            refreshVoiceProfiles: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not refresh voice profiles because no embedded host action performer is configured yet."
                )
            },
            setDefaultVoiceProfileName: { profileName in
                throw ServerStateActionError.unavailable(
                    "ServerState could not set default voice profile '\(profileName)' because no embedded host action performer is configured yet."
                )
            },
            clearDefaultVoiceProfileName: {},
            pausePlayback: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not pause playback because no embedded host action performer is configured yet."
                )
            },
            resumePlayback: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not resume playback because no embedded host action performer is configured yet."
                )
            },
            clearPlaybackQueue: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not clear the playback queue because no embedded host action performer is configured yet."
                )
            },
            cancelPlaybackRequest: { requestID in
                throw ServerStateActionError.unavailable(
                    "ServerState could not cancel playback request '\(requestID)' because no embedded host action performer is configured yet."
                )
            }
        )
    }

    enum ServerStateActionError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let message):
                message
            }
        }
    }

    public internal(set) var overview = HostOverviewSnapshot(
        service: "speak-swiftly-server",
        environment: "development",
        defaultVoiceProfileName: nil,
        serverMode: "degraded",
        workerMode: "starting",
        workerStage: "starting",
        workerReady: false,
        startupError: nil,
        profileCacheState: "uninitialized",
        profileCacheWarning: nil,
        profileCount: 0,
        lastProfileRefreshAt: nil
    )

    public internal(set) var generationQueue = QueueStatusSnapshot(
        queueType: "generation",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: []
    )

    public internal(set) var playbackQueue = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: []
    )

    public internal(set) var playback = PlaybackStatusSnapshot(
        state: "idle",
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil
    )

    public internal(set) var runtimeRefresh: RuntimeRefreshSnapshot?
    public internal(set) var currentGenerationJobs = [CurrentGenerationJobSnapshot]()
    public internal(set) var runtimeConfiguration = RuntimeConfigurationSnapshot(
        activeRuntimeSpeechBackend: "qwen3",
        nextRuntimeSpeechBackend: "qwen3",
        environmentSpeechBackendOverride: nil,
        persistedSpeechBackend: nil,
        profileRootPath: "",
        persistedConfigurationPath: "",
        persistedConfigurationExists: false,
        persistedConfigurationState: "missing",
        persistedConfigurationError: nil,
        persistedConfigurationAppliesOnRestart: true,
        activeRuntimeMatchesNextRuntime: true,
        persistedConfigurationWillAffectNextRuntimeStart: true
    )
    public internal(set) var voiceProfiles = [ProfileSnapshot]()
    public internal(set) var transports = [TransportStatusSnapshot]()
    public internal(set) var recentErrors = [RecentErrorSnapshot]()
    public internal(set) var jobsByID: [String: JobSnapshot] = [:]
    @ObservationIgnored private var actions = Actions.unavailable

    public init() {}

    public func listVoiceProfiles() -> [ProfileSnapshot] {
        voiceProfiles
    }

    public func refreshVoiceProfiles() async throws -> [ProfileSnapshot] {
        let profiles = try await actions.refreshVoiceProfiles()
        voiceProfiles = profiles
        return profiles
    }

    @discardableResult
    public func setDefaultVoiceProfileName(_ profileName: String) async throws -> String {
        let resolvedProfileName = try await actions.setDefaultVoiceProfileName(profileName)
        overview = overview.replacing(defaultVoiceProfileName: resolvedProfileName)
        return resolvedProfileName
    }

    public func clearDefaultVoiceProfileName() async {
        await actions.clearDefaultVoiceProfileName()
        overview = overview.replacing(defaultVoiceProfileName: nil)
    }

    @discardableResult
    public func pausePlayback() async throws -> PlaybackStatusSnapshot {
        let playback = try await actions.pausePlayback()
        self.playback = playback
        return playback
    }

    @discardableResult
    public func resumePlayback() async throws -> PlaybackStatusSnapshot {
        let playback = try await actions.resumePlayback()
        self.playback = playback
        return playback
    }

    @discardableResult
    public func clearPlaybackQueue() async throws -> Int {
        try await actions.clearPlaybackQueue()
    }

    @discardableResult
    public func cancelPlaybackRequest(_ requestID: String) async throws -> String {
        try await actions.cancelPlaybackRequest(requestID)
    }

    func configureActions(_ actions: Actions) {
        self.actions = actions
    }
}
