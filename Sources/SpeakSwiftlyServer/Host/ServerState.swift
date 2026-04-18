import Foundation
import Observation
import SpeakSwiftly

/// Main-actor observable app model for an embedded SpeakSwiftly server session.
///
/// `EmbeddedServer` is the consumer-facing type an app should own directly. It exposes the current
/// host snapshots as bindable properties, exposes the app-owned control actions, and owns the
/// embedded runtime lifecycle through ``liftoff(environment:)`` and ``land()``.
@Observable
@MainActor
public final class EmbeddedServer {
    /// Configuration options for the app-owned embedded server bootstrap path.
    public struct Options: Sendable {
        /// Optional localhost port override for the embedded HTTP transport.
        ///
        /// When this is set, the embedded server applies the same port to the shared transport
        /// default and the concrete HTTP listener unless the caller later overrides those values
        /// more specifically through the environment-driven config surface.
        public var port: Int?

        /// Optional runtime profile-root override for the embedded server and the underlying
        /// `SpeakSwiftly` runtime.
        ///
        /// Pass this when the host app wants one explicit persistence root, such as an app-owned
        /// Application Support subdirectory or an App Group container path.
        public var runtimeProfileRootURL: URL?

        public init(port: Int? = nil, runtimeProfileRootURL: URL? = nil) {
            self.port = port
            self.runtimeProfileRootURL = runtimeProfileRootURL
        }
    }

    struct Actions {
        static let unavailable = Actions(
            refreshVoiceProfiles: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not refresh voice profiles because no embedded host action performer is configured yet.",
                )
            },
            setDefaultVoiceProfileName: { profileName in
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not set default voice profile '\(profileName)' because no embedded host action performer is configured yet.",
                )
            },
            clearDefaultVoiceProfileName: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not clear the default voice profile because no embedded host action performer is configured yet.",
                )
            },
            switchSpeechBackend: { speechBackend in
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not switch the active speech backend to '\(speechBackend.rawValue)' because no embedded host action performer is configured yet.",
                )
            },
            reloadModels: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not reload resident runtime models because no embedded host action performer is configured yet.",
                )
            },
            unloadModels: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not unload resident runtime models because no embedded host action performer is configured yet.",
                )
            },
            pausePlayback: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not pause playback because no embedded host action performer is configured yet.",
                )
            },
            resumePlayback: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not resume playback because no embedded host action performer is configured yet.",
                )
            },
            clearPlaybackQueue: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not clear the playback queue because no embedded host action performer is configured yet.",
                )
            },
            cancelPlaybackRequest: { requestID in
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not cancel playback request '\(requestID)' because no embedded host action performer is configured yet.",
                )
            },
        )

        let refreshVoiceProfiles: @Sendable () async throws -> [ProfileSnapshot]
        let setDefaultVoiceProfileName: @Sendable (String) async throws -> String
        let clearDefaultVoiceProfileName: @Sendable () async throws -> String?
        let switchSpeechBackend: @Sendable (SpeakSwiftly.SpeechBackend) async throws -> HostStateSnapshot
        let reloadModels: @Sendable () async throws -> HostStateSnapshot
        let unloadModels: @Sendable () async throws -> HostStateSnapshot
        let pausePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let resumePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let clearPlaybackQueue: @Sendable () async throws -> Int
        let cancelPlaybackRequest: @Sendable (String) async throws -> String
    }

    enum EmbeddedServerActionError: LocalizedError {
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

    @ObservationIgnored private let options: Options
    @ObservationIgnored private var actions = Actions.unavailable
    @ObservationIgnored private var lifecycle: EmbeddedServerLifecycleHooks?
    @ObservationIgnored private var stopCoordinator = EmbeddedServerStopCoordinator()
    @ObservationIgnored private var isLiftingOff = false

    /// Creates an app-owned embedded server model with optional bootstrap overrides.
    public init(options: Options = .init()) {
        self.options = options
    }

    /// Starts the embedded server if it is not already running.
    public func liftoff(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) async throws {
        try await liftoff(
            environment: environment,
            defaultProfile: .embeddedSession,
            bootstrap: embeddedServerLiveBootstrap,
        )
    }

    /// Gracefully stops the embedded server and waits for transport and host cleanup to finish.
    public func land() async throws {
        guard let lifecycle else {
            return
        }

        if await stopCoordinator.requestStopIfNeeded() {
            await lifecycle.requestStop()
        }
        try await lifecycle.waitUntilStopped()
    }

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

    /// Switches the active runtime speech backend and applies the refreshed host state snapshot.
    @discardableResult
    public func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async throws -> HostStateSnapshot {
        let snapshot = try await actions.switchSpeechBackend(speechBackend)
        applyHostStateSnapshot(snapshot)
        return snapshot
    }

    /// Reloads resident runtime models and applies the refreshed host state snapshot.
    @discardableResult
    public func reloadModels() async throws -> HostStateSnapshot {
        let snapshot = try await actions.reloadModels()
        applyHostStateSnapshot(snapshot)
        return snapshot
    }

    /// Unloads resident runtime models and applies the refreshed host state snapshot.
    @discardableResult
    public func unloadModels() async throws -> HostStateSnapshot {
        let snapshot = try await actions.unloadModels()
        applyHostStateSnapshot(snapshot)
        return snapshot
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

    func liftoff(
        environment: [String: String],
        defaultProfile: AppRuntimeDefaultProfile,
        bootstrap: @escaping @Sendable ([String: String], EmbeddedServer) async throws -> EmbeddedServerLifecycleHooks = embeddedServerLiveBootstrap,
    ) async throws {
        guard lifecycle == nil, !isLiftingOff else {
            return
        }

        isLiftingOff = true
        defer { isLiftingOff = false }

        lifecycle = try await bootstrap(
            embeddedServerEffectiveEnvironment(
                environment: environment,
                options: options,
                defaultProfile: defaultProfile,
            ),
            self,
        )
    }

    func applyHostStateSnapshot(_ snapshot: HostStateSnapshot) {
        overview = snapshot.overview
        runtimeRefresh = snapshot.runtimeRefresh
        generationQueue = snapshot.generationQueue
        playbackQueue = snapshot.playbackQueue
        playback = snapshot.playback
        currentGenerationJobs = snapshot.currentGenerationJobs
        runtimeConfiguration = snapshot.runtimeConfiguration
        transports = snapshot.transports
        recentErrors = snapshot.recentErrors
    }

    func configureActions(_ actions: Actions) {
        self.actions = actions
    }

    func waitUntilStopped() async throws {
        guard let lifecycle else {
            return
        }

        try await lifecycle.waitUntilStopped()
    }
}
