import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

private struct GenerationArtifactPayload: Encodable {
    let artifactID: String
    let kind: String
    let createdAt: Date
    let filePath: String
    let sampleRate: Int
    let voiceProfile: String
    let textProfile: SpeakSwiftly.TextProfileID?
    let inputTextContext: SpeakSwiftly.InputTextContext?
    let requestContext: SpeakSwiftly.RequestContext?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case kind
        case createdAt = "created_at"
        case filePath = "file_path"
        case sampleRate = "sample_rate"
        case voiceProfile = "voice_profile"
        case textProfile = "text_profile"
        case inputTextContext = "input_text_context"
        case requestContext = "request_context"
    }
}

private func makeGenerationArtifact(from generatedFile: SpeakSwiftly.GeneratedFile) throws -> SpeakSwiftly.GenerationArtifact {
    let payload = GenerationArtifactPayload(
        artifactID: generatedFile.artifactID,
        kind: "audio_wav",
        createdAt: generatedFile.createdAt,
        filePath: generatedFile.filePath,
        sampleRate: generatedFile.sampleRate,
        voiceProfile: generatedFile.voiceProfile,
        textProfile: generatedFile.textProfile,
        inputTextContext: generatedFile.inputTextContext,
        requestContext: generatedFile.requestContext,
    )

    let data = try JSONEncoder().encode(payload)
    return try JSONDecoder().decode(SpeakSwiftly.GenerationArtifact.self, from: data)
}

extension ServerHost {
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
            transports: hostState.transports,
            recentErrors: hostState.recentErrors,
        )
    }

    func runtimeConfigurationSnapshot() -> RuntimeConfigurationSnapshot {
        runtimeConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeQwenResidentModel: activeQwenResidentModel,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
    }

    func saveRuntimeConfiguration(
        speechBackend: SpeakSwiftly.SpeechBackend,
        qwenResidentModel: SpeakSwiftly.QwenResidentModel? = nil,
        marvisResidentPolicy: SpeakSwiftly.MarvisResidentPolicy? = nil,
    ) async throws -> RuntimeConfigurationSnapshot {
        let snapshot = try runtimeConfigurationStore.save(
            speechBackend: speechBackend,
            qwenResidentModel: qwenResidentModel,
            marvisResidentPolicy: marvisResidentPolicy,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeQwenResidentModel: activeQwenResidentModel,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
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
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-jobs request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing retained generation jobs.",
        )
        return success.generationJobs ?? []
    }

    func generationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.generationJob(id: jobID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading retained generation job '\(jobID)'.",
        )
        guard let generationJob = success.generationJob else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job request for '\(jobID)', but it did not return a generation_job payload.",
            )
        }

        return generationJob
    }

    func expireGenerationJob(id jobID: String) async throws -> SpeakSwiftly.GenerationJob {
        let handle = await runtime.expireGenerationJob(id: jobID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-job expiry request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while expiring retained generation job '\(jobID)'.",
        )
        guard let generationJob = success.generationJob else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-job expiry request for '\(jobID)', but it did not return a generation_job payload.",
            )
        }

        return generationJob
    }

    func listGenerationArtifacts() async throws -> [SpeakSwiftly.GenerationArtifact] {
        let handle = await runtime.listGenerationArtifacts()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-artifacts request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while listing retained generation artifacts.",
        )
        return try success.generatedFiles?.map(makeGenerationArtifact(from:)) ?? []
    }

    func generationArtifact(id artifactID: String) async throws -> SpeakSwiftly.GenerationArtifact {
        let handle = await runtime.generationArtifact(id: artifactID)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the generation-artifact request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading retained generation artifact '\(artifactID)'.",
        )
        guard let generatedFile = success.generatedFile else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the generation-artifact request for '\(artifactID)', but it did not return an artifact payload.",
            )
        }

        return try makeGenerationArtifact(from: generatedFile)
    }

    func runtimeStatus() async throws -> RuntimeStatusResponse {
        let handle = await runtime.runtimeStatus()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the runtime-status request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while reading runtime status.",
        )
        guard let status = success.status else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the runtime-status request, but it did not return a status payload.",
            )
        }

        return .init(status: status, runtimeBackendTransition: runtimeBackendTransitionSnapshot())
    }

    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async throws -> RuntimeBackendResponse {
        let handle = await runtime.switchSpeechBackend(to: speechBackend)
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the speech-backend switch request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while switching the active speech backend.",
        )
        guard let resolvedSpeechBackend = success.speechBackend else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the speech-backend switch request, but it did not return a speech_backend payload.",
            )
        }

        activeRuntimeSpeechBackend = resolvedSpeechBackend
        let runtimeConfigurationSnapshot = runtimeConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: resolvedSpeechBackend,
            activeQwenResidentModel: activeQwenResidentModel,
            activeMarvisResidentPolicy: activeMarvisResidentPolicy,
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
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        return .init(clearedCount: success.clearedCount ?? 0)
    }

    func cancelQueuedOrActiveRequest(requestID: String) async throws -> QueueCancellationResponse {
        let handle = await runtime.cancelRequest(requestID)
        return try await queueCancellationResponse(handle: handle)
    }

    func cancelQueuedOrActiveRequest(
        requestID: String,
        scope: RequestCancellationScope?,
    ) async throws -> QueueCancellationResponse {
        if let scope {
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
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        guard let cancelledRequestID = success.cancelledRequestID, !cancelledRequestID.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the cancel-request control operation, but it did not report which request was cancelled.",
            )
        }

        return .init(cancelledRequestID: cancelledRequestID)
    }
}
