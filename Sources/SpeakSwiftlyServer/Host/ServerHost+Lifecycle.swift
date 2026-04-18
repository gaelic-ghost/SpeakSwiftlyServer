import AsyncAlgorithms
import Foundation

// MARK: - Host Lifecycle Surface

extension ServerHost {
    // MARK: - Runtime Lifecycle

    func start() async {
        publishTask = Task {
            let immediateRequests = self.immediatePublishRequests
            let coalescedRequests = self.coalescedPublishRequests.debounce(for: .milliseconds(25))
            for await _ in merge(immediateRequests, coalescedRequests) {
                await self.publishState()
            }
        }

        let statusStream = await runtime.statusEvents()
        statusTask = Task {
            for await status in statusStream {
                await self.handle(status: status)
            }
        }

        await runtime.start()
        await requestPublish(mode: .immediate, refreshRuntimeState: true)
    }

    func shutdown() async {
        statusTask?.cancel()
        let requestMonitorTasks = requestMonitorTasks
        self.requestMonitorTasks.removeAll()
        for task in requestMonitorTasks.values {
            task.cancel()
        }
        await runtime.shutdown()
        for task in requestMonitorTasks.values {
            await task.value
        }
        workerMode = "stopped"
        workerStage = "stopped"
        if httpConfig.enabled {
            updateTransportStatus(named: "http", state: "stopped")
        }
        if mcpConfig.enabled {
            updateTransportStatus(named: "mcp", state: "stopped")
        }

        pendingRuntimeRefresh = false
        await publishState()
        publishTask?.cancel()
        immediatePublishContinuation.finish()
        coalescedPublishContinuation.finish()
        publishedStateContinuation.finish()
        hostEventContinuation.finish()
    }

    func requestMonitorTaskCount() -> Int {
        requestMonitorTasks.count
    }

    func jobPruneInterval() -> Duration {
        .seconds(configuration.jobPruneIntervalSeconds)
    }

    func runPruneMaintenanceTick() async {
        pruneCompletedJobs()
        await requestPublish(mode: .coalesced, refreshRuntimeState: false)
    }

    // MARK: - Shared Update Streams

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
            message: message,
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
                message: "SpeakSwiftlyServer reloaded configuration from disk, but these settings still require a full restart before they can take effect: \(restartRequiredKeys.joined(separator: ", ")).",
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
            message: "SpeakSwiftlyServer detected a configuration file change, but the updated values were not valid and were left unapplied. Likely cause: \(message)",
        )
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func markConfigurationWatchFailed(_ error: any Error) async {
        recordRecentError(
            source: "config",
            code: "reload_watch_failed",
            message: "SpeakSwiftlyServer could not continue watching for configuration file updates. Likely cause: \(error.localizedDescription)",
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
            lastProfileRefreshAt: lastProfileRefreshAt.map(TimestampFormatter.string(from:)),
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
            recentErrors: recentErrors,
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
            startupError: overview.startupError,
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
                lastProfileRefreshAt: overview.lastProfileRefreshAt,
            ),
        )
    }
}
