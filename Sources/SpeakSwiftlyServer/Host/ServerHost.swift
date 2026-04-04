import AsyncAlgorithms
import Foundation
import Hummingbird
import SpeakSwiftlyCore

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
        var subscribers: [UUID: AsyncStream<ByteBuffer>.Continuation] = [:]
        var heartbeatTasks: [UUID: Task<Void, Never>] = [:]

        var snapshot: JobSnapshot {
            .init(
                jobID: jobID,
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

    private let configuration: ServerConfiguration
    private let httpConfig: HTTPConfig
    private let mcpConfig: MCPConfig
    private let runtime: any ServerRuntimeProtocol
    private let state: ServerState
    private let immediatePublishRequests: AsyncStream<Void>
    private let immediatePublishContinuation: AsyncStream<Void>.Continuation
    private let coalescedPublishRequests: AsyncStream<Void>
    private let coalescedPublishContinuation: AsyncStream<Void>.Continuation
    private let publishedStateContinuation: AsyncStream<HostStateSnapshot>.Continuation
    private let makeSharedStateUpdates: @Sendable () -> AsyncStream<HostStateSnapshot>
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
    private var playbackStatus = PlaybackStatusSnapshot(state: PlaybackState.idle.rawValue, activeRequest: nil)
    private var recentErrors = [RecentErrorSnapshot]()
    private var latestPublishedState: HostStateSnapshot?
    private var pendingRuntimeRefresh = true
    private var jobs = [String: JobRecord]()
    private var hasRequestedStartupProfileRefresh = false

    static func live(appConfig: AppConfig, state: ServerState) async -> ServerHost {
        let runtime = await WorkerRuntime.live()
        let host = ServerHost(
            configuration: appConfig.server,
            httpConfig: appConfig.http,
            mcpConfig: appConfig.mcp,
            runtime: runtime,
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
        let sharedPublishedStates = publishedStateStream.share(bufferingPolicy: .bufferingLatest(1))

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
            serverName: "speak-to-user-mcp",
            title: "SpeakSwiftlyMCP"
        )
        self.runtime = runtime
        self.state = state
        self.immediatePublishRequests = immediatePublishRequests
        self.immediatePublishContinuation = immediatePublishContinuation
        self.coalescedPublishRequests = coalescedPublishRequests
        self.coalescedPublishContinuation = coalescedPublishContinuation
        self.publishedStateContinuation = publishedStateContinuation
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
        self.encoder.outputFormatting = [.sortedKeys]
    }

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

        for jobID in jobs.keys {
            finishSubscribers(for: jobID)
        }
        pendingRuntimeRefresh = false
        await publishState()
        self.publishTask?.cancel()
        immediatePublishContinuation.finish()
        coalescedPublishContinuation.finish()
        publishedStateContinuation.finish()
    }

    func stateUpdates() -> AsyncStream<HostStateSnapshot> {
        let sharedUpdates = makeSharedStateUpdates()
        let latestPublishedState = self.latestPublishedState
        return AsyncStream { continuation in
            if let latestPublishedState {
                continuation.yield(latestPublishedState)
            }

            let task = Task {
                for await snapshot in sharedUpdates {
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

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
            transports: transportSnapshots(),
            recentErrors: recentErrors
        )
    }

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
            transports: hostState.transports,
            recentErrors: hostState.recentErrors
        )
    }

    func cachedProfiles() -> [ProfileSnapshot] {
        profileCache
    }

    func currentWorkerStatusEvent() -> ServerJobEvent {
        .workerStatus(
            .init(
                stage: workerStage,
                workerMode: workerMode
            )
        )
    }

    func submitSpeak(text: String, profileName: String) async throws -> String {
        try ensureWorkerReady()
        let requestID = UUID().uuidString
        let handle = await runtime.queueSpeechHandle(text: text, profileName: profileName, as: .live, id: requestID)
        return await enqueuePublicJob(handle)
    }

    func submitCreateProfile(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?
    ) async throws -> String {
        try ensureWorkerReady()
        let requestID = UUID().uuidString
        let handle = await runtime.createProfileHandle(
            profileName: profileName,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            id: requestID
        )
        return await enqueuePublicJob(handle)
    }

    func submitRemoveProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let requestID = UUID().uuidString
        let handle = await runtime.removeProfileHandle(profileName: profileName, id: requestID)
        return await enqueuePublicJob(handle)
    }

    func queueSnapshot(queueType: WorkerQueueType) async throws -> QueueSnapshotResponse {
        let requestID = UUID().uuidString
        let handle = await runtime.listQueueHandle(queueType, id: requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operationName)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operationName)' control request."
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
        let requestID = UUID().uuidString
        let handle = await runtime.clearQueueHandle(id: requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operationName)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operationName)' control request."
        )
        return .init(clearedCount: success.clearedCount ?? 0)
    }

    func cancelQueuedOrActiveRequest(requestID: String) async throws -> QueueCancellationResponse {
        let controlRequestID = UUID().uuidString
        let handle = await runtime.cancelRequestHandle(with: requestID, requestID: controlRequestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operationName)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operationName)' control request."
        )
        guard let cancelledRequestID = success.cancelledRequestID, !cancelledRequestID.isEmpty else {
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly accepted the cancel_request control operation, but it did not report which request was cancelled."
            )
        }
        return .init(cancelledRequestID: cancelledRequestID)
    }

    func jobSnapshot(id: String) throws -> JobSnapshot {
        pruneCompletedJobs()
        guard let job = jobs[id] else {
            throw HTTPError(
                .notFound,
                message: "Job '\(id)' was not found in the server request cache. It may be unknown or may have expired from in-memory retention."
            )
        }
        return job.snapshot
    }

    func sseStream(for jobID: String) throws -> AsyncStream<ByteBuffer> {
        pruneCompletedJobs()
        guard let job = jobs[jobID] else {
            throw HTTPError(
                .notFound,
                message: "Job '\(jobID)' was not found in the server request cache. It may be unknown or may have expired from in-memory retention."
            )
        }

        let history = job.history
        let terminalEvent = job.terminalEvent
        let workerStatusEvent = currentWorkerStatusEvent()

        return AsyncStream { continuation in
            continuation.yield(self.encodeSSEBuffer(for: workerStatusEvent))
            for event in history {
                continuation.yield(self.encodeSSEBuffer(for: event))
            }

            if terminalEvent != nil {
                continuation.finish()
                return
            }

            let subscriberID = UUID()
            let heartbeatTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(self.configuration.sseHeartbeatSeconds))
                    self.emitHeartbeat(jobID: jobID, subscriberID: subscriberID)
                }
            }

            Task {
                self.addSubscriber(
                    continuation,
                    heartbeatTask: heartbeatTask,
                    to: jobID,
                    subscriberID: subscriberID
                )
            }

            continuation.onTermination = { _ in
                heartbeatTask.cancel()
                Task {
                    await self.removeSubscriber(jobID: jobID, subscriberID: subscriberID)
                }
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
            op: handle.operationName,
            profileName: handle.profileName,
            submittedAt: Date()
        )

        Task {
            await self.consume(handle: handle)
        }
        await requestPublish(mode: .coalesced, refreshRuntimeState: true)
        return handle.id
    }

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
                    if handle.operationName == "create_profile" {
                        await finalizeMutationSuccess(
                            success: success,
                            requestID: handle.id,
                            operationName: handle.operationName
                        )
                    } else if handle.operationName == "remove_profile" {
                        await finalizeMutationSuccess(
                            success: success,
                            requestID: handle.id,
                            operationName: handle.operationName
                        )
                    } else if handle.operationName == "list_profiles" {
                        await applyProfileRefresh(from: success)
                        await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                    } else {
                        await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                    }
                }
            }
        } catch let error as WorkerError {
            let failure = ServerFailureEvent(id: handle.id, code: error.code.rawValue, message: error.message)
            await record(.failed(failure), for: handle.id, terminal: true)
        } catch {
            let failure = ServerFailureEvent(
                id: handle.id,
                code: WorkerErrorCode.internalError.rawValue,
                message: "SpeakSwiftly request '\(handle.id)' failed unexpectedly while the server was monitoring its typed event stream. \(error.localizedDescription)"
            )
            await record(.failed(failure), for: handle.id, terminal: true)
        }
    }

    private func finalizeMutationSuccess(
        success: WorkerSuccessResponse,
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
                profileName: success.profileName,
                profilePath: success.profilePath,
                profiles: nil,
                activeRequest: success.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
                queue: success.queue?.map(QueuedRequestSnapshot.init(summary:)),
                playbackState: success.playbackState.map(PlaybackStateSnapshot.init(summary:)),
                clearedCount: success.clearedCount,
                cancelledRequestID: success.cancelledRequestID
            )
            await record(.completed(finalSuccess), for: requestID, terminal: true)
        } catch {
            self.profileCacheState = "stale"
            self.profileCacheWarning = "SpeakSwiftly reported a successful profile mutation, but the server could not confirm the refreshed profile list afterward. The cached profile list may be stale. Likely cause: \(error.localizedDescription)"
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
        success: WorkerSuccessResponse,
        previousProfiles: [ProfileSnapshot]
    ) async throws -> [ProfileSnapshot] {
        guard let profileName = success.profileName, !profileName.isEmpty else {
            throw WorkerError(
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

        throw WorkerError(
            code: .internalError,
            message: "SpeakSwiftly refreshed the profile cache after \(op) for profile '\(profileName)', but the list still did not reflect the expected mutation."
        )
    }

    private func refreshProfiles(reason: String) async throws -> [ProfileSnapshot] {
        let requestID = UUID().uuidString
        let handle = await runtime.listProfilesHandle(id: requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the internal list_profiles request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing cached profiles."
        )
        let profiles = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        self.profileCache = profiles
        self.lastProfileRefreshAt = Date()
        self.profileCacheState = "fresh"
        self.profileCacheWarning = nil
        _ = reason
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return profiles
    }

    private func applyProfileRefresh(from success: WorkerSuccessResponse) async {
        self.profileCache = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        self.lastProfileRefreshAt = Date()
        self.profileCacheState = "fresh"
        self.profileCacheWarning = nil
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
        case "create_profile":
            return refreshedNames.contains(profileName) && refreshedNames != previousNames
        case "remove_profile":
            return !refreshedNames.contains(profileName) && refreshedNames != previousNames
        default:
            return false
        }
    }

    private func handle(status: WorkerStatusEvent) async {
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
                }
            }
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
        if terminal {
            job.terminalEvent = event
            job.terminalAt = Date()
        }
        jobs[jobID] = job

        for continuation in job.subscribers.values {
            continuation.yield(encodeSSEBuffer(for: event))
        }

        if terminal {
            if case .failed(let failure) = event {
                recordRecentError(
                    source: "job:\(job.op)",
                    code: failure.code,
                    message: failure.message
                )
            }
            finishSubscribers(for: jobID)
            pruneCompletedJobs()
        }
        await requestPublish(mode: terminal ? .immediate : .coalesced, refreshRuntimeState: true)
    }

    private func addSubscriber(
        _ continuation: AsyncStream<ByteBuffer>.Continuation,
        heartbeatTask: Task<Void, Never>,
        to jobID: String,
        subscriberID: UUID
    ) {
        guard var job = jobs[jobID] else {
            continuation.finish()
            heartbeatTask.cancel()
            return
        }
        job.subscribers[subscriberID] = continuation
        job.heartbeatTasks[subscriberID] = heartbeatTask
        jobs[jobID] = job
    }

    private func removeSubscriber(jobID: String, subscriberID: UUID) {
        guard var job = jobs[jobID] else { return }
        job.subscribers.removeValue(forKey: subscriberID)
        job.heartbeatTasks.removeValue(forKey: subscriberID)?.cancel()
        jobs[jobID] = job
    }

    private func emitHeartbeat(jobID: String, subscriberID: UUID) {
        guard let continuation = jobs[jobID]?.subscribers[subscriberID] else { return }
        continuation.yield(encodeHeartbeatBuffer())
    }

    private func finishSubscribers(for jobID: String) {
        guard var job = jobs[jobID] else { return }
        for task in job.heartbeatTasks.values {
            task.cancel()
        }
        for continuation in job.subscribers.values {
            continuation.finish()
        }
        job.subscribers.removeAll()
        job.heartbeatTasks.removeAll()
        jobs[jobID] = job
    }

    private func pruneCompletedJobs() {
        let now = Date()
        let expiredIDs = jobs.compactMap { jobID, job -> String? in
            guard let terminalAt = job.terminalAt else { return nil }
            let age = now.timeIntervalSince(terminalAt)
            return age > configuration.completedJobTTLSeconds ? jobID : nil
        }
        for jobID in expiredIDs {
            finishSubscribers(for: jobID)
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
            finishSubscribers(for: job.jobID)
            jobs.removeValue(forKey: job.jobID)
        }
    }

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
            state.transports = hostState.transports
            state.recentErrors = hostState.recentErrors
            state.jobsByID = jobsByID
        }
    }

    private func refreshRuntimeDerivedState() async {
        guard workerMode == "ready" else {
            generationQueueStatus = deriveGenerationQueueStatusFallback()
            playbackQueueStatus = derivePlaybackQueueStatusFallback()
            playbackStatus = derivePlaybackStatusFallback()
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
    }

    private func fetchQueueStatus(_ queueType: WorkerQueueType) async throws -> QueueStatusSnapshot {
        let requestID = UUID().uuidString
        let handle = await runtime.listQueueHandle(queueType, id: requestID)
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
        let requestID = UUID().uuidString
        let handle = await runtime.playbackHandle(.state, id: requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the playback state request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing playback state."
        )
        guard let playbackState = success.playbackState else {
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly accepted the playback state request, but it did not return a playback state payload."
            )
        }

        return .init(
            state: playbackState.state.rawValue,
            activeRequest: playbackState.activeRequest.map(ActiveRequestSnapshot.init(summary:))
        )
    }

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
            .filter { $0.op == "queue_speech_live" && $0.terminalEvent == nil }
            .sorted { lhs, rhs in
                generationPriority(for: lhs) > generationPriority(for: rhs)
                    || (
                        generationPriority(for: lhs) == generationPriority(for: rhs)
                        && lhs.submittedAt < rhs.submittedAt
                    )
            }
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
            guard $0.op == "queue_speech_live", $0.terminalEvent == nil else {
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
            activeCount: playbackStatus.state == PlaybackState.idle.rawValue ? 0 : 1,
            queuedCount: 0,
            activeRequest: playbackStatus.activeRequest
        )
    }

    private func derivePlaybackStatusFallback() -> PlaybackStatusSnapshot {
        if let activeRequest = currentGenerationJobRecord().map({
            ActiveRequestSnapshot(id: $0.jobID, op: $0.op, profileName: $0.profileName)
        }) {
            return .init(state: PlaybackState.playing.rawValue, activeRequest: activeRequest)
        }
        return .init(state: PlaybackState.idle.rawValue, activeRequest: nil)
    }

    private func transportSnapshots() -> [TransportStatusSnapshot] {
        [
            .init(
                name: "http",
                enabled: httpConfig.enabled,
                state: httpConfig.enabled ? "configured" : "disabled",
                host: httpConfig.enabled ? httpConfig.host : nil,
                port: httpConfig.enabled ? httpConfig.port : nil,
                path: nil,
                advertisedAddress: httpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)" : nil
            ),
            .init(
                name: "mcp",
                enabled: mcpConfig.enabled,
                state: mcpConfig.enabled ? "configured" : "disabled",
                host: mcpConfig.enabled ? httpConfig.host : nil,
                port: mcpConfig.enabled ? httpConfig.port : nil,
                path: mcpConfig.enabled ? mcpConfig.path : nil,
                advertisedAddress: mcpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)\(mcpConfig.path)" : nil
            ),
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
    }

    private func mapQueuedEvent(_ event: WorkerQueuedEvent) -> ServerJobEvent {
        .queued(
            .init(
                id: event.id,
                reason: event.reason.rawValue,
                queuePosition: event.queuePosition
            )
        )
    }

    private func mapStartedEvent(_ event: WorkerStartedEvent) -> ServerJobEvent {
        .started(.init(id: event.id, op: event.op))
    }

    private func mapProgressEvent(_ event: WorkerProgressEvent) -> ServerJobEvent {
        .progress(.init(id: event.id, stage: event.stage.rawValue))
    }

    private func mapSuccessEvent(_ event: WorkerSuccessResponse, acknowledged: Bool) -> ServerJobEvent {
        let success = ServerSuccessEvent(
            id: event.id,
            profileName: event.profileName,
            profilePath: event.profilePath,
            profiles: event.profiles?.map(ProfileSnapshot.init(profile:)),
            activeRequest: event.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
            queue: event.queue?.map(QueuedRequestSnapshot.init(summary:)),
            playbackState: event.playbackState.map(PlaybackStateSnapshot.init(summary:)),
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

    private func encodeHeartbeatBuffer() -> ByteBuffer {
        var buffer = byteBufferAllocator.buffer(capacity: 15)
        buffer.writeString(": keep-alive\n\n")
        return buffer
    }

    private func playbackStateResponse(for action: PlaybackAction) async throws -> PlaybackStateResponse {
        let requestID = UUID().uuidString
        let handle = await runtime.playbackHandle(action, id: requestID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operationName)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operationName)' control request."
        )
        guard let playbackState = success.playbackState else {
            throw WorkerError(
                code: .internalError,
                message: "SpeakSwiftly accepted the '\(requestName(for: action))' control request, but it did not return a playback state payload."
            )
        }
        return .init(playback: .init(summary: playbackState))
    }

    private func requestName(for action: PlaybackAction) -> String {
        switch action {
        case .pause:
            "playback_pause"
        case .resume:
            "playback_resume"
        case .state:
            "playback_state"
        }
    }

    private func queueTypeName(_ queueType: WorkerQueueType) -> String {
        switch queueType {
        case .generation:
            "generation"
        case .playback:
            "playback"
        }
    }

    private func awaitImmediateSuccess(
        handle: RuntimeRequestHandle,
        missingTerminalMessage: String,
        unexpectedFailureMessagePrefix: String
    ) async throws -> WorkerSuccessResponse {
        do {
            for try await event in handle.events {
                if case .completed(let success) = event {
                    return success
                }
            }
            throw WorkerError(
                code: .internalError,
                message: missingTerminalMessage
            )
        } catch let error as WorkerError {
            throw error
        } catch {
            throw WorkerError(
                code: .internalError,
                message: "\(unexpectedFailureMessagePrefix) \(error.localizedDescription)"
            )
        }
    }
}
