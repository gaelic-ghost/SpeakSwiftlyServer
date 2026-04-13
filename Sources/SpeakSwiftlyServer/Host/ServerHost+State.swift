import Foundation
import SpeakSwiftly

// MARK: - Host State Flow

extension ServerHost {
    // MARK: - Publish Flow

    func requestPublish(mode: PublishMode, refreshRuntimeState: Bool) async {
        pendingRuntimeRefresh = pendingRuntimeRefresh || refreshRuntimeState
        switch mode {
        case .immediate:
            immediatePublishContinuation.yield(())
        case .coalesced:
            coalescedPublishContinuation.yield(())
        }
    }

    func publishState() async {
        let shouldRefreshRuntimeState = pendingRuntimeRefresh
        pendingRuntimeRefresh = false
        if shouldRefreshRuntimeState {
            await refreshRuntimeDerivedState()
        }

        let hostState = hostStateSnapshot()
        let cachedVoiceProfiles = profileCache
        let jobsByID = Dictionary(uniqueKeysWithValues: jobs.map { ($0.key, $0.value.snapshot) })
        publishedStateContinuation.yield(hostState)

        await MainActor.run {
            state.overview = hostState.overview
            state.runtimeRefresh = hostState.runtimeRefresh
            state.generationQueue = hostState.generationQueue
            state.playbackQueue = hostState.playbackQueue
            state.playback = hostState.playback
            state.currentGenerationJobs = hostState.currentGenerationJobs
            state.runtimeConfiguration = hostState.runtimeConfiguration
            state.voiceProfiles = cachedVoiceProfiles
            state.transports = hostState.transports
            state.recentErrors = hostState.recentErrors
            state.jobsByID = jobsByID
        }
    }

    func shouldRefreshRuntimeDerivedState(
        after event: ServerJobEvent,
        terminal: Bool
    ) -> Bool {
        if terminal {
            return true
        }

        switch event {
        case .queued, .started, .progress:
            return true
        case .workerStatus, .acknowledged, .completed, .failed:
            return false
        }
    }

    // MARK: - Runtime-Derived State

    func refreshRuntimeDerivedState() async {
        let previousPlaybackStatus = playbackStatus
        let refreshSequenceID = nextRuntimeRefreshSequenceID
        nextRuntimeRefreshSequenceID += 1
        let startedAt = Date()
        guard workerMode == "ready" else {
            applyCachedRuntimeDerivedState(
                sequenceID: refreshSequenceID,
                startedAt: startedAt,
                previousPlaybackStatus: previousPlaybackStatus,
                source: "cached_worker_not_ready"
            )
            return
        }

        var runtimeOverviewRefreshedAt = Date()
        do {
            try await applyRuntimeOverviewSnapshot()
            runtimeOverviewRefreshedAt = Date()
            runtimeRefreshSnapshot = .init(
                sequenceID: refreshSequenceID,
                source: "runtime_overview",
                startedAt: TimestampFormatter.string(from: startedAt),
                generationQueueRefreshedAt: TimestampFormatter.string(from: runtimeOverviewRefreshedAt),
                playbackQueueRefreshedAt: TimestampFormatter.string(from: runtimeOverviewRefreshedAt),
                playbackStateRefreshedAt: TimestampFormatter.string(from: runtimeOverviewRefreshedAt),
                completedAt: TimestampFormatter.string(from: Date())
            )
        } catch {
            recordRecentError(
                source: "runtime:overview",
                code: "runtime_overview_failed",
                message: "SpeakSwiftlyServer could not refresh the atomic runtime overview snapshot. Likely cause: \(error.localizedDescription)"
            )
            applyCachedRuntimeDerivedState(
                sequenceID: refreshSequenceID,
                startedAt: startedAt,
                previousPlaybackStatus: previousPlaybackStatus,
                source: "cached_runtime_overview_failed"
            )
            return
        }

        if playbackStatus != previousPlaybackStatus {
            hostEventContinuation.yield(.playbackChanged(playbackStatus))
        }
    }

    func refreshRuntimeDerivedStateIfNeeded() async {
        guard pendingRuntimeRefresh else {
            return
        }
        pendingRuntimeRefresh = false
        await refreshRuntimeDerivedState()
    }

