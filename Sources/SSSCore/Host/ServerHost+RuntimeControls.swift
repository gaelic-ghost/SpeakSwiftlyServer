import Foundation
import SpeakSwiftly
import TextForSpeech

package extension ServerHost {
    // MARK: - Public Query Surface

    func statusSnapshot() -> StatusSnapshot {
        let hostState = hostStateSnapshot()
        let overview = hostState.overview
        return .init(
            service: overview.service,
            environment: overview.environment,
            defaultVoiceProfileName: overview.defaultVoiceProfileName,
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
            runtimeRefresh: hostState.runtimeRefresh,
            generationQueue: hostState.generationQueue,
            playbackQueue: hostState.playbackQueue,
            playback: hostState.playback,
            runtimeBackendTransition: hostState.runtimeBackendTransition,
            currentGenerationJobs: hostState.currentGenerationJobs,
            runtimeConfiguration: hostState.runtimeConfiguration,
            remoteGeneration: hostState.remoteGeneration,
            transports: hostState.transports,
            networkAudioDestinations: hostState.networkAudioDestinations,
            networkAudioReceiverSelection: hostState.networkAudioReceiverSelection,
            recentErrors: hostState.recentErrors,
        )
    }

    func runtimeConfigurationSnapshot() -> RuntimeConfigurationSnapshot {
        runtimeStartupConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDuckMediaVolume: activeDuckMediaVolume,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
    }

    func remoteGenerationStatusSnapshot() -> RemoteGenerationStatusSnapshot {
        let sharedTokenConfigured = remoteGenerationConfig.sharedToken?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let state = if remoteGenerationConfig.allowRemoteStreamRequests == false {
            "disabled"
        } else if sharedTokenConfigured {
            "ready"
        } else {
            "misconfigured"
        }

        return .init(
            state: state,
            streamRequestsEnabled: remoteGenerationConfig.allowRemoteStreamRequests,
            sharedTokenConfigured: sharedTokenConfigured,
            streamTokenHeaderName: RemoteGenerationConfig.streamTokenHeaderName,
            activeOutboundRequestCount: remoteGenerationRequestTasks.count,
        )
    }

    func saveRuntimeConfiguration(
        speechBackend: SpeakSwiftly.SpeechBackend,
        duckMediaVolume: SpeakSwiftly.DuckMediaVolume? = nil,
    ) async throws -> RuntimeConfigurationSnapshot {
        let snapshot = try runtimeStartupConfigurationStore.save(
            speechBackend: speechBackend,
            duckMediaVolume: duckMediaVolume,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDuckMediaVolume: activeDuckMediaVolume,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        emitRuntimeConfigurationChanged(snapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return snapshot
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

    func listGenerationJobs() async throws -> [SpeakSwiftly.GenerationJob] {
        let handle = await runtime.listGenerationJobs()
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-jobs request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing retained generation jobs.",
        )
        guard case let .generationJobs(jobs) = completion else {
            return []
        }

        return jobs
    }

    func generationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.generationJob(id: jobID)
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading retained generation job '\(jobID)'.",
        )
        guard case let .generationJob(generationJob) = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job request for '\(jobID)', but it did not return a generation_job payload.",
            )
        }

        return generationJob
    }

    func expireGenerationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.expireGenerationJob(id: jobID)
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job expiry request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while expiring retained generation job '\(jobID)'.",
        )
        guard case let .generationJob(generationJob) = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job expiry request for '\(jobID)', but it did not return a generation_job payload.",
            )
        }

        return generationJob
    }

    func listGenerationArtifacts() async throws -> [SpeakSwiftly.GenerationArtifact] {
        let handle = await runtime.listGenerationArtifacts()
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-artifacts request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing retained generation artifacts.",
        )
        guard case let .artifacts(artifacts) = completion else {
            return []
        }

        return artifacts
    }

    func generationArtifact(id artifactID: String) async throws -> SpeakSwiftly.GenerationArtifact {
        let handle = await runtime.generationArtifact(id: artifactID)
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-artifact request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading retained generation artifact '\(artifactID)'.",
        )
        guard case let .artifact(artifact) = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-artifact request for '\(artifactID)', but it did not return an artifact payload.",
            )
        }

        return artifact
    }

    func runtimeStatus() async throws -> RuntimeStatusResponse {
        let runtimeSnapshot = await runtime.runtimeSnapshot()
        return .init(
            runtime: runtimeSnapshot,
            runtimeBackendTransition: runtimeBackendTransitionSnapshot(),
        )
    }

    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async throws -> RuntimeBackendResponse {
        let handle = await runtime.switchSpeechBackend(to: speechBackend)
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the speech-backend switch request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while switching the active speech backend.",
        )
        guard case .runtimeUpdate = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the speech-backend switch request, but it did not return a runtime update payload.",
            )
        }

        let runtimeSnapshot = await runtime.runtimeSnapshot()
        let resolvedSpeechBackend = runtimeSnapshot.speechBackend == speechBackend
            ? runtimeSnapshot.speechBackend
            : speechBackend
        activeRuntimeSpeechBackend = resolvedSpeechBackend
        let runtimeConfigurationSnapshot = runtimeStartupConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: resolvedSpeechBackend,
            activeDuckMediaVolume: activeDuckMediaVolume,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(speechBackend: resolvedSpeechBackend.rawValue)
    }

    func reloadModels() async throws -> RuntimeStatusResponse {
        try await runtimeStatusResponse(
            handle: runtime.reloadModels(),
            requestName: "reload-models",
        )
    }

    func unloadModels() async throws -> RuntimeStatusResponse {
        try await runtimeStatusResponse(
            handle: runtime.unloadModels(),
            requestName: "unload-models",
        )
    }

    // MARK: - Immediate Control Operations

    func generationQueueSnapshot() async -> QueueSnapshotResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return queueSnapshotResponse(from: generationQueueStatus)
    }

    func playbackStateSnapshot() async -> PlaybackStateResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return .init(playback: playbackStatus)
    }

    func pausePlayback() async throws -> PlaybackStateResponse {
        try await playbackControlResponse(
            handle: runtime.pausePlayback(),
            requestName: "pause-playback",
            expectedState: .paused,
        )
    }

    func resumePlayback() async throws -> PlaybackStateResponse {
        try await playbackControlResponse(
            handle: runtime.resumePlayback(),
            requestName: "resume-playback",
            expectedState: .playing,
        )
    }

    func playbackQueueSnapshot() async -> QueueSnapshotResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return queueSnapshotResponse(from: playbackQueueStatus)
    }

    func clearQueue() async throws -> QueueClearedResponse {
        let handle = await runtime.clearQueue()
        return try await queueClearedResponse(handle: handle)
    }

    func clearQueue(_ queueType: SpeakSwiftly.QueueType) async throws -> QueueClearedResponse {
        let handle = await runtime.clearQueue(queueType)
        return try await queueClearedResponse(handle: handle)
    }

    private func queueClearedResponse(handle: RuntimeRequestHandle) async throws -> QueueClearedResponse {
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        guard case let .queueCleared(count) = completion else {
            return .init(clearedCount: 0)
        }

        return .init(clearedCount: count)
    }

    func cancelQueuedOrActiveRequest(requestID: String) async throws -> QueueCancellationResponse {
        if let response = cancelRemoteGenerationRequestIfTracked(requestID: requestID) {
            return response
        }

        let handle = await runtime.cancelRequest(requestID)
        return try await queueCancellationResponse(handle: handle)
    }

    func cancelQueuedOrActiveRequest(
        requestID: String,
        scope: RequestCancellationScope?,
    ) async throws -> QueueCancellationResponse {
        if let scope {
            if scope == .generation,
               let response = cancelRemoteGenerationRequestIfTracked(requestID: requestID) {
                return response
            }

            return try await cancelQueuedOrActiveRequest(scope.queueType, requestID: requestID)
        }

        return try await cancelQueuedOrActiveRequest(requestID: requestID)
    }

    func cancelQueuedOrActiveRequest(
        _ queueType: SpeakSwiftly.QueueType,
        requestID: String,
    ) async throws -> QueueCancellationResponse {
        let handle = await runtime.cancel(queueType, requestID: requestID)
        return try await queueCancellationResponse(handle: handle)
    }

    private func queueCancellationResponse(handle: RuntimeRequestHandle) async throws -> QueueCancellationResponse {
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        guard case let .requestCancelled(cancelledRequestID) = completion, !cancelledRequestID.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the cancel-request control operation, but it did not report which request was cancelled.",
            )
        }

        return .init(cancelledRequestID: cancelledRequestID)
    }

    private func cancelRemoteGenerationRequestIfTracked(requestID: String) -> QueueCancellationResponse? {
        guard let task = remoteGenerationRequestTasks[requestID] else {
            return nil
        }

        task.cancel()
        remoteGenerationRequestTasks[requestID] = nil
        return .init(cancelledRequestID: requestID)
    }
}
