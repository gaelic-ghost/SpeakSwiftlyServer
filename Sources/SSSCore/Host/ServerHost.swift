import AsyncAlgorithms
import Foundation
import NIOCore
import SpeakSwiftly
import TextForSpeech

package actor ServerHost {
    package enum ProfileMutationExpectation: Equatable {
        case create(profileName: String)
        case rename(from: String, to: String)
        case reroll(profileName: String)
        case delete(profileName: String)

        var operationName: String {
            switch self {
                case .create:
                    "create_voice_profile"
                case .rename:
                    "update_voice_profile_name"
                case .reroll:
                    "reroll_voice_profile"
                case .delete:
                    "delete_voice_profile"
            }
        }

        var expectedSuccessProfileName: String {
            switch self {
                case let .create(profileName),
                     let .reroll(profileName),
                     let .delete(profileName):
                    profileName
                case let .rename(_, newProfileName):
                    newProfileName
            }
        }
    }

    package enum PublishMode {
        case immediate
        case coalesced
    }

    package struct RuntimeBackendSwitchExpectation: Equatable {
        let requestedSpeechBackend: SpeakSwiftly.SpeechBackend
    }

    package struct JobRecord {
        let jobID: String
        let op: String
        let profileName: String?
        let profileMutation: ProfileMutationExpectation?
        let runtimeBackendSwitch: RuntimeBackendSwitchExpectation?
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
    var networkAudioReceiverConfig: NetworkAudioReceiverConfig
    let runtime: any SpeakSwiftlyRuntimeServing
    let runtimeStartupConfigurationStore: RuntimeStartupConfigurationStore
    let state: any ServerHostStatePublishing
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
    var activeDuckMediaVolume: SpeakSwiftly.DuckMediaVolume

    var statusTask: Task<Void, Never>?
    var playbackTask: Task<Void, Never>?
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
        sequence: nil,
        updatedAt: nil,
        state: SpeakSwiftly.PlaybackState.idle.rawValue,
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil,
        latestEvent: nil,
    )
    var runtimeRefreshSnapshot: RuntimeRefreshSnapshot?
    var transportStatuses = [String: TransportStatusSnapshot]()
    var recentErrors = [RecentErrorSnapshot]()
    var nextRuntimeRefreshSequenceID = 1
    var pendingRuntimeRefresh = true
    var jobs = [String: JobRecord]()
    var hasRequestedStartupProfileRefresh = false
    var isRunningStartupProfileRefresh = false

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
        networkAudioReceiverConfig: NetworkAudioReceiverConfig? = nil,
        runtime: any SpeakSwiftlyRuntimeServing,
        runtimeStartupConfigurationStore: RuntimeStartupConfigurationStore = .init(),
        activeRuntimeSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        activeDuckMediaVolume: SpeakSwiftly.DuckMediaVolume? = nil,
        state: any ServerHostStatePublishing,
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
            title: "Speak Swiftly",
        )
        self.networkAudioReceiverConfig = networkAudioReceiverConfig ?? .init(
            enabled: false,
            serviceName: "SpeakSwiftly Audio Receiver",
            port: 0,
            sharedToken: nil,
        )
        self.runtime = runtime
        self.runtimeStartupConfigurationStore = runtimeStartupConfigurationStore
        self.activeRuntimeSpeechBackend = activeRuntimeSpeechBackend
            ?? runtimeStartupConfigurationStore.initialActiveRuntimeSpeechBackend()
        self.activeDuckMediaVolume = activeDuckMediaVolume
            ?? runtimeStartupConfigurationStore.initialActiveDuckMediaVolume()
        activeDefaultVoiceProfileName = runtimeStartupConfigurationStore.initialActiveDefaultVoiceProfileName(
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        self.state = state
        transportStatuses = Self.initialTransportStatuses(
            httpConfig: self.httpConfig,
            mcpConfig: self.mcpConfig,
            networkAudioReceiverConfig: self.networkAudioReceiverConfig,
        )
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

    package static func makeLive(
        appConfig: AppConfig,
        state: any ServerHostStatePublishing,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        configurationURL: URL? = nil,
        profileRootURL: URL? = nil,
    ) async -> ServerHost {
        let runtimeStartupConfigurationStore = RuntimeStartupConfigurationStore(
            environment: environment,
            configurationURL: configurationURL,
            profileRootURL: profileRootURL,
        )
        let startupConfiguration = runtimeStartupConfigurationStore.startupConfiguration(
            configuredDefaultVoiceProfileName: appConfig.runtime.defaultVoiceProfileName
                ?? appConfig.server.defaultVoiceProfileName,
        )
        let runtime = await SpeakSwiftlyRuntimeAdapter(
            runtime: SpeakSwiftly.liftoff(
                configuration: startupConfiguration,
                stateRootURL: runtimeStartupConfigurationStore.runtimeStateRootURL(),
            ),
        )
        return ServerHost(
            configuration: appConfig.server,
            httpConfig: appConfig.http,
            mcpConfig: appConfig.mcp,
            networkAudioReceiverConfig: appConfig.networkAudioReceiver,
            runtime: runtime,
            runtimeStartupConfigurationStore: runtimeStartupConfigurationStore,
            activeRuntimeSpeechBackend: startupConfiguration.speechBackend,
            activeDuckMediaVolume: startupConfiguration.duckMediaVolume,
            state: state,
        )
    }
}
