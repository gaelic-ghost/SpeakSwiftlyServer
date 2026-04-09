import AsyncAlgorithms
import Foundation
import Hummingbird
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Server Host

actor ServerHost {
    private static let mutationRefreshRetryDelays: [Duration] = [
        .milliseconds(50),
        .milliseconds(100),
    ]
    private static let recentErrorLimit = 8

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

    private var configuration: ServerConfiguration
    private var httpConfig: HTTPConfig
    private var mcpConfig: MCPConfig
    private let runtime: any ServerRuntimeProtocol
    private let runtimeConfigurationStore: RuntimeConfigurationStore
    private let state: ServerState
    private let immediatePublishRequests: AsyncStream<Void>
    private let immediatePublishContinuation: AsyncStream<Void>.Continuation
    private let coalescedPublishRequests: AsyncStream<Void>
    private let coalescedPublishContinuation: AsyncStream<Void>.Continuation
    private let publishedStateContinuation: AsyncStream<HostStateSnapshot>.Continuation
    private let makeSharedStateUpdates: @Sendable () -> AsyncStream<HostStateSnapshot>
    private let hostEventContinuation: AsyncStream<HostEvent>.Continuation
    private let makeSharedHostEvents: @Sendable () -> AsyncStream<HostEvent>
    private let encoder = JSONEncoder()
    private let byteBufferAllocator = ByteBufferAllocator()

    private var statusTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?
    private var publishTask: Task<Void, Never>?
    private var workerMode = "starting"
    private var workerStage = "starting"
    private var startupError: String?
    private var profileCache = [ProfileSnapshot]()
    private var profileCacheState = "uninitialized"
    private var profileCacheWarning: String?
    private var lastProfileRefreshAt: Date?
    private var generationQueueStatus = QueueStatusSnapshot(queueType: "generation", activeCount: 0, queuedCount: 0, activeRequest: nil)
    private var playbackQueueStatus = QueueStatusSnapshot(queueType: "playback", activeCount: 0, queuedCount: 0, activeRequest: nil)
    private var playbackStatus = PlaybackStatusSnapshot(state: SpeakSwiftly.PlaybackState.idle.rawValue, activeRequest: nil)
    private var transportStatuses = [String: TransportStatusSnapshot]()
    private var recentErrors = [RecentErrorSnapshot]()
    private var latestPublishedState: HostStateSnapshot?
    private var pendingRuntimeRefresh = true
    private var jobs = [String: JobRecord]()
    private var hasRequestedStartupProfileRefresh = false

    // MARK: - Construction

    static func live(appConfig: AppConfig, state: ServerState) async -> ServerHost {
        let runtimeConfigurationStore = RuntimeConfigurationStore()
        let runtime = ServerRuntimeAdapter(runtime: await SpeakSwiftly.liftoff())
        let host = ServerHost(
            configuration: appConfig.server,
            httpConfig: appConfig.http,
            mcpConfig: appConfig.mcp,
            runtime: runtime,
            runtimeConfigurationStore: runtimeConfigurationStore,
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
            generationQueue: generationQueueStatus,
            playbackQueue: playbackQueueStatus,
            playback: playbackStatus,
            currentGenerationJob: currentGenerationJobSnapshot(),
            runtimeConfiguration: runtimeConfigurationStore.snapshot(),
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

    // MARK: - Public Query Surface

    func statusSnapshot() -> StatusSnapshot {
        let hostState = hostStateSnapshot()
        let overview = hostState.overview
        return .init(
            service: overview.service,
            environment: overview.environment,
            serverMode: overview.serverMode,
            workerMode: overview.workerMode,
            workerStage: overview.workerStage,
            profileCacheState: overview.profileCacheState,
            profileCacheWarning: overview.profileCacheWarning,
            workerFailureSummary: overview.startupError,
            cachedProfiles: profileCache,
            lastProfileRefreshAt: overview.lastProfileRefreshAt,
            host: httpConfig.host,
            port: httpConfig.port,
            generationQueue: hostState.generationQueue,
            playbackQueue: hostState.playbackQueue,
            playback: hostState.playback,
            currentGenerationJob: hostState.currentGenerationJob,
            runtimeConfiguration: hostState.runtimeConfiguration,
            transports: hostState.transports,
            recentErrors: hostState.recentErrors
        )
    }

    func runtimeConfigurationSnapshot() -> RuntimeConfigurationSnapshot {
        runtimeConfigurationStore.snapshot()
    }

    func saveRuntimeConfiguration(
        speechBackend: SpeakSwiftly.SpeechBackend
    ) async throws -> RuntimeConfigurationSnapshot {
        let snapshot = try runtimeConfigurationStore.save(speechBackend: speechBackend)
        emitRuntimeConfigurationChanged(snapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return snapshot
    }

    func cachedProfiles() -> [ProfileSnapshot] {
        profileCache
    }

    func cachedProfile(_ profileName: String) -> ProfileSnapshot? {
        profileCache.first { $0.profileName == profileName }
    }

    func textProfilesSnapshot() async -> TextProfilesSnapshot {
        .init(
            persistenceURL: await runtime.textProfilePersistenceURL()?.path,
            baseProfile: .init(profile: await runtime.baseTextProfile()),
            activeProfile: .init(profile: await runtime.activeTextProfile()),
            storedProfiles: (await runtime.textProfiles()).map(TextProfileSnapshot.init(profile:)),
            effectiveProfile: .init(profile: await runtime.effectiveTextProfile(id: nil))
        )
    }

    func storedTextProfile(_ profileID: String) async -> TextProfileSnapshot? {
        await runtime.textProfile(id: profileID).map(TextProfileSnapshot.init(profile:))
    }

    func effectiveTextProfile(_ profileID: String?) async -> TextProfileSnapshot {
        .init(profile: await runtime.effectiveTextProfile(id: profileID))
    }

    func createTextProfile(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement]
    ) async throws -> TextProfileSnapshot {
        let profile = try await runtime.createTextProfile(id: id, named: name, replacements: replacements)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func loadTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.loadTextProfiles()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func saveTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.saveTextProfiles()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws -> TextProfileSnapshot {
        try await runtime.storeTextProfile(profile)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws -> TextProfileSnapshot {
        try await runtime.useTextProfile(profile)
        let activeProfile = await runtime.activeTextProfile()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: activeProfile)
    }

    func removeTextProfile(named profileID: String) async throws -> TextProfilesSnapshot {
        try await runtime.removeTextProfile(id: profileID)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func resetTextProfile() async throws -> TextProfileSnapshot {
        try await runtime.resetTextProfile()
        let activeProfile = await runtime.activeTextProfile()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: activeProfile)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileNamed profileID: String? = nil
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile
        if let profileID {
            profile = try await runtime.addTextReplacement(replacement, toStoredTextProfileID: profileID)
        } else {
            profile = try await runtime.addTextReplacement(replacement)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileNamed profileID: String? = nil
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile
        if let profileID {
            profile = try await runtime.replaceTextReplacement(replacement, inStoredTextProfileID: profileID)
        } else {
            profile = try await runtime.replaceTextReplacement(replacement)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileNamed profileID: String? = nil
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile
        if let profileID {
            profile = try await runtime.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID)
        } else {
            profile = try await runtime.removeTextReplacement(id: replacementID)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func jobSnapshots() -> [JobSnapshot] {
        pruneCompletedJobs()
        return jobs.values
            .sorted { lhs, rhs in
                if lhs.submittedAt == rhs.submittedAt {
                    return lhs.jobID > rhs.jobID
                }
                return lhs.submittedAt > rhs.submittedAt
            }
            .map(\.snapshot)
    }

    func generationJobs() async throws -> [SpeakSwiftly.GenerationJob] {
        let handle = await runtime.generationJobs()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-jobs request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing retained generation jobs."
        )
        return success.generationJobs ?? []
    }

    func generationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.generationJob(id: jobID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading retained generation job '\(jobID)'."
        )
        guard let generationJob = success.generationJob else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job request for '\(jobID)', but it did not return a generation_job payload."
            )
        }
        return generationJob
    }

    func expireGenerationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.expireGenerationJob(id: jobID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job expiry request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while expiring retained generation job '\(jobID)'."
        )
        guard let generationJob = success.generationJob else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job expiry request for '\(jobID)', but it did not return a generation_job payload."
            )
        }
        return generationJob
    }

    func generatedFiles() async throws -> [SpeakSwiftly.GeneratedFile] {
        let handle = await runtime.generatedFiles()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generated-files request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing generated audio files."
        )
        return success.generatedFiles ?? []
    }

    func generatedFile(id artifactID: String) async throws -> SpeakSwiftly.GeneratedFile {
        let handle = await runtime.generatedFile(id: artifactID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generated-file request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading generated audio file '\(artifactID)'."
        )
        guard let generatedFile = success.generatedFile else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generated-file request for '\(artifactID)', but it did not return a generated_file payload."
            )
        }
        return generatedFile
    }

    func generatedBatches() async throws -> [SpeakSwiftly.GeneratedBatch] {
        let handle = await runtime.generatedBatches()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generated-batches request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing generated audio batches."
        )
        return success.generatedBatches ?? []
    }

    func generatedBatch(id batchID: String) async throws -> SpeakSwiftly.GeneratedBatch {
        let handle = await runtime.generatedBatch(id: batchID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generated-batch request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading generated audio batch '\(batchID)'."
        )
        guard let generatedBatch = success.generatedBatch else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generated-batch request for '\(batchID)', but it did not return a generated_batch payload."
            )
        }
        return generatedBatch
    }

    func currentWorkerStatusEvent() -> ServerJobEvent {
        .workerStatus(
            .init(
                stage: workerStage,
                workerMode: workerMode
            )
        )
    }

    func runtimeStatus() async throws -> RuntimeStatusResponse {
        let handle = await runtime.runtimeStatus()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the runtime-status request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading runtime status."
        )
        guard let status = success.status else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the runtime-status request, but it did not return a status payload."
            )
        }
        return .init(status: status)
    }

    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async throws -> RuntimeBackendResponse {
        let handle = await runtime.switchSpeechBackend(to: speechBackend)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the speech-backend switch request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while switching the active speech backend."
        )
        guard let resolvedSpeechBackend = success.speechBackend else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the speech-backend switch request, but it did not return a speech_backend payload."
            )
        }
        return .init(speechBackend: resolvedSpeechBackend.rawValue)
    }

    func reloadModels() async throws -> RuntimeStatusResponse {
        try await runtimeStatusResponse(
            handle: await runtime.reloadModels(),
            requestName: "reload-models"
        )
    }

    func unloadModels() async throws -> RuntimeStatusResponse {
        try await runtimeStatusResponse(
            handle: await runtime.unloadModels(),
            requestName: "unload-models"
        )
    }

    // MARK: - Job Submission

    func submitGenerateSpeechLive(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.generateSpeechLive(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return await enqueuePublicJob(handle)
    }

    func submitGenerateAudioFile(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.generateAudioFile(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return await enqueuePublicJob(handle)
    }

    func submitGenerateAudioBatch(
        items: [SpeakSwiftly.BatchItem],
        profileName: String
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.generateAudioBatch(items, with: profileName)
        return await enqueuePublicJob(handle)
    }

    func submitCreateVoiceProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.createVoiceProfile(
            named: profileName,
            vibe: vibe,
            from: text,
            voice: voiceDescription,
            outputPath: outputPath,
            cwd: cwd
        )
        return await enqueuePublicJob(handle)
    }

    func submitCloneVoiceProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.cloneVoiceProfile(
            named: profileName,
            vibe: vibe,
            from: referenceAudioPath,
            transcript: transcript,
            cwd: cwd
        )
        return await enqueuePublicJob(handle)
    }

    func submitDeleteVoiceProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.deleteVoiceProfile(named: profileName)
        return await enqueuePublicJob(handle)
    }

    // MARK: - Immediate Control Operations

    func queueSnapshot(queueType: RuntimeQueueType) async throws -> QueueSnapshotResponse {
        let handle = await runtime.queue(queueType)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        return .init(
            queueType: queueTypeName(queueType),
            activeRequest: success.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
            queue: success.queue?.map(QueuedRequestSnapshot.init(summary:)) ?? []
        )
    }

    func playbackStateSnapshot() async throws -> PlaybackStateResponse {
        try await playbackStateResponse(for: .state)
    }

    func pausePlayback() async throws -> PlaybackStateResponse {
        try await playbackStateResponse(for: .pause)
    }

    func resumePlayback() async throws -> PlaybackStateResponse {
        try await playbackStateResponse(for: .resume)
    }

    func clearQueue() async throws -> QueueClearedResponse {
        let handle = await runtime.clearQueue()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        return .init(clearedCount: success.clearedCount ?? 0)
    }

    func cancelQueuedOrActiveRequest(requestID: String) async throws -> QueueCancellationResponse {
        let handle = await runtime.cancelRequest(requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        guard let cancelledRequestID = success.cancelledRequestID, !cancelledRequestID.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the cancel-request control operation, but it did not report which request was cancelled."
            )
        }
        return .init(cancelledRequestID: cancelledRequestID)
    }

    // MARK: - Job Inspection and SSE

    func jobSnapshot(id: String) throws -> JobSnapshot {
        pruneCompletedJobs()
        guard let job = jobs[id] else {
            throw HTTPError(
                .notFound,
                message: "Request '\(id)' was not found in the shared server request cache. It may be unknown or may have expired from in-memory retention."
            )
        }
        return job.snapshot
    }

    func sseStream(for jobID: String) throws -> AsyncStream<ByteBuffer> {
        pruneCompletedJobs()
        let updates = eventUpdates()
        guard let job = jobs[jobID] else {
            throw HTTPError(
                .notFound,
                message: "Request '\(jobID)' was not found in the shared server request cache. It may be unknown or may have expired from in-memory retention."
            )
        }

        let history = job.history
        let terminalEvent = job.terminalEvent
        let workerStatusEvent = currentWorkerStatusEvent()
        let replayedHistoryCount = history.count

        return AsyncStream { continuation in
            continuation.yield(self.encodeSSEBuffer(for: workerStatusEvent))
            for event in history {
                continuation.yield(self.encodeSSEBuffer(for: event))
            }

            if terminalEvent != nil {
                continuation.finish()
                return
            }

            let heartbeatTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(self.configuration.sseHeartbeatSeconds))
                    continuation.yield(self.encodeHeartbeatBuffer())
                }
            }

            let eventTask = Task {
                var iterator = updates.makeAsyncIterator()
                var lastDeliveredHistoryIndex = replayedHistoryCount

                while !Task.isCancelled, let update = await iterator.next() {
                    guard case .jobEvent(let jobUpdate) = update else {
                        continue
                    }
                    guard jobUpdate.jobID == jobID else {
                        continue
                    }
                    guard jobUpdate.historyIndex > lastDeliveredHistoryIndex else {
                        continue
                    }

                    lastDeliveredHistoryIndex = jobUpdate.historyIndex
                    continuation.yield(self.encodeSSEBuffer(for: jobUpdate.event))

                    if jobUpdate.terminal {
                        continuation.finish()
                        break
                    }
                }
            }

            continuation.onTermination = { _ in
                heartbeatTask.cancel()
                eventTask.cancel()
            }
        }
    }

    private var serverMode: String {
        if workerMode == "ready", profileCacheState != "stale" {
            "ready"
        } else {
            "degraded"
        }
    }

    private func ensureWorkerReady() throws {
        guard workerMode == "ready" else {
            throw HTTPError(
                .serviceUnavailable,
                message: startupError ?? "SpeakSwiftly is not ready yet, so the server cannot accept new work right now."
            )
        }
    }

    private func enqueuePublicJob(_ handle: RuntimeRequestHandle) async -> String {
        jobs[handle.id] = JobRecord(
            jobID: handle.id,
            op: handle.operation,
            profileName: handle.profileName,
            submittedAt: Date()
        )

        Task {
            await self.consume(handle: handle)
        }
        await requestPublish(mode: .coalesced, refreshRuntimeState: true)
        return handle.id
    }

    // MARK: - Job Event Consumption

    private func consume(handle: RuntimeRequestHandle) async {
        do {
            for try await event in handle.events {
                switch event {
                case .queued(let queued):
                    await record(mapQueuedEvent(queued), for: handle.id, terminal: false)
                case .acknowledged(let success):
                    await record(mapSuccessEvent(success, acknowledged: true), for: handle.id, terminal: false)
                case .started(let started):
                    await record(mapStartedEvent(started), for: handle.id, terminal: false)
                case .progress(let progress):
                    await record(mapProgressEvent(progress), for: handle.id, terminal: false)
                case .completed(let success):
                    if handle.operation == "create_voice_profile"
                        || handle.operation == "clone_voice_profile"
                        || handle.operation == "delete_voice_profile"
                    {
                        await finalizeMutationSuccess(
                            success: success,
                            requestID: handle.id,
                            operationName: handle.operation
                        )
                    } else if handle.operation == "list_voice_profiles" {
                        await applyProfileRefresh(from: success)
                        await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                    } else {
                        await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                    }
                }
            }
        } catch let error as SpeakSwiftly.Error {
            let failure = ServerFailureEvent(id: handle.id, code: error.code.rawValue, message: error.message)
            await record(.failed(failure), for: handle.id, terminal: true)
        } catch {
            let failure = ServerFailureEvent(
                id: handle.id,
                code: SpeakSwiftly.ErrorCode.internalError.rawValue,
                message: "SpeakSwiftly request '\(handle.id)' failed unexpectedly while the server was monitoring its typed event stream. \(error.localizedDescription)"
            )
            await record(.failed(failure), for: handle.id, terminal: true)
        }
    }

    // MARK: - Profile Cache Reconciliation

    private func finalizeMutationSuccess(
        success: SpeakSwiftly.Success,
        requestID: String,
        operationName: String
    ) async {
        do {
            let previousProfiles = profileCache
            let profiles = try await reconcileProfilesAfterMutation(
                op: operationName,
                requestID: requestID,
                success: success,
                previousProfiles: previousProfiles
            )
            self.profileCache = profiles
            self.profileCacheState = "fresh"
            self.profileCacheWarning = nil
            let finalSuccess = ServerSuccessEvent(
                id: success.id,
                generatedFile: success.generatedFile,
                generatedFiles: success.generatedFiles,
                generatedBatch: success.generatedBatch,
                generatedBatches: success.generatedBatches,
                generationJob: success.generationJob,
                generationJobs: success.generationJobs,
                profileName: success.profileName,
                profilePath: success.profilePath,
                profiles: nil,
                textProfile: success.textProfile.map(TextProfileSnapshot.init(profile:)),
                textProfiles: success.textProfiles?.map(TextProfileSnapshot.init(profile:)),
                textProfilePath: success.textProfilePath,
                activeRequest: success.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
                queue: success.queue?.map(QueuedRequestSnapshot.init(summary:)),
                playbackState: success.playbackState.map(PlaybackStateSnapshot.init(summary:)),
                status: success.status,
                speechBackend: success.speechBackend?.rawValue,
                clearedCount: success.clearedCount,
                cancelledRequestID: success.cancelledRequestID
            )
            await record(.completed(finalSuccess), for: requestID, terminal: true)
        } catch {
            self.profileCacheState = "stale"
            self.profileCacheWarning = "SpeakSwiftly reported a successful profile mutation, but the server could not confirm the refreshed profile list afterward. The cached profile list may be stale. Likely cause: \(error.localizedDescription)"
            emitProfileCacheChanged()
            recordRecentError(
                source: "profile_cache",
                code: "profile_refresh_mismatch",
                message: self.profileCacheWarning ?? "SpeakSwiftly could not reconcile the refreshed profile cache after a successful mutation."
            )
            let failure = ServerFailureEvent(
                id: requestID,
                code: "profile_refresh_mismatch",
                message: "SpeakSwiftly reported success, but the server could not confirm the profile list changed as expected after the mutation."
            )
            await record(.failed(failure), for: requestID, terminal: true)
        }
    }

    private func reconcileProfilesAfterMutation(
        op: String,
        requestID: String,
        success: SpeakSwiftly.Success,
        previousProfiles: [ProfileSnapshot]
    ) async throws -> [ProfileSnapshot] {
        guard let profileName = success.profileName, !profileName.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly returned a successful \(op) payload for request '\(requestID)', but it did not include a usable profile name for cache reconciliation."
            )
        }

        let retryDelays = Self.mutationRefreshRetryDelays
        for attempt in 0...retryDelays.count {
            let refreshedProfiles = try await refreshProfiles(reason: "\(op):\(requestID):\(attempt)")
            if profilesMatchExpectedMutation(
                op: op,
                profileName: profileName,
                previousProfiles: previousProfiles,
                refreshedProfiles: refreshedProfiles
            ) {
                return refreshedProfiles
            }

            if attempt < retryDelays.count {
                try await Task.sleep(for: retryDelays[attempt])
            }
        }

        throw SpeakSwiftly.Error(
            code: .internalError,
            message: "SpeakSwiftly refreshed the profile cache after \(op) for profile '\(profileName)', but the list still did not reflect the expected mutation."
        )
    }

    private func refreshProfiles(reason: String) async throws -> [ProfileSnapshot] {
        let handle = await runtime.voiceProfiles()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the internal list_voice_profiles request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing cached profiles."
        )
        let profiles = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        self.profileCache = profiles
        self.lastProfileRefreshAt = Date()
        self.profileCacheState = "fresh"
        self.profileCacheWarning = nil
        emitProfileCacheChanged()
        _ = reason
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return profiles
    }

    private func applyProfileRefresh(from success: SpeakSwiftly.Success) async {
        self.profileCache = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        self.lastProfileRefreshAt = Date()
        self.profileCacheState = "fresh"
        self.profileCacheWarning = nil
        emitProfileCacheChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    private func profilesMatchExpectedMutation(
        op: String,
        profileName: String,
        previousProfiles: [ProfileSnapshot],
        refreshedProfiles: [ProfileSnapshot]
    ) -> Bool {
        let previousNames = Set(previousProfiles.map(\.profileName))
        let refreshedNames = Set(refreshedProfiles.map(\.profileName))

        switch op {
        case "create_voice_profile":
            return refreshedNames.contains(profileName) && refreshedNames != previousNames
        case "clone_voice_profile":
            return refreshedNames.contains(profileName) && refreshedNames != previousNames
        case "delete_voice_profile":
            return !refreshedNames.contains(profileName) && refreshedNames != previousNames
        default:
            return false
        }
    }

    // MARK: - Worker Status Handling

    private func handle(status: SpeakSwiftly.StatusEvent) async {
        switch status.stage {
        case .warmingResidentModel:
            self.workerMode = "starting"
            self.workerStage = status.stage.rawValue
            self.startupError = nil
        case .residentModelReady:
            self.workerMode = "ready"
            self.workerStage = status.stage.rawValue
            self.startupError = nil
            if !hasRequestedStartupProfileRefresh {
                hasRequestedStartupProfileRefresh = true
                do {
                    _ = try await refreshProfiles(reason: "startup")
                } catch {
                    self.profileCacheState = "stale"
                    self.profileCacheWarning = "SpeakSwiftly became ready, but the server could not refresh the initial profile cache. Likely cause: \(error.localizedDescription)"
                    emitProfileCacheChanged()
                }
            }
        case .residentModelsUnloaded:
            self.workerMode = "starting"
            self.workerStage = status.stage.rawValue
            self.startupError = nil
        case .residentModelFailed:
            self.workerMode = "failed"
            self.workerStage = status.stage.rawValue
            self.startupError = "SpeakSwiftly reported resident model startup failure."
            recordRecentError(
                source: "worker",
                code: "resident_model_failed",
                message: self.startupError ?? "SpeakSwiftly reported resident model startup failure."
            )
        }

        let event = currentWorkerStatusEvent()
        for (jobID, job) in jobs where job.terminalEvent == nil {
            await record(event, for: jobID, terminal: false)
        }
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    private func record(_ event: ServerJobEvent, for jobID: String, terminal: Bool) async {
        guard var job = jobs[jobID] else { return }
        job.latestEvent = event
        if job.startedAt == nil, case .started = event {
            job.startedAt = Date()
        }
        job.history.append(event)
        let historyIndex = job.history.count
        if terminal {
            job.terminalEvent = event
            job.terminalAt = Date()
        }
        jobs[jobID] = job
        hostEventContinuation.yield(.jobChanged(job.snapshot))
        hostEventContinuation.yield(
            .jobEvent(
                .init(
                    jobID: jobID,
                    event: event,
                    historyIndex: historyIndex,
                    terminal: terminal
                )
            )
        )

        if terminal {
            if case .failed(let failure) = event {
                recordRecentError(
                    source: "job:\(job.op)",
                    code: failure.code,
                    message: failure.message
                )
            }
            pruneCompletedJobs()
        }
        await requestPublish(mode: terminal ? .immediate : .coalesced, refreshRuntimeState: true)
    }

    private func pruneCompletedJobs() {
        let now = Date()
        let expiredIDs = jobs.compactMap { jobID, job -> String? in
            guard let terminalAt = job.terminalAt else { return nil }
            let age = now.timeIntervalSince(terminalAt)
            return age > configuration.completedJobTTLSeconds ? jobID : nil
        }
        for jobID in expiredIDs {
            jobs.removeValue(forKey: jobID)
        }

        let completed = jobs.values
            .filter { $0.terminalAt != nil }
            .sorted { lhs, rhs in
                let lhsTerminalAt = lhs.terminalAt ?? .distantPast
                let rhsTerminalAt = rhs.terminalAt ?? .distantPast
                if lhsTerminalAt == rhsTerminalAt {
                    return lhs.submittedAt < rhs.submittedAt
                }
                return lhsTerminalAt < rhsTerminalAt
            }
        let overflow = completed.count - configuration.completedJobMaxCount
        guard overflow > 0 else { return }
        for job in completed.prefix(overflow) {
            jobs.removeValue(forKey: job.jobID)
        }
    }

    // MARK: - Publish Flow

    private func requestPublish(mode: PublishMode, refreshRuntimeState: Bool) async {
        pendingRuntimeRefresh = pendingRuntimeRefresh || refreshRuntimeState
        switch mode {
        case .immediate:
            immediatePublishContinuation.yield(())
        case .coalesced:
            coalescedPublishContinuation.yield(())
        }
    }

    private func publishState() async {
        let shouldRefreshRuntimeState = pendingRuntimeRefresh
        pendingRuntimeRefresh = false
        if shouldRefreshRuntimeState {
            await refreshRuntimeDerivedState()
        }

        let hostState = hostStateSnapshot()
        let jobsByID = Dictionary(uniqueKeysWithValues: jobs.map { ($0.key, $0.value.snapshot) })
        latestPublishedState = hostState

        publishedStateContinuation.yield(hostState)

        await MainActor.run {
            state.overview = hostState.overview
            state.generationQueue = hostState.generationQueue
            state.playbackQueue = hostState.playbackQueue
            state.playback = hostState.playback
            state.currentGenerationJob = hostState.currentGenerationJob
            state.runtimeConfiguration = hostState.runtimeConfiguration
            state.transports = hostState.transports
            state.recentErrors = hostState.recentErrors
            state.jobsByID = jobsByID
        }
    }

    // MARK: - Runtime-Derived State

    private func refreshRuntimeDerivedState() async {
        let previousPlaybackStatus = playbackStatus
        guard workerMode == "ready" else {
            generationQueueStatus = deriveGenerationQueueStatusFallback()
            playbackQueueStatus = derivePlaybackQueueStatusFallback()
            playbackStatus = derivePlaybackStatusFallback()
            if playbackStatus != previousPlaybackStatus {
                hostEventContinuation.yield(.playbackChanged(playbackStatus))
            }
            return
        }

        do {
            generationQueueStatus = try await fetchQueueStatus(.generation)
        } catch {
            recordRecentError(
                source: "queue:generation",
                code: "queue_snapshot_failed",
                message: "SpeakSwiftlyServer could not refresh the generation queue snapshot. Likely cause: \(error.localizedDescription)"
            )
            generationQueueStatus = deriveGenerationQueueStatusFallback()
        }

        do {
            playbackQueueStatus = try await fetchQueueStatus(.playback)
        } catch {
            recordRecentError(
                source: "queue:playback",
                code: "queue_snapshot_failed",
                message: "SpeakSwiftlyServer could not refresh the playback queue snapshot. Likely cause: \(error.localizedDescription)"
            )
            playbackQueueStatus = derivePlaybackQueueStatusFallback()
        }

        do {
            playbackStatus = try await fetchPlaybackStatus()
        } catch {
            recordRecentError(
                source: "playback",
                code: "playback_state_failed",
                message: "SpeakSwiftlyServer could not refresh the playback state snapshot. Likely cause: \(error.localizedDescription)"
            )
            playbackStatus = derivePlaybackStatusFallback()
        }

        if playbackStatus != previousPlaybackStatus {
            hostEventContinuation.yield(.playbackChanged(playbackStatus))
        }
    }

    // MARK: - Runtime Snapshot Fetches

    private func fetchQueueStatus(_ queueType: RuntimeQueueType) async throws -> QueueStatusSnapshot {
        let handle = await runtime.queue(queueType)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the queue snapshot request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing a queue snapshot."
        )

        let queueName = queueTypeName(queueType)
        return .init(
            queueType: queueName,
            activeCount: success.activeRequest == nil ? 0 : 1,
            queuedCount: success.queue?.count ?? 0,
            activeRequest: success.activeRequest.map(ActiveRequestSnapshot.init(summary:))
        )
    }

    private func fetchPlaybackStatus() async throws -> PlaybackStatusSnapshot {
        let handle = await runtime.playback(.state)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the playback state request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing playback state."
        )
        guard let playbackState = success.playbackState else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the playback state request, but it did not return a playback state payload."
            )
        }

        return .init(
            state: playbackState.state.rawValue,
            activeRequest: playbackState.activeRequest.map(ActiveRequestSnapshot.init(summary:))
        )
    }

    // MARK: - Derived Snapshot Helpers

    private func currentGenerationJobSnapshot() -> CurrentGenerationJobSnapshot? {
        guard let job = currentGenerationJobRecord() else { return nil }
        return .init(
            jobID: job.jobID,
            op: job.op,
            profileName: job.profileName,
            submittedAt: TimestampFormatter.string(from: job.submittedAt),
            startedAt: job.startedAt.map(TimestampFormatter.string(from:)),
            latestStage: latestStage(for: job.latestEvent),
            elapsedGenerationSeconds: job.startedAt.map { max(0, Date().timeIntervalSince($0)) }
        )
    }

    private func currentGenerationJobRecord() -> JobRecord? {
        jobs.values
            .filter { isGenerationOperation($0.op) && $0.terminalEvent == nil }
            .sorted { lhs, rhs in
                generationPriority(for: lhs) > generationPriority(for: rhs)
                    || (
                        generationPriority(for: lhs) == generationPriority(for: rhs)
                        && lhs.submittedAt < rhs.submittedAt
                    )
            }
            .first
    }

    private func currentLiveSpeechJobRecord() -> JobRecord? {
        jobs.values
            .filter { $0.op == "generate_speech_live" && $0.terminalEvent == nil }
            .sorted { lhs, rhs in lhs.submittedAt < rhs.submittedAt }
            .first
    }

    private func generationPriority(for job: JobRecord) -> Int {
        switch job.latestEvent {
        case .progress, .started:
            3
        case .acknowledged:
            2
        case .queued:
            1
        default:
            0
        }
    }

    private func latestStage(for event: ServerJobEvent?) -> String? {
        switch event {
        case .progress(let event):
            event.stage
        case .started(let event):
            event.op
        case .queued(let event):
            event.reason
        default:
            nil
        }
    }

    private func deriveGenerationQueueStatusFallback() -> QueueStatusSnapshot {
        let activeJob = currentGenerationJobRecord()
        let queuedCount = jobs.values.filter {
            guard isGenerationOperation($0.op), $0.terminalEvent == nil else {
                return false
            }
            if case .queued = $0.latestEvent {
                return true
            }
            return false
        }.count

        return .init(
            queueType: "generation",
            activeCount: activeJob == nil ? 0 : 1,
            queuedCount: queuedCount,
            activeRequest: activeJob.map {
                .init(id: $0.jobID, op: $0.op, profileName: $0.profileName)
            }
        )
    }

    private func derivePlaybackQueueStatusFallback() -> QueueStatusSnapshot {
        .init(
            queueType: "playback",
            activeCount: playbackStatus.state == SpeakSwiftly.PlaybackState.idle.rawValue ? 0 : 1,
            queuedCount: 0,
            activeRequest: playbackStatus.activeRequest
        )
    }

    private func derivePlaybackStatusFallback() -> PlaybackStatusSnapshot {
        if let activeRequest = currentLiveSpeechJobRecord().map({
            ActiveRequestSnapshot(id: $0.jobID, op: $0.op, profileName: $0.profileName)
        }) {
            return .init(state: SpeakSwiftly.PlaybackState.playing.rawValue, activeRequest: activeRequest)
        }
        return .init(state: SpeakSwiftly.PlaybackState.idle.rawValue, activeRequest: nil)
    }

    private func transportSnapshots() -> [TransportStatusSnapshot] {
        ["http", "mcp"].compactMap { transportStatuses[$0] }
    }

    private func applyLiveConfigurationChanges(from appConfig: AppConfig) -> Bool {
        var didChange = false
        var shouldPruneCompletedJobs = false

        if configuration.name != appConfig.server.name ||
            configuration.environment != appConfig.server.environment ||
            configuration.sseHeartbeatSeconds != appConfig.server.sseHeartbeatSeconds ||
            configuration.completedJobTTLSeconds != appConfig.server.completedJobTTLSeconds ||
            configuration.completedJobMaxCount != appConfig.server.completedJobMaxCount ||
            configuration.jobPruneIntervalSeconds != appConfig.server.jobPruneIntervalSeconds
        {
            shouldPruneCompletedJobs =
                configuration.completedJobTTLSeconds != appConfig.server.completedJobTTLSeconds ||
                configuration.completedJobMaxCount != appConfig.server.completedJobMaxCount

            configuration = ServerConfiguration(
                name: appConfig.server.name,
                environment: appConfig.server.environment,
                host: configuration.host,
                port: configuration.port,
                sseHeartbeatSeconds: appConfig.server.sseHeartbeatSeconds,
                completedJobTTLSeconds: appConfig.server.completedJobTTLSeconds,
                completedJobMaxCount: appConfig.server.completedJobMaxCount,
                jobPruneIntervalSeconds: appConfig.server.jobPruneIntervalSeconds
            )
            didChange = true
        }

        if shouldPruneCompletedJobs {
            pruneCompletedJobs()
        }

        return didChange
    }

    private func restartRequiredConfigurationKeys(for appConfig: AppConfig) -> [String] {
        var keys = [String]()

        if configuration.host != appConfig.server.host {
            keys.append("app.host")
        }
        if configuration.port != appConfig.server.port {
            keys.append("app.port")
        }
        if httpConfig.enabled != appConfig.http.enabled {
            keys.append("app.http.enabled")
        }
        if httpConfig.host != appConfig.http.host {
            keys.append("app.http.host")
        }
        if httpConfig.port != appConfig.http.port {
            keys.append("app.http.port")
        }
        if httpConfig.sseHeartbeatSeconds != appConfig.http.sseHeartbeatSeconds {
            keys.append("app.http.sseHeartbeatSeconds")
        }
        if mcpConfig.enabled != appConfig.mcp.enabled {
            keys.append("app.mcp.enabled")
        }
        if mcpConfig.path != appConfig.mcp.path {
            keys.append("app.mcp.path")
        }
        if mcpConfig.serverName != appConfig.mcp.serverName {
            keys.append("app.mcp.serverName")
        }
        if mcpConfig.title != appConfig.mcp.title {
            keys.append("app.mcp.title")
        }

        return keys
    }

    // MARK: - Transport and Error Tracking

    private func updateTransportStatus(named name: String, state: String) {
        guard let current = transportStatuses[name], current.enabled else {
            return
        }
        let updated = TransportStatusSnapshot(
            name: current.name,
            enabled: current.enabled,
            state: state,
            host: current.host,
            port: current.port,
            path: current.path,
            advertisedAddress: current.advertisedAddress
        )
        guard updated != current else {
            return
        }
        transportStatuses[name] = updated
        hostEventContinuation.yield(.transportChanged(updated))
    }

    private static func initialTransportStatuses(
        httpConfig: HTTPConfig,
        mcpConfig: MCPConfig
    ) -> [String: TransportStatusSnapshot] {
        let http = TransportStatusSnapshot(
            name: "http",
            enabled: httpConfig.enabled,
            state: httpConfig.enabled ? "stopped" : "disabled",
            host: httpConfig.enabled ? httpConfig.host : nil,
            port: httpConfig.enabled ? httpConfig.port : nil,
            path: nil,
            advertisedAddress: httpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)" : nil
        )
        let mcp = TransportStatusSnapshot(
            name: "mcp",
            enabled: mcpConfig.enabled,
            state: mcpConfig.enabled ? "stopped" : "disabled",
            host: mcpConfig.enabled ? httpConfig.host : nil,
            port: mcpConfig.enabled ? httpConfig.port : nil,
            path: mcpConfig.enabled ? mcpConfig.path : nil,
            advertisedAddress: mcpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)\(mcpConfig.path)" : nil
        )
        return [
            http.name: http,
            mcp.name: mcp,
        ]
    }

    private func recordRecentError(source: String, code: String, message: String) {
        if let last = recentErrors.last,
           last.source == source,
           last.code == code,
           last.message == message
        {
            return
        }
        let snapshot = RecentErrorSnapshot(
            occurredAt: TimestampFormatter.string(from: Date()),
            source: source,
            code: code,
            message: message
        )
        recentErrors.append(snapshot)
        if recentErrors.count > Self.recentErrorLimit {
            recentErrors.removeFirst(recentErrors.count - Self.recentErrorLimit)
        }
        hostEventContinuation.yield(.recentErrorRecorded(snapshot))
    }

    private func emitProfileCacheChanged() {
        hostEventContinuation.yield(
            .profileCacheChanged(
                .init(
                    state: profileCacheState,
                    warning: profileCacheWarning,
                    profileCount: profileCache.count,
                    lastRefreshAt: lastProfileRefreshAt.map(TimestampFormatter.string(from:))
                )
            )
        )
    }

    private func emitTextProfilesChanged() async {
        let activeProfile = await runtime.activeTextProfile()
        let storedProfiles = await runtime.textProfiles()
        hostEventContinuation.yield(
            .textProfilesChanged(
                .init(
                    activeProfileID: activeProfile.id,
                    storedProfileCount: storedProfiles.count,
                    persistenceURL: await runtime.textProfilePersistenceURL()?.path
                )
            )
        )
    }

    private func emitRuntimeConfigurationChanged(_ snapshot: RuntimeConfigurationSnapshot) {
        hostEventContinuation.yield(
            .runtimeConfigurationChanged(
                .init(
                    activeRuntimeSpeechBackend: snapshot.activeRuntimeSpeechBackend,
                    nextRuntimeSpeechBackend: snapshot.nextRuntimeSpeechBackend,
                    persistedSpeechBackend: snapshot.persistedSpeechBackend,
                    environmentSpeechBackendOverride: snapshot.environmentSpeechBackendOverride,
                    persistedConfigurationPath: snapshot.persistedConfigurationPath,
                    persistedConfigurationState: snapshot.persistedConfigurationState
                )
            )
        )
    }

    // MARK: - Event Mapping and Encoding

    private func mapQueuedEvent(_ event: SpeakSwiftly.QueuedEvent) -> ServerJobEvent {
        .queued(
            .init(
                id: event.id,
                reason: event.reason.rawValue,
                queuePosition: event.queuePosition
            )
        )
    }

    private func mapStartedEvent(_ event: SpeakSwiftly.StartedEvent) -> ServerJobEvent {
        .started(.init(id: event.id, op: event.op))
    }

    private func mapProgressEvent(_ event: SpeakSwiftly.ProgressEvent) -> ServerJobEvent {
        .progress(.init(id: event.id, stage: event.stage.rawValue))
    }

    private func mapSuccessEvent(_ event: SpeakSwiftly.Success, acknowledged: Bool) -> ServerJobEvent {
        let success = ServerSuccessEvent(
            id: event.id,
            generatedFile: event.generatedFile,
            generatedFiles: event.generatedFiles,
            generatedBatch: event.generatedBatch,
            generatedBatches: event.generatedBatches,
            generationJob: event.generationJob,
            generationJobs: event.generationJobs,
            profileName: event.profileName,
            profilePath: event.profilePath,
            profiles: event.profiles?.map(ProfileSnapshot.init(profile:)),
            textProfile: event.textProfile.map(TextProfileSnapshot.init(profile:)),
            textProfiles: event.textProfiles?.map(TextProfileSnapshot.init(profile:)),
            textProfilePath: event.textProfilePath,
            activeRequest: event.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
            queue: event.queue?.map(QueuedRequestSnapshot.init(summary:)),
            playbackState: event.playbackState.map(PlaybackStateSnapshot.init(summary:)),
            status: event.status,
            speechBackend: event.speechBackend?.rawValue,
            clearedCount: event.clearedCount,
            cancelledRequestID: event.cancelledRequestID
        )
        return acknowledged ? .acknowledged(success) : .completed(success)
    }

    private func encodeSSEBuffer(for event: ServerJobEvent) -> ByteBuffer {
        let eventName: String = switch event {
        case .workerStatus:
            "worker_status"
        case .queued:
            "queued"
        case .acknowledged, .completed:
            "message"
        case .started:
            "started"
        case .progress:
            "progress"
        case .failed:
            "message"
        }

        let data = (try? encoder.encode(event)) ?? Data(#"{"ok":false,"code":"encoding_error","message":"SpeakSwiftlyServer could not encode an SSE event payload."}"#.utf8)
        var buffer = byteBufferAllocator.buffer(capacity: eventName.utf8.count + data.count + 16)
        buffer.writeString("event: \(eventName)\n")
        buffer.writeString("data: ")
        buffer.writeBytes(data)
        buffer.writeString("\n\n")
        return buffer
    }

    // MARK: - Immediate Control Helpers

    private func encodeHeartbeatBuffer() -> ByteBuffer {
        var buffer = byteBufferAllocator.buffer(capacity: 15)
        buffer.writeString(": keep-alive\n\n")
        return buffer
    }

    private func playbackStateResponse(for action: RuntimePlaybackAction) async throws -> PlaybackStateResponse {
        let handle = await runtime.playback(action)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        guard let playbackState = success.playbackState else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the '\(requestName(for: action))' control request, but it did not return a playback state payload."
            )
        }
        return .init(playback: .init(summary: playbackState))
    }

    private func requestName(for action: RuntimePlaybackAction) -> String {
        switch action {
        case .pause:
            "pause-playback"
        case .resume:
            "resume-playback"
        case .state:
            "playback-state"
        }
    }

    private func queueTypeName(_ queueType: RuntimeQueueType) -> String {
        switch queueType {
        case .generation:
            "generation"
        case .playback:
            "playback"
        }
    }

    private func isGenerationOperation(_ operation: String) -> Bool {
        operation == "generate_speech_live"
            || operation == "generate_audio_file"
            || operation == "generate_audio_batch"
    }

    private func runtimeStatusResponse(
        handle: RuntimeRequestHandle,
        requestName: String
    ) async throws -> RuntimeStatusResponse {
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the \(requestName) request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the \(requestName) request."
        )
        guard let status = success.status else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the \(requestName) request, but it did not return a status payload."
            )
        }
        return .init(status: status)
    }

    private func awaitImmediateSuccess(
        handle: RuntimeRequestHandle,
        missingTerminalMessage: String,
        unexpectedFailureMessagePrefix: String
    ) async throws -> SpeakSwiftly.Success {
        do {
            for try await event in handle.events {
                if case .completed(let success) = event {
                    return success
                }
            }
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: missingTerminalMessage
            )
        } catch let error as SpeakSwiftly.Error {
            throw error
        } catch {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "\(unexpectedFailureMessagePrefix) \(error.localizedDescription)"
            )
        }
    }
}
