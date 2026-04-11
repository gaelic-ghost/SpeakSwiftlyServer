import AsyncAlgorithms
import Foundation
import Hummingbird
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Server Host

actor ServerHost {
    static let mutationRefreshRetryDelays: [Duration] = [
        .milliseconds(50),
        .milliseconds(100),
    ]
    static let recentErrorLimit = 8

    enum PublishMode: Sendable {
        case immediate
        case coalesced
    }

    struct JobRecord: Sendable {
        let jobID: String
        let op: String
        let profileName: String?
        let submittedAt: Date
        var startedAt: Date?
        var terminalAt: Date?
        var latestEvent: ServerJobEvent?
        var terminalEvent: ServerJobEvent?
        var history: [ServerJobEvent] = []

        var snapshot: JobSnapshot {
            .init(
                requestID: jobID,
                op: op,
                submittedAt: TimestampFormatter.string(from: submittedAt),
                startedAt: startedAt.map(TimestampFormatter.string(from:)),
                status: terminalEvent == nil ? "running" : "completed",
                latestEvent: latestEvent,
                terminalEvent: terminalEvent,
                history: history
            )
        }
    }

    var configuration: ServerConfiguration
    var httpConfig: HTTPConfig
    var mcpConfig: MCPConfig
    let runtime: any ServerRuntimeProtocol
    let runtimeConfigurationStore: RuntimeConfigurationStore
    let state: ServerState
    let immediatePublishRequests: AsyncStream<Void>
    let immediatePublishContinuation: AsyncStream<Void>.Continuation
    let coalescedPublishRequests: AsyncStream<Void>
    let coalescedPublishContinuation: AsyncStream<Void>.Continuation
    let publishedStateContinuation: AsyncStream<HostStateSnapshot>.Continuation
    let makeSharedStateUpdates: @Sendable () -> AsyncStream<HostStateSnapshot>
    let hostEventContinuation: AsyncStream<HostEvent>.Continuation
    let makeSharedHostEvents: @Sendable () -> AsyncStream<HostEvent>
    let encoder = JSONEncoder()
    let byteBufferAllocator = ByteBufferAllocator()
    var activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend

    var statusTask: Task<Void, Never>?
    var pruneTask: Task<Void, Never>?
    var publishTask: Task<Void, Never>?
    var workerMode = "starting"
    var workerStage = "starting"
    var startupError: String?
    var activeDefaultVoiceProfileName: String?
    var profileCache = [ProfileSnapshot]()
    var profileCacheState = "uninitialized"
    var profileCacheWarning: String?
    var lastProfileRefreshAt: Date?
    var generationQueueStatus = QueueStatusSnapshot(
        queueType: "generation",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: []
    )
    var playbackQueueStatus = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: []
    )
    var playbackStatus = PlaybackStatusSnapshot(
        state: SpeakSwiftly.PlaybackState.idle.rawValue,
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil
    )
    var runtimeRefreshSnapshot: RuntimeRefreshSnapshot?
    var transportStatuses = [String: TransportStatusSnapshot]()
    var recentErrors = [RecentErrorSnapshot]()
    var nextRuntimeRefreshSequenceID = 1
    var pendingRuntimeRefresh = true
    var jobs = [String: JobRecord]()
    var hasRequestedStartupProfileRefresh = false

    // MARK: - Construction

    static func live(appConfig: AppConfig, state: ServerState) async -> ServerHost {
        let runtimeConfigurationStore = RuntimeConfigurationStore()
        let startupConfiguration = runtimeConfigurationStore.startupConfiguration()
        let runtime = ServerRuntimeAdapter(runtime: await SpeakSwiftly.liftoff(configuration: startupConfiguration))
        let host = ServerHost(
            configuration: appConfig.server,
            httpConfig: appConfig.http,
            mcpConfig: appConfig.mcp,
            runtime: runtime,
            runtimeConfigurationStore: runtimeConfigurationStore,
            activeRuntimeSpeechBackend: startupConfiguration.speechBackend,
            state: state
        )
        await host.start()
        return host
    }

    init(
        configuration: ServerConfiguration,
        httpConfig: HTTPConfig? = nil,
        mcpConfig: MCPConfig? = nil,
        runtime: any ServerRuntimeProtocol,
        runtimeConfigurationStore: RuntimeConfigurationStore = .init(),
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        state: ServerState
    ) {
        let (immediatePublishRequests, immediatePublishContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let (coalescedPublishRequests, coalescedPublishContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let (publishedStateStream, publishedStateContinuation) = AsyncStream.makeStream(
            of: HostStateSnapshot.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let (hostEventStream, hostEventContinuation) = AsyncStream.makeStream(
            of: HostEvent.self,
            bufferingPolicy: .bufferingNewest(32)
        )
        let sharedPublishedStates = publishedStateStream.share(bufferingPolicy: .bufferingLatest(1))
        let sharedHostEvents = hostEventStream.share(bufferingPolicy: .bufferingLatest(32))

        self.configuration = configuration
        self.httpConfig = httpConfig ?? .init(
            enabled: true,
            host: configuration.host,
            port: configuration.port,
            sseHeartbeatSeconds: configuration.sseHeartbeatSeconds
        )
        self.mcpConfig = mcpConfig ?? .init(
            enabled: false,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
        )
        self.runtime = runtime
        self.runtimeConfigurationStore = runtimeConfigurationStore
        self.activeRuntimeSpeechBackend = activeRuntimeSpeechBackend
            ?? runtimeConfigurationStore.initialActiveRuntimeSpeechBackend()
        self.activeDefaultVoiceProfileName = configuration.defaultVoiceProfileName
        self.state = state
        self.transportStatuses = Self.initialTransportStatuses(httpConfig: self.httpConfig, mcpConfig: self.mcpConfig)
        self.immediatePublishRequests = immediatePublishRequests
        self.immediatePublishContinuation = immediatePublishContinuation
        self.coalescedPublishRequests = coalescedPublishRequests
        self.coalescedPublishContinuation = coalescedPublishContinuation
        self.publishedStateContinuation = publishedStateContinuation
        self.hostEventContinuation = hostEventContinuation
        self.makeSharedStateUpdates = { [sharedPublishedStates] in
            AsyncStream { continuation in
                let task = Task {
                    for await snapshot in sharedPublishedStates {
                        continuation.yield(snapshot)
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        self.makeSharedHostEvents = { [sharedHostEvents] in
            AsyncStream { continuation in
                let task = Task {
                    for await event in sharedHostEvents {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }

                continuation.onTermination = { _ in
                    task.cancel()
                }
            }
        }
        self.encoder.outputFormatting = [.sortedKeys]
    }

    // MARK: - Lifecycle

    func start() async {
        self.publishTask = Task {
            let immediateRequests = self.immediatePublishRequests
            let coalescedRequests = self.coalescedPublishRequests.debounce(for: .milliseconds(25))
            for await _ in merge(immediateRequests, coalescedRequests) {
                await self.publishState()
            }
        }

        let statusStream = await runtime.statusEvents()
        self.statusTask = Task {
            for await status in statusStream {
                await self.handle(status: status)
            }
        }

        self.pruneTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.configuration.jobPruneIntervalSeconds))
                self.pruneCompletedJobs()
                await self.requestPublish(mode: .coalesced, refreshRuntimeState: false)
            }
        }

        await runtime.start()
        await requestPublish(mode: .immediate, refreshRuntimeState: true)
    }

    func shutdown() async {
        self.statusTask?.cancel()
        self.pruneTask?.cancel()
        await runtime.shutdown()
        self.workerMode = "stopped"
        self.workerStage = "stopped"
        if httpConfig.enabled {
            updateTransportStatus(named: "http", state: "stopped")
        }
        if mcpConfig.enabled {
            updateTransportStatus(named: "mcp", state: "stopped")
        }

        pendingRuntimeRefresh = false
        await publishState()
        self.publishTask?.cancel()
        immediatePublishContinuation.finish()
        coalescedPublishContinuation.finish()
        publishedStateContinuation.finish()
        hostEventContinuation.finish()
    }

    // MARK: - Live Updates

    func stateUpdates() -> AsyncStream<HostStateSnapshot> {
        makeSharedStateUpdates()
    }

    func eventUpdates() -> AsyncStream<HostEvent> {
        makeSharedHostEvents()
    }

    // MARK: - Transport Lifecycle

    func markTransportStarting(name: String) async {
        updateTransportStatus(named: name, state: "starting")
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func markTransportListening(name: String) async {
        updateTransportStatus(named: name, state: "listening")
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func markTransportStopped(name: String) async {
        updateTransportStatus(named: name, state: "stopped")
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func markTransportFailed(name: String, message: String) async {
        updateTransportStatus(named: name, state: "failed")
        recordRecentError(
            source: "transport:\(name)",
            code: "transport_failed",
            message: message
        )
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    // MARK: - Configuration Reload

    func applyConfigurationUpdate(_ appConfig: AppConfig) async {
        let restartRequiredKeys = restartRequiredConfigurationKeys(for: appConfig)
        let appliedLiveChanges = applyLiveConfigurationChanges(from: appConfig)

        if !restartRequiredKeys.isEmpty {
            recordRecentError(
                source: "config",
                code: "reload_requires_restart",
                message: "SpeakSwiftlyServer reloaded configuration from disk, but these settings still require a full restart before they can take effect: \(restartRequiredKeys.joined(separator: ", "))."
            )
        }

        if appliedLiveChanges {
            await requestPublish(mode: .immediate, refreshRuntimeState: false)
        }
    }

    func markConfigurationReloadRejected(_ message: String) async {
        recordRecentError(
            source: "config",
            code: "reload_rejected",
            message: "SpeakSwiftlyServer detected a configuration file change, but the updated values were not valid and were left unapplied. Likely cause: \(message)"
        )
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func markConfigurationWatchFailed(_ error: any Error) async {
        recordRecentError(
            source: "config",
            code: "reload_watch_failed",
            message: "SpeakSwiftlyServer could not continue watching for configuration file updates. Likely cause: \(error.localizedDescription)"
        )
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    // MARK: - Shared Snapshots

    func hostStateSnapshot() -> HostStateSnapshot {
        let overview = HostOverviewSnapshot(
            service: configuration.name,
            environment: configuration.environment,
            defaultVoiceProfileName: activeDefaultVoiceProfileName,
            serverMode: serverMode,
            workerMode: workerMode,
            workerStage: workerStage,
            workerReady: workerMode == "ready",
            startupError: startupError,
            profileCacheState: profileCacheState,
            profileCacheWarning: profileCacheWarning,
            profileCount: profileCache.count,
            lastProfileRefreshAt: lastProfileRefreshAt.map(TimestampFormatter.string(from:))
        )

        return .init(
            overview: overview,
            runtimeRefresh: runtimeRefreshSnapshot,
            generationQueue: generationQueueStatus,
            playbackQueue: playbackQueueStatus,
            playback: playbackStatus,
            currentGenerationJobs: currentGenerationJobSnapshots(),
            runtimeConfiguration: runtimeConfigurationSnapshot(),
            transports: transportSnapshots(),
            recentErrors: recentErrors
        )
    }

    // MARK: - Health and Readiness

    func healthSnapshot() -> HealthSnapshot {
        let overview = hostStateSnapshot().overview
        return .init(
            status: "ok",
            service: overview.service,
            environment: overview.environment,
            serverMode: overview.serverMode,
            workerMode: overview.workerMode,
            workerStage: overview.workerStage,
            workerReady: overview.workerReady,
            startupError: overview.startupError
        )
    }

    func readinessSnapshot() -> (Bool, ReadinessSnapshot) {
        let hostState = hostStateSnapshot()
        let overview = hostState.overview
        let ready = overview.workerReady
        return (
            ready,
            .init(
                status: ready ? "ready" : "not_ready",
                serverMode: overview.serverMode,
                workerMode: overview.workerMode,
                workerStage: overview.workerStage,
                workerReady: ready,
                startupError: overview.startupError,
                profileCacheState: overview.profileCacheState,
                profileCacheWarning: overview.profileCacheWarning,
                profileCount: overview.profileCount,
                lastProfileRefreshAt: overview.lastProfileRefreshAt
            )
        )
    }

    var serverMode: String {
        if workerMode == "ready", profileCacheState != "stale" {
            "ready"
        } else {
            "degraded"
        }
    }
}