    func applyCachedRuntimeDerivedState(
        sequenceID: Int,
        startedAt: Date,
        previousPlaybackStatus: PlaybackStatusSnapshot,
        source: String
    ) {
        if source == "cached_worker_not_ready" {
            playbackQueueStatus = .init(
                queueType: "playback",
                activeCount: 0,
                queuedCount: 0,
                activeRequest: nil,
                activeRequests: [],
                queuedRequests: []
            )
            playbackStatus = .init(
                state: SpeakSwiftly.PlaybackState.idle.rawValue,
                activeRequest: nil,
                isStableForConcurrentGeneration: false,
                isRebuffering: false,
                stableBufferedAudioMS: nil,
                stableBufferTargetMS: nil
            )
        }
        let refreshedAt = Date()
        runtimeRefreshSnapshot = .init(
            sequenceID: sequenceID,
            source: source,
            startedAt: TimestampFormatter.string(from: startedAt),
            generationQueueRefreshedAt: TimestampFormatter.string(from: refreshedAt),
            playbackQueueRefreshedAt: TimestampFormatter.string(from: refreshedAt),
            playbackStateRefreshedAt: TimestampFormatter.string(from: refreshedAt),
            completedAt: TimestampFormatter.string(from: refreshedAt)
        )
        if playbackStatus != previousPlaybackStatus {
            hostEventContinuation.yield(.playbackChanged(playbackStatus))
        }
    }

    // MARK: - Runtime Snapshot Fetches

    func applyRuntimeOverviewSnapshot() async throws {
        let handle = await runtime.runtimeOverview()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the runtime overview request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing the atomic runtime overview snapshot."
        )
        guard let overview = success.runtimeOverview else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the runtime overview request, but it did not return a runtime_overview payload."
            )
        }
        generationQueueStatus = queueStatusSnapshot(from: overview.generationQueue)
        playbackQueueStatus = queueStatusSnapshot(from: overview.playbackQueue)
        playbackStatus = PlaybackStatusSnapshot(summary: overview.playbackState)
    }

    // MARK: - Derived Snapshot Helpers

    func currentGenerationJobSnapshots() -> [CurrentGenerationJobSnapshot] {
        activeGenerationJobRecords().map { job in
            .init(
                jobID: job.jobID,
                op: job.op,
                profileName: job.profileName,
                submittedAt: TimestampFormatter.string(from: job.submittedAt),
                startedAt: job.startedAt.map(TimestampFormatter.string(from:)),
                latestStage: latestStage(for: job.latestEvent),
                elapsedGenerationSeconds: job.startedAt.map { max(0, Date().timeIntervalSince($0)) }
            )
        }
    }

    func activeGenerationJobRecords() -> [JobRecord] {
        generationQueueStatus.activeRequests.compactMap { activeRequest in
            guard let job = jobs[activeRequest.id], isGenerationOperation(job.op), job.terminalEvent == nil else {
                return nil
            }
            return job
        }
        .sorted(by: generationJobOrdering)
    }

    func generationPriority(for job: JobRecord) -> Int {
        switch latestOperationalEvent(for: job) {
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

    func latestStage(for event: ServerJobEvent?) -> String? {
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

    func latestOperationalEvent(for job: JobRecord) -> ServerJobEvent? {
        job.history.reversed().first { event in
            if case .workerStatus = event {
                return false
            }
            return true
        }
    }

    func transportSnapshots() -> [TransportStatusSnapshot] {
        ["http", "mcp"].compactMap { transportStatuses[$0] }
    }

    func applyLiveConfigurationChanges(from appConfig: AppConfig) -> Bool {
        var didChange = false
        var shouldPruneCompletedJobs = false
        let previousConfiguredDefaultVoiceProfileName = configuration.defaultVoiceProfileName

        if configuration.name != appConfig.server.name ||
            configuration.environment != appConfig.server.environment ||
            previousConfiguredDefaultVoiceProfileName != appConfig.server.defaultVoiceProfileName ||
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
                defaultVoiceProfileName: appConfig.server.defaultVoiceProfileName,
                host: configuration.host,
                port: configuration.port,
                sseHeartbeatSeconds: appConfig.server.sseHeartbeatSeconds,
                completedJobTTLSeconds: appConfig.server.completedJobTTLSeconds,
                completedJobMaxCount: appConfig.server.completedJobMaxCount,
                jobPruneIntervalSeconds: appConfig.server.jobPruneIntervalSeconds
            )
            didChange = true
        }

        if activeDefaultVoiceProfileName == previousConfiguredDefaultVoiceProfileName {
            activeDefaultVoiceProfileName = appConfig.server.defaultVoiceProfileName
        }

        if shouldPruneCompletedJobs {
            pruneCompletedJobs()
        }

        return didChange
    }

    func restartRequiredConfigurationKeys(for appConfig: AppConfig) -> [String] {
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
}
