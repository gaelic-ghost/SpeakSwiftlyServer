import AsyncAlgorithms
import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

// MARK: - Server Host

actor ServerHost {
    enum PublishMode {
        case immediate
        case coalesced
    }

    struct JobRecord {
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
                history: history,
            )
        }
    }

    static let mutationRefreshRetryDelays: [Duration] = [
        .milliseconds(50),
        .milliseconds(100),
    ]
    static let recentErrorLimit = 8

    var configuration: ServerConfiguration
    var httpConfig: HTTPConfig
    var mcpConfig: MCPConfig
    let runtime: any ServerRuntimeProtocol
    let runtimeConfigurationStore: RuntimeConfigurationStore
    let state: EmbeddedServer
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
    var publishTask: Task<Void, Never>?
    var requestMonitorTasks = [String: Task<Void, Never>]()
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
        queuedRequests: [],
    )
    var playbackQueueStatus = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil,
        activeRequests: [],
        queuedRequests: [],
    )
    var playbackStatus = PlaybackStatusSnapshot(
        state: SpeakSwiftly.PlaybackState.idle.rawValue,
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil,
    )
    var runtimeRefreshSnapshot: RuntimeRefreshSnapshot?
    var transportStatuses = [String: TransportStatusSnapshot]()
    var recentErrors = [RecentErrorSnapshot]()
    var nextRuntimeRefreshSequenceID = 1
    var pendingRuntimeRefresh = true
    var jobs = [String: JobRecord]()
    var hasRequestedStartupProfileRefresh = false

    var serverMode: String {
        if workerMode == "ready", profileCacheState != "stale" {
            "ready"
        } else {
            "degraded"
        }
    }

    init(
        configuration: ServerConfiguration,
        httpConfig: HTTPConfig? = nil,
        mcpConfig: MCPConfig? = nil,
        runtime: any ServerRuntimeProtocol,
        runtimeConfigurationStore: RuntimeConfigurationStore = .init(),
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        state: EmbeddedServer,
    ) {
        let (immediatePublishRequests, immediatePublishContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let (coalescedPublishRequests, coalescedPublishContinuation) = AsyncStream.makeStream(
            of: Void.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let (publishedStateStream, publishedStateContinuation) = AsyncStream.makeStream(
            of: HostStateSnapshot.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        let (hostEventStream, hostEventContinuation) = AsyncStream.makeStream(
            of: HostEvent.self,
            bufferingPolicy: .bufferingNewest(32),
        )
        let sharedPublishedStates = publishedStateStream.share(bufferingPolicy: .bufferingLatest(1))
        let sharedHostEvents = hostEventStream.share(bufferingPolicy: .bufferingLatest(32))

        self.configuration = configuration
        self.httpConfig = httpConfig ?? .init(
            enabled: true,
            host: configuration.host,
            port: configuration.port,
            sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
        )
        self.mcpConfig = mcpConfig ?? .init(
            enabled: false,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly",
        )
        self.runtime = runtime
        self.runtimeConfigurationStore = runtimeConfigurationStore
        self.activeRuntimeSpeechBackend = activeRuntimeSpeechBackend
            ?? runtimeConfigurationStore.initialActiveRuntimeSpeechBackend()
        activeDefaultVoiceProfileName = runtimeConfigurationStore.initialActiveDefaultVoiceProfileName(
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        self.state = state
        transportStatuses = Self.initialTransportStatuses(httpConfig: self.httpConfig, mcpConfig: self.mcpConfig)
        self.immediatePublishRequests = immediatePublishRequests
        self.immediatePublishContinuation = immediatePublishContinuation
        self.coalescedPublishRequests = coalescedPublishRequests
        self.coalescedPublishContinuation = coalescedPublishContinuation
        self.publishedStateContinuation = publishedStateContinuation
        self.hostEventContinuation = hostEventContinuation
        makeSharedStateUpdates = { [sharedPublishedStates] in
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
        makeSharedHostEvents = { [sharedHostEvents] in
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
        encoder.outputFormatting = [.sortedKeys]
    }

    // MARK: - Construction

    static func makeLive(
        appConfig: AppConfig,
        state: EmbeddedServer,
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) async -> ServerHost {
        let runtimeConfigurationStore = RuntimeConfigurationStore(environment: environment)
        let startupConfiguration = runtimeConfigurationStore.startupConfiguration()
        let runtime = await ServerRuntimeAdapter(
            runtime: SpeakSwiftlyRuntimeLauncher.shared.launch(
                configuration: startupConfiguration,
                environment: environment,
                makeRuntime: { configuration in
                    await SpeakSwiftly.liftoff(configuration: configuration)
                },
            ),
        )
        return ServerHost(
            configuration: appConfig.server,
            httpConfig: appConfig.http,
            mcpConfig: appConfig.mcp,
            runtime: runtime,
            runtimeConfigurationStore: runtimeConfigurationStore,
            activeRuntimeSpeechBackend: startupConfiguration.speechBackend,
            state: state,
        )
    }
}
