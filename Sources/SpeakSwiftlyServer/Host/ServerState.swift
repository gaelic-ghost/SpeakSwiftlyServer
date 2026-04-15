import Foundation
import Observation

// MARK: - Observable State

/// Main-actor observable read model for an embedded SpeakSwiftly server session.
///
/// `ServerState` is app-facing. It mirrors the host's latest snapshots for UI and other main-actor consumers,
/// while the real transport and runtime ownership stays behind ``EmbeddedServerSession`` and the internal host.
@Observable
@MainActor
public final class ServerState {
    struct Actions {
        static let unavailable = Actions(
            refreshVoiceProfiles: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not refresh voice profiles because no embedded host action performer is configured yet.",
                )
            },
            setDefaultVoiceProfileName: { profileName in
                throw ServerStateActionError.unavailable(
                    "ServerState could not set default voice profile '\(profileName)' because no embedded host action performer is configured yet.",
                )
            },
            clearDefaultVoiceProfileName: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not clear the default voice profile because no embedded host action performer is configured yet.",
                )
            },
            pausePlayback: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not pause playback because no embedded host action performer is configured yet.",
                )
            },
            resumePlayback: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not resume playback because no embedded host action performer is configured yet.",
                )
            },
            clearPlaybackQueue: {
                throw ServerStateActionError.unavailable(
                    "ServerState could not clear the playback queue because no embedded host action performer is configured yet.",
                )
            },
            cancelPlaybackRequest: { requestID in
                throw ServerStateActionError.unavailable(
                    "ServerState could not cancel playback request '\(requestID)' because no embedded host action performer is configured yet.",
                )
            },
        )

        let refreshVoiceProfiles: @Sendable () async throws -> [ProfileSnapshot]
        let setDefaultVoiceProfileName: @Sendable (String) async throws -> String
        let clearDefaultVoiceProfileName: @Sendable () async throws -> String?
        let pausePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let resumePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let clearPlaybackQueue: @Sendable () async throws -> Int
        let cancelPlaybackRequest: @Sendable (String) async throws -> String
    }

    enum ServerStateActionError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
                case let .unavailable(message):
                    message
            }
        }
    }

    /// High-level host identity, readiness, and voice-profile cache status.
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
        lastProfileRefreshAt: nil,
    )

    /// Snapshot of the active and queued speech-generation work.
    public internal(set) var generationQueue = QueueStatusSnapshot(
        queueType: "generation",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: [],
    )

    /// Snapshot of the active and queued playback work.
    public internal(set) var playbackQueue = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: [],
    )

    /// Current playback state reported by the shared runtime.
    public internal(set) var playback = PlaybackStatusSnapshot(
        state: "idle",
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil,
    )

    /// Timing details for the most recent host refresh cycle, when one has completed.
    public internal(set) var runtimeRefresh: RuntimeRefreshSnapshot?
    /// Generation jobs that are currently active in the runtime.
    public internal(set) var currentGenerationJobs = [CurrentGenerationJobSnapshot]()
    /// The active and next-start runtime configuration state.
    public internal(set) var runtimeConfiguration = RuntimeConfigurationSnapshot(
        activeRuntimeSpeechBackend: "qwen3",
        nextRuntimeSpeechBackend: "qwen3",
        activeDefaultVoiceProfileName: nil,
        nextDefaultVoiceProfileName: nil,
        environmentSpeechBackendOverride: nil,
        persistedSpeechBackend: nil,
        persistedDefaultVoiceProfileName: nil,
        profileRootPath: "",
        persistedConfigurationPath: "",
        persistedConfigurationExists: false,
        persistedConfigurationState: "missing",
        persistedConfigurationError: nil,
        persistedConfigurationAppliesOnRestart: true,
        activeRuntimeMatchesNextRuntime: true,
        persistedConfigurationWillAffectNextRuntimeStart: true,
    )
    /// Cached voice-profile summaries currently known to the host.
    public internal(set) var voiceProfiles = [ProfileSnapshot]()
    /// Current status for each published operator transport.
    public internal(set) var transports = [TransportStatusSnapshot]()
    /// Recent host and transport errors retained for operator inspection.
    public internal(set) var recentErrors = [RecentErrorSnapshot]()
    public internal(set) var jobsByID: [String: JobSnapshot] = [:]

    @ObservationIgnored private var actions = Actions.unavailable

    /// Creates an empty observable state model that an embedded session can hydrate.
    public init() {}

    /// Returns the currently cached voice-profile summaries.
    public func listVoiceProfiles() -> [ProfileSnapshot] {
        voiceProfiles
    }

    /// Refreshes the cached voice-profile list through the embedded host actions.
    public func refreshVoiceProfiles() async throws -> [ProfileSnapshot] {
        let profiles = try await actions.refreshVoiceProfiles()
        voiceProfiles = profiles
        return profiles
    }

    /// Sets the host's default voice profile name and updates the local overview snapshot.
    @discardableResult
    public func setDefaultVoiceProfileName(_ profileName: String) async throws -> String {
        let resolvedProfileName = try await actions.setDefaultVoiceProfileName(profileName)
        overview = overview.replacing(defaultVoiceProfileName: resolvedProfileName)
        return resolvedProfileName
    }

    /// Clears the host's default voice profile name and updates the local overview snapshot.
    public func clearDefaultVoiceProfileName() async throws {
        let resolvedProfileName = try await actions.clearDefaultVoiceProfileName()
        overview = overview.replacing(defaultVoiceProfileName: resolvedProfileName)
    }

    /// Requests a playback pause through the embedded host and returns the updated playback snapshot.
    @discardableResult
    public func pausePlayback() async throws -> PlaybackStatusSnapshot {
        let playback = try await actions.pausePlayback()
        self.playback = playback
        return playback
    }

    /// Requests playback resume through the embedded host and returns the updated playback snapshot.
    @discardableResult
    public func resumePlayback() async throws -> PlaybackStatusSnapshot {
        let playback = try await actions.resumePlayback()
        self.playback = playback
        return playback
    }

    /// Clears queued playback work and returns the number of requests removed.
    @discardableResult
    public func clearPlaybackQueue() async throws -> Int {
        try await actions.clearPlaybackQueue()
    }

    /// Cancels one active or queued playback request by identifier.
    @discardableResult
    public func cancelPlaybackRequest(_ requestID: String) async throws -> String {
        try await actions.cancelPlaybackRequest(requestID)
    }

    func configureActions(_ actions: Actions) {
        self.actions = actions
    }
}
