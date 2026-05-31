import Foundation
import Observation
import SpeakSwiftly
import SSSCore

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

        /// Optional persisted server config URL.
        ///
        /// When omitted, the server uses its default Application Support config path and seeds
        /// that file from the bundled package resource the first time it is needed.
        public var configurationURL: URL?

        public init(
            port: Int? = nil,
            runtimeProfileRootURL: URL? = nil,
            configurationURL: URL? = nil,
        ) {
            self.port = port
            self.runtimeProfileRootURL = runtimeProfileRootURL
            self.configurationURL = configurationURL
        }
    }

    package struct Actions {
        static let unavailable = Actions(
            refreshVoiceProfiles: {
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not refresh voice profiles because no embedded host action performer is configured yet.",
                )
            },
            queueLiveSpeech: { _, _, _, _, _ in
                throw EmbeddedServerActionError.unavailable(
                    "EmbeddedServer could not queue the live speech request because no embedded host action performer is configured yet.",
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
        let queueLiveSpeech: @Sendable (
            String,
            String?,
            String?,
            SpeakSwiftly.RequestContext?,
            Bool,
        ) async throws -> String
        let setDefaultVoiceProfileName: @Sendable (String) async throws -> String
        let clearDefaultVoiceProfileName: @Sendable () async throws -> String?
        let switchSpeechBackend: @Sendable (SpeakSwiftly.SpeechBackend) async throws -> HostStateSnapshot
        let reloadModels: @Sendable () async throws -> HostStateSnapshot
        let unloadModels: @Sendable () async throws -> HostStateSnapshot
        let pausePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let resumePlayback: @Sendable () async throws -> PlaybackStatusSnapshot
        let clearPlaybackQueue: @Sendable () async throws -> Int
        let cancelPlaybackRequest: @Sendable (String) async throws -> String

        package init(
            refreshVoiceProfiles: @escaping @Sendable () async throws -> [ProfileSnapshot],
            queueLiveSpeech: @escaping @Sendable (
                String,
                String?,
                String?,
                SpeakSwiftly.RequestContext?,
                Bool,
            ) async throws -> String,
            setDefaultVoiceProfileName: @escaping @Sendable (String) async throws -> String,
            clearDefaultVoiceProfileName: @escaping @Sendable () async throws -> String?,
            switchSpeechBackend: @escaping @Sendable (SpeakSwiftly.SpeechBackend) async throws -> HostStateSnapshot,
            reloadModels: @escaping @Sendable () async throws -> HostStateSnapshot,
            unloadModels: @escaping @Sendable () async throws -> HostStateSnapshot,
            pausePlayback: @escaping @Sendable () async throws -> PlaybackStatusSnapshot,
            resumePlayback: @escaping @Sendable () async throws -> PlaybackStatusSnapshot,
            clearPlaybackQueue: @escaping @Sendable () async throws -> Int,
            cancelPlaybackRequest: @escaping @Sendable (String) async throws -> String,
        ) {
            self.refreshVoiceProfiles = refreshVoiceProfiles
            self.queueLiveSpeech = queueLiveSpeech
            self.setDefaultVoiceProfileName = setDefaultVoiceProfileName
            self.clearDefaultVoiceProfileName = clearDefaultVoiceProfileName
            self.switchSpeechBackend = switchSpeechBackend
            self.reloadModels = reloadModels
            self.unloadModels = unloadModels
            self.pausePlayback = pausePlayback
            self.resumePlayback = resumePlayback
            self.clearPlaybackQueue = clearPlaybackQueue
            self.cancelPlaybackRequest = cancelPlaybackRequest
        }
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
    public package(set) var overview = ServerHostDefaultSnapshots.overview

    /// Snapshot of the active and queued speech-generation work.
    public package(set) var generationQueue = ServerHostDefaultSnapshots.generationQueue

    /// Snapshot of the active and queued playback work.
    public package(set) var playbackQueue = ServerHostDefaultSnapshots.playbackQueue

    /// Current playback state reported by the shared runtime.
    public package(set) var playback = ServerHostDefaultSnapshots.playback

    /// Timing details for the most recent host refresh cycle, when one has completed.
    public package(set) var runtimeRefresh: RuntimeRefreshSnapshot?
    /// Live backend-switch progress for the running runtime.
    public package(set) var runtimeBackendTransition = ServerHostDefaultSnapshots.runtimeBackendTransition
    /// Generation jobs that are currently active in the runtime.
    public package(set) var currentGenerationJobs = [CurrentGenerationJobSnapshot]()
    /// The active and next-start runtime configuration state.
    public package(set) var runtimeConfiguration = ServerHostDefaultSnapshots.runtimeConfiguration
    /// Cached voice-profile summaries currently known to the host.
    public package(set) var voiceProfiles = [ProfileSnapshot]()
    /// Current status for each published operator transport.
    public package(set) var transports = [TransportStatusSnapshot]()
    /// Recent host and transport errors retained for operator inspection.
    public package(set) var recentErrors = [RecentErrorSnapshot]()

    @ObservationIgnored private let options: Options
    @ObservationIgnored private var actions = Actions.unavailable
    @ObservationIgnored private var lifecycle: EmbeddedServerLifecycleHooks?
    @ObservationIgnored private var stopCoordinator = EmbeddedServerStopCoordinator()
    @ObservationIgnored private var isLiftingOff = false

    var bootstrapOptions: Options {
        options
    }

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
        resetEmbeddedLifecycleState()
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

    /// Queues one live speech request through the embedded host and returns the accepted request identifier.
    @discardableResult
    public func queueLiveSpeech(
        text: String,
        profileName: String? = nil,
        textProfileID: String? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
    ) async throws -> String {
        try await actions.queueLiveSpeech(
            text,
            profileName,
            textProfileID,
            requestContext,
            qwenPreModelTextChunking,
        )
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

    package func liftoff(
        environment: [String: String],
        defaultProfile: ServerConfigDefaultProfile,
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

    package func applyHostStateSnapshot(_ snapshot: HostStateSnapshot) {
        overview = snapshot.overview
        runtimeRefresh = snapshot.runtimeRefresh
        generationQueue = snapshot.generationQueue
        playbackQueue = snapshot.playbackQueue
        playback = snapshot.playback
        runtimeBackendTransition = snapshot.runtimeBackendTransition
        currentGenerationJobs = snapshot.currentGenerationJobs
        runtimeConfiguration = snapshot.runtimeConfiguration
        transports = snapshot.transports
        recentErrors = snapshot.recentErrors
    }

    package func configureActions(_ actions: Actions) {
        self.actions = actions
    }

    package func waitUntilStopped() async throws {
        guard let lifecycle else {
            return
        }

        try await lifecycle.waitUntilStopped()
        resetEmbeddedLifecycleState()
    }

    private func resetEmbeddedLifecycleState() {
        lifecycle = nil
        stopCoordinator = EmbeddedServerStopCoordinator()
    }
}

extension EmbeddedServer: ServerHostStatePublishing {}
