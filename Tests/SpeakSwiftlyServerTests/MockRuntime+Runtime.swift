import Foundation
import SpeakSwiftlyCore
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - Mock Runtime Protocol

@available(macOS 14, *)
extension MockRuntime {
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let request = MockRequest(id: requestID, operation: "generate_speech", profileName: profileName)
        queuedSpeechInvocations.append(
            .init(
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                normalizationContext: normalizationContext,
                sourceFormat: sourceFormat
            )
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a speech request continuation for request '\(requestID)'.")
        }

        continuation.yield(.acknowledged(.init(id: requestID)))

        if self.activeRequest == nil {
            self.startActiveRequest(request, continuation: continuation)
        } else {
            self.queuedRequests.append(.init(request: request, continuation: continuation))
            continuation.yield(
                .queued(
                    .init(
                        id: requestID,
                        reason: .waitingForActiveRequest,
                        queuePosition: self.queuedRequests.count
                    )
                )
            )
        }

        return RuntimeRequestHandle(id: requestID, operation: request.operation, profileName: profileName, events: events)
    }

    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let artifactID = "\(requestID)-artifact-1"
        let createdAt = Date()
        let generatedFile = try! makeGeneratedFile(
            artifactID: artifactID,
            createdAt: createdAt,
            profileName: profileName,
            textProfileName: textProfileName,
            sampleRate: 24_000,
            filePath: "/tmp/\(artifactID).wav"
        )
        generatedFiles.append(generatedFile)
        let items = [
            GenerationJobItemFixture(
                artifactID: artifactID,
                text: text,
                textProfileName: textProfileName,
                textContext: normalizationContext,
                sourceFormat: sourceFormat
            )
        ]
        let artifacts = [
            GenerationArtifactFixture(
                artifactID: artifactID,
                kind: "audio_wav",
                createdAt: createdAt,
                filePath: generatedFile.filePath,
                sampleRate: generatedFile.sampleRate,
                profileName: profileName,
                textProfileName: textProfileName
            )
        ]
        generationJobs.append(
            try! makeGenerationJob(
                jobID: requestID,
                jobKind: "file",
                createdAt: createdAt,
                updatedAt: createdAt,
                profileName: profileName,
                textProfileName: textProfileName,
                speechBackend: "qwen3",
                state: "completed",
                items: items,
                artifacts: artifacts,
                startedAt: createdAt,
                completedAt: createdAt,
                failedAt: nil,
                expiresAt: nil,
                retentionPolicy: "manual"
            )
        )
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFile: generatedFile, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generate_audio_file", profileName: profileName, events: events)
    }

    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let createdAt = Date()
        let artifacts = items.enumerated().map { index, item in
            try! makeGeneratedFile(
                artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                createdAt: createdAt,
                profileName: profileName,
                textProfileName: item.textProfileName,
                sampleRate: 24_000,
                filePath: "/tmp/\(item.artifactID ?? "\(requestID)-artifact-\(index + 1)").wav"
            )
        }
        generatedFiles.append(contentsOf: artifacts)
        let batchItems = items.enumerated().map { index, item in
            GenerationJobItemFixture(
                artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                text: item.text,
                textProfileName: item.textProfileName,
                textContext: item.textContext,
                sourceFormat: item.sourceFormat
            )
        }
        let generatedBatch = try! makeGeneratedBatch(
            batchID: requestID,
            profileName: profileName,
            textProfileName: items.first?.textProfileName,
            speechBackend: "qwen3",
            state: "completed",
            items: batchItems,
            artifacts: artifacts.map {
                GeneratedFileFixture(
                    artifactID: $0.artifactID,
                    createdAt: $0.createdAt,
                    profileName: $0.profileName,
                    textProfileName: $0.textProfileName,
                    sampleRate: $0.sampleRate,
                    filePath: $0.filePath
                )
            },
            createdAt: createdAt,
            updatedAt: createdAt,
            startedAt: createdAt,
            completedAt: createdAt,
            failedAt: nil,
            expiresAt: nil,
            retentionPolicy: "manual"
        )
        generatedBatches.append(generatedBatch)
        generationJobs.append(
            try! makeGenerationJob(
                jobID: requestID,
                jobKind: "batch",
                createdAt: createdAt,
                updatedAt: createdAt,
                profileName: profileName,
                textProfileName: items.first?.textProfileName,
                speechBackend: "qwen3",
                state: "completed",
                items: batchItems,
                artifacts: generatedBatch.artifacts.map {
                    GenerationArtifactFixture(
                        artifactID: $0.artifactID,
                        kind: "audio_wav",
                        createdAt: $0.createdAt,
                        filePath: $0.filePath,
                        sampleRate: $0.sampleRate,
                        profileName: $0.profileName,
                        textProfileName: $0.textProfileName
                    )
                },
                startedAt: generatedBatch.startedAt,
                completedAt: generatedBatch.completedAt,
                failedAt: nil,
                expiresAt: nil,
                retentionPolicy: "manual"
            )
        )
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatch: generatedBatch, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generate_batch", profileName: profileName, events: events)
    }

    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        createProfileInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: cwd
            )
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: voiceDescription,
                    sourceText: text
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "create_voice_profile_from_description", profileName: profileName, events: events)
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        createCloneInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                referenceAudioPath: referenceAudioPath,
                transcript: transcript,
                cwd: cwd
            )
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: "Imported reference audio clone.",
                    sourceText: transcript ?? "Imported clone transcript."
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "create_voice_profile_from_audio", profileName: profileName, events: events)
    }

    func listVoiceProfiles() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let profiles = self.profiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profiles: profiles, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_voice_profiles", profileName: nil, events: events)
    }

    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        if mutationRefreshBehavior == .applyMutations {
            profiles.removeAll { $0.profileName == profileName }
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "delete_voice_profile", profileName: profileName, events: events)
    }

    func generationJob(id jobID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let job = generationJobs.first { $0.jobID == jobID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJob: job, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generation_job", profileName: nil, events: events)
    }

    func listGenerationJobs() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let jobs = generationJobs
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJobs: jobs, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generation_jobs", profileName: nil, events: events)
    }

    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        guard let index = generationJobs.firstIndex(where: { $0.jobID == jobID }) else {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(
                    throwing: SpeakSwiftly.Error(
                        code: .generationJobNotFound,
                        message: "No mock generation job matched '\(jobID)'."
                    )
                )
            }
            return RuntimeRequestHandle(id: requestID, operation: "expire_generation_job", profileName: nil, events: events)
        }
        let current = generationJobs[index]
        generationJobs[index] = try! makeGenerationJob(
            jobID: current.jobID,
            jobKind: current.jobKind.rawValue,
            createdAt: current.createdAt,
            updatedAt: Date(),
            profileName: current.profileName,
            textProfileName: current.textProfileName,
            speechBackend: current.speechBackend.rawValue,
            state: "expired",
            items: current.items.map {
                GenerationJobItemFixture(
                    artifactID: $0.artifactID,
                    text: $0.text,
                    textProfileName: $0.textProfileName,
                    textContext: $0.textContext,
                    sourceFormat: $0.sourceFormat
                )
            },
            artifacts: current.artifacts.map {
                GenerationArtifactFixture(
                    artifactID: $0.artifactID,
                    kind: $0.kind.rawValue,
                    createdAt: $0.createdAt,
                    filePath: $0.filePath,
                    sampleRate: $0.sampleRate,
                    profileName: $0.profileName,
                    textProfileName: $0.textProfileName
                )
            },
            failure: current.failure.map { .init(code: $0.code, message: $0.message) },
            startedAt: current.startedAt,
            completedAt: current.completedAt,
            failedAt: current.failedAt,
            expiresAt: current.expiresAt,
            retentionPolicy: current.retentionPolicy.rawValue
        )
        let expiredJob = generationJobs[index]
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJob: expiredJob, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "expire_generation_job", profileName: nil, events: events)
    }

    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let file = generatedFiles.first { $0.artifactID == artifactID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFile: file, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generated_file", profileName: nil, events: events)
    }

    func listGeneratedFiles() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let files = generatedFiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFiles: files, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generated_files", profileName: nil, events: events)
    }

    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let batch = generatedBatches.first { $0.batchID == batchID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatch: batch, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generated_batch", profileName: nil, events: events)
    }

    func listGeneratedBatches() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let batches = generatedBatches
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatches: batches, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generated_batches", profileName: nil, events: events)
    }

    func runtimeStatus() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let status = SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3)
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, activeRequests: nil, status: status)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_runtime_status", profileName: nil, events: events)
    }

    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, activeRequests: nil, speechBackend: speechBackend)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "switch_speech_backend", profileName: nil, events: events)
    }

    func reloadModels() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let status = SpeakSwiftly.StatusEvent(stage: .residentModelReady, residentState: .ready, speechBackend: .qwen3)
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, activeRequests: nil, status: status)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "reload_models", profileName: nil, events: events)
    }

    func unloadModels() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let status = SpeakSwiftly.StatusEvent(stage: .residentModelsUnloaded, residentState: .unloaded, speechBackend: .qwen3)
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, activeRequests: nil, status: status)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "unload_models", profileName: nil, events: events)
    }

    func runtimeOverview() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        generationQueueRequestCount += 1
        playbackQueueRequestCount += 1
        playbackStateRequestCount += 1
        let overview = runtimeOverviewSummary()
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequests: nil,
                        runtimeOverview: overview
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_runtime_overview", profileName: nil, events: events)
    }

    func generationQueue() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        generationQueueRequestCount += 1
        let activeRequest = self.activeRequest.map(self.activeSummary(for:))
        let queue = self.queuedSummaries()
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequest: activeRequest,
                        activeRequests: nil,
                        queue: queue
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generation_queue", profileName: nil, events: events)
    }

    func playbackQueue() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        playbackQueueRequestCount += 1
        let activeRequest = playbackState == .idle ? nil : self.activeRequest.map(self.activeSummary(for:))
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequest: activeRequest,
                        activeRequests: nil,
                        queue: []
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_playback_queue", profileName: nil, events: events)
    }

    func playbackState() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        playbackStateRequestCount += 1
        let playbackState = self.playbackStateSummary()
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequests: nil,
                        playbackState: playbackState
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_playback_state", profileName: nil, events: events)
    }

    func pausePlayback() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        if activeRequest != nil {
            playbackState = .paused
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequests: nil,
                        playbackState: self.playbackStateSummary()
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "pause_playback", profileName: nil, events: events)
    }

    func resumePlayback() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        if activeRequest != nil {
            playbackState = .playing
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequests: nil,
                        playbackState: self.playbackStateSummary()
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "resume_playback", profileName: nil, events: events)
    }

    func clearQueue() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let clearedRequestIDs = queuedRequests.map(\.request.id)
        let clearedCount = clearedRequestIDs.count
        for queuedRequestID in clearedRequestIDs {
            cancelQueuedRequest(
                queuedRequestID,
                reason: "The request was cancelled because queued work was cleared from the mock SpeakSwiftly runtime."
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, activeRequests: nil, clearedCount: clearedCount)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "clear_playback_queue", profileName: nil, events: events)
    }

    func cancelRequest(_ requestIDToCancel: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        do {
            let cancelledRequestID = try cancelRequestNow(requestIDToCancel)
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.yield(
                    .completed(
                        SpeakSwiftly.Success(
                            id: requestID,
                            activeRequests: nil,
                            cancelledRequestID: cancelledRequestID
                        )
                    )
                )
                continuation.finish()
            }
            return RuntimeRequestHandle(id: requestID, operation: "cancel_request", profileName: nil, events: events)
        } catch {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(throwing: error)
            }
            return RuntimeRequestHandle(id: requestID, operation: "cancel_request", profileName: nil, events: events)
        }
    }
}
