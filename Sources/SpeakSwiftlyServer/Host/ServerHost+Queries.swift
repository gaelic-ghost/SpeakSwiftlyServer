import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

// MARK: - Query Surface

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
            currentGenerationJobs: hostState.currentGenerationJobs,
            runtimeConfiguration: hostState.runtimeConfiguration,
            transports: hostState.transports,
            recentErrors: hostState.recentErrors
        )
    }

    func runtimeConfigurationSnapshot() -> RuntimeConfigurationSnapshot {
        runtimeConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName
        )
    }

    func saveRuntimeConfiguration(
        speechBackend: SpeakSwiftly.SpeechBackend
    ) async throws -> RuntimeConfigurationSnapshot {
        let snapshot = try runtimeConfigurationStore.save(
            speechBackend: speechBackend,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            activeDefaultVoiceProfileName: activeDefaultVoiceProfileName,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName
        )
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

    func resolvedRequestedVoiceProfileName(_ requestedProfileName: String?) -> String? {
        let explicitProfileName = requestedProfileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitProfileName, !explicitProfileName.isEmpty {
            return explicitProfileName
        }
        return activeDefaultVoiceProfileName
    }

    func missingVoiceProfileNameMessage(for operation: String) -> String {
        "SpeakSwiftlyServer could not queue \(operation) because the request did not include 'profile_name' and the server does not have 'app.defaultVoiceProfileName' configured."
    }

    func defaultVoiceProfileName() -> SpeakSwiftly.Name? {
        activeDefaultVoiceProfileName
    }

    func setDefaultVoiceProfileName(_ profileName: SpeakSwiftly.Name) async throws -> SpeakSwiftly.Name {
        let normalizedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProfileName.isEmpty else {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not set the default voice profile because the requested profile name was empty."
            )
        }
        activeDefaultVoiceProfileName = normalizedProfileName
        let runtimeConfigurationSnapshot = try runtimeConfigurationStore.saveDefaultVoiceProfileName(
            normalizedProfileName,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return normalizedProfileName
    }

    func clearDefaultVoiceProfileName() async throws -> SpeakSwiftly.Name? {
        let fallbackProfileName = configuration.defaultVoiceProfileName
        activeDefaultVoiceProfileName = fallbackProfileName
        let runtimeConfigurationSnapshot = try runtimeConfigurationStore.saveDefaultVoiceProfileName(
            nil,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return fallbackProfileName
    }

    func refreshVoiceProfiles() async throws -> [ProfileSnapshot] {
        try await refreshProfiles(reason: "app_consumer")
    }

    func textProfilesSnapshot() async -> TextProfilesSnapshot {
        let builtInStyle = await runtime.builtInTextProfileStyle()
        return .init(
            builtInStyle: builtInStyle.rawValue,
            baseProfile: .init(profile: await runtime.baseTextProfile()),
            activeProfile: .init(profile: await runtime.activeTextProfile()),
            storedProfiles: (await runtime.textProfiles()).map(TextProfileSnapshot.init(profile:)),
            effectiveProfile: .init(profile: await runtime.effectiveTextProfile(id: nil))
        )
    }

    func textProfileStyleSnapshot() async -> TextProfileStyleSnapshot {
        .init(style: await runtime.builtInTextProfileStyle())
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

    func setTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle
    ) async throws -> TextProfilesSnapshot {
        _ = try await runtime.setBuiltInTextProfileStyle(style)
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

    func removeTextProfile(id profileID: String) async throws -> TextProfilesSnapshot {
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
        toStoredTextProfileID profileID: String? = nil
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
        inStoredTextProfileID profileID: String? = nil
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
        fromStoredTextProfileID profileID: String? = nil
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

    func listGenerationJobs() async throws -> [SpeakSwiftly.GenerationJob] {
        let handle = await runtime.listGenerationJobs()
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

    func listGeneratedFiles() async throws -> [SpeakSwiftly.GeneratedFile] {
        let handle = await runtime.listGeneratedFiles()
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

    func listGeneratedBatches() async throws -> [SpeakSwiftly.GeneratedBatch] {
        let handle = await runtime.listGeneratedBatches()
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
        activeRuntimeSpeechBackend = resolvedSpeechBackend
        let runtimeConfigurationSnapshot = runtimeConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: resolvedSpeechBackend
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
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

    // MARK: - Immediate Control Operations

    func generationQueueSnapshot() async -> QueueSnapshotResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return queueSnapshotResponse(from: generationQueueStatus)
    }

    func playbackStateSnapshot() async -> PlaybackStateResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return .init(playback: .init(status: playbackStatus))
    }

    func pausePlayback() async throws -> PlaybackStateResponse {
        try await playbackControlResponse(
            handle: await runtime.pausePlayback(),
            requestName: "pause-playback",
            expectedState: .paused
        )
    }

    func resumePlayback() async throws -> PlaybackStateResponse {
        try await playbackControlResponse(
            handle: await runtime.resumePlayback(),
            requestName: "resume-playback",
            expectedState: .playing
        )
    }

    func playbackQueueSnapshot() async -> QueueSnapshotResponse {
        await refreshRuntimeDerivedStateIfNeeded()
        return queueSnapshotResponse(from: playbackQueueStatus)
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
}
