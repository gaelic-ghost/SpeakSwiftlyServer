import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftlyCore
import Testing
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - Mock Runtime

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct MockRequest: Sendable {
        let id: String
        let operation: String
        let profileName: String?
    }

    struct QueuedSpeechInvocation: Sendable, Equatable {
        let text: String
        let profileName: String
        let textProfileName: String?
        let normalizationContext: SpeechNormalizationContext?
        let sourceFormat: TextForSpeech.SourceFormat?
    }

    struct CreateCloneInvocation: Sendable, Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let referenceAudioPath: String
        let transcript: String?
        let cwd: String?
    }

    struct CreateProfileInvocation: Sendable, Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let text: String
        let voiceDescription: String
        let outputPath: String?
        let cwd: String?
    }

    struct QueuedRequestState: Sendable {
        let request: MockRequest
        let continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    }

    enum SpeakBehavior: Sendable {
        case completeImmediately
        case holdOpen
    }

    enum MutationRefreshBehavior: Sendable {
        case applyMutations
        case leaveProfilesUnchanged
    }

    var profiles: [SpeakSwiftly.ProfileSummary]
    var speakBehavior: SpeakBehavior
    var mutationRefreshBehavior: MutationRefreshBehavior
    private var statusContinuation: AsyncStream<SpeakSwiftly.StatusEvent>.Continuation?
    private var activeRequest: MockRequest?
    private var activeContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
    private var queuedRequests = [QueuedRequestState]()
    private var queuedSpeechInvocations = [QueuedSpeechInvocation]()
    private var createCloneInvocations = [CreateCloneInvocation]()
    private var createProfileInvocations = [CreateProfileInvocation]()
    private var playbackState: SpeakSwiftly.PlaybackState = .idle
    private var textRuntime = TextForSpeech.Runtime()
    private var loadTextProfilesCallCount = 0
    private var saveTextProfilesCallCount = 0
    private var generatedFiles = [SpeakSwiftly.GeneratedFile]()
    private var generatedBatches = [SpeakSwiftly.GeneratedBatch]()
    private var generationJobs = [SpeakSwiftly.GenerationJob]()
    private var generationQueueRequestCount = 0
    private var playbackQueueRequestCount = 0
    private var playbackStateRequestCount = 0

    // MARK: - Lifecycle

    init(
        profiles: [SpeakSwiftly.ProfileSummary] = [sampleProfile()],
        speakBehavior: SpeakBehavior = .completeImmediately,
        mutationRefreshBehavior: MutationRefreshBehavior = .applyMutations
    ) {
        self.profiles = profiles
        self.speakBehavior = speakBehavior
        self.mutationRefreshBehavior = mutationRefreshBehavior
    }

    func start() {}

    func shutdown() async {
        statusContinuation?.finish()
        activeContinuation?.finish()
        activeContinuation = nil
        activeRequest = nil
        playbackState = .idle
        for queued in queuedRequests {
            queued.continuation.finish()
        }
        queuedRequests.removeAll()
    }

    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
        }
    }

    // MARK: - Runtime Protocol

    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let request = MockRequest(id: requestID, operation: "queue_speech_live", profileName: profileName)
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
        return RuntimeRequestHandle(id: requestID, operation: "queue_speech_file", profileName: profileName, events: events)
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
        return RuntimeRequestHandle(id: requestID, operation: "queue_speech_batch", profileName: profileName, events: events)
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

    func activeTextProfile() async -> TextForSpeech.Profile {
        textRuntime.profiles.active() ?? .default
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        .init(id: "base", name: "Base")
    }

    func textProfile(id profileID: String) async -> TextForSpeech.Profile? {
        textRuntime.profiles.stored(id: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        textRuntime.profiles.list()
    }

    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile {
        textRuntime.profiles.effective(id: profileID) ?? .default
    }

    func loadTextProfiles() async throws {
        loadTextProfilesCallCount += 1
    }

    func saveTextProfiles() async throws {
        saveTextProfilesCallCount += 1
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement]
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.create(id: id, name: name, replacements: replacements)
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.profiles.store(profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.profiles.use(profile)
    }

    func removeTextProfile(id profileID: String) async throws {
        textRuntime.profiles.delete(id: profileID)
    }

    func resetTextProfile() async throws {
        textRuntime.profiles.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        textRuntime.profiles.add(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement, toStoredProfileID: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement, inStoredProfileID: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID, fromStoredProfileID: profileID)
    }

    // MARK: - Test Control

    func publishStatus(_ stage: SpeakSwiftly.StatusStage) {
        let residentState: SpeakSwiftly.ResidentModelState = switch stage {
        case .warmingResidentModel:
            .warming
        case .residentModelReady:
            .ready
        case .residentModelsUnloaded:
            .unloaded
        case .residentModelFailed:
            .failed
        }
        statusContinuation?.yield(.init(stage: stage, residentState: residentState, speechBackend: .qwen3))
    }

    func finishHeldSpeak(id: String) {
        guard activeRequest?.id == id, let continuation = activeContinuation else { return }
        continuation.yield(
            SpeakSwiftly.RequestEvent.progress(
                .init(id: id, stage: .playbackFinished)
            )
        )
            continuation.yield(
                SpeakSwiftly.RequestEvent.completed(
                    .init(id: id)
            )
        )
        continuation.finish()
        playbackState = .idle
        activeContinuation = nil
        activeRequest = nil
        startNextQueuedRequestIfNeeded()
    }

    func publishHeldSpeakProgress(id: String, stage: SpeakSwiftly.ProgressStage) {
        guard activeRequest?.id == id, let continuation = activeContinuation else { return }
        continuation.yield(.progress(.init(id: id, stage: stage)))
    }

    func latestQueuedSpeechInvocation() -> QueuedSpeechInvocation? {
        queuedSpeechInvocations.last
    }

    func latestCreateProfileInvocation() -> CreateProfileInvocation? {
        createProfileInvocations.last
    }

    func latestCreateCloneInvocation() -> CreateCloneInvocation? {
        createCloneInvocations.last
    }

    func textProfilePersistenceActionCounts() -> (load: Int, save: Int) {
        (loadTextProfilesCallCount, saveTextProfilesCallCount)
    }

    func runtimeRefreshActionCounts() -> (generationQueue: Int, playbackQueue: Int, playbackState: Int) {
        (
            generationQueueRequestCount,
            playbackQueueRequestCount,
            playbackStateRequestCount
        )
    }

    // MARK: - Internal Helpers

    private func startActiveRequest(
        _ request: MockRequest,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    ) {
        activeRequest = request
        playbackState = .playing
        continuation.yield(.started(.init(id: request.id, op: request.operation)))

        if speakBehavior == .completeImmediately {
            continuation.yield(.progress(.init(id: request.id, stage: .startingPlayback)))
            continuation.yield(.completed(.init(id: request.id)))
            continuation.finish()
            playbackState = .idle
            activeRequest = nil
            activeContinuation = nil
            startNextQueuedRequestIfNeeded()
        } else {
            activeContinuation = continuation
        }
    }

    private func startNextQueuedRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }
        let next = queuedRequests.removeFirst()
        startActiveRequest(next.request, continuation: next.continuation)
    }

    private func activeSummary(for request: MockRequest) -> SpeakSwiftly.ActiveRequest {
        .init(id: request.id, op: request.operation, profileName: request.profileName)
    }

    private func queuedSummaries() -> [SpeakSwiftly.QueuedRequest] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.operation,
                profileName: queued.request.profileName,
                queuePosition: offset + 1
            )
        }
    }

    private func playbackStateSummary() -> SpeakSwiftly.PlaybackStateSnapshot {
        .init(
            state: playbackState,
            activeRequest: playbackState == .idle ? nil : activeRequest.map(activeSummary(for:)),
            isStableForConcurrentGeneration: playbackState == .playing,
            isRebuffering: false,
            stableBufferedAudioMS: playbackState == .playing ? 320 : nil,
            stableBufferTargetMS: playbackState == .playing ? 400 : nil
        )
    }

    private func runtimeOverviewSummary() -> SpeakSwiftly.RuntimeOverview {
        let generationActiveRequest = activeRequest.map(activeSummary(for:))
        let generationQueue = SpeakSwiftly.QueueSnapshot(
            queueType: "generation",
            activeRequest: generationActiveRequest,
            activeRequests: generationActiveRequest.map { [$0] },
            queue: queuedSummaries()
        )
        let playbackActiveRequest = playbackState == .idle ? nil : activeRequest.map(activeSummary(for:))
        let playbackQueue = SpeakSwiftly.QueueSnapshot(
            queueType: "playback",
            activeRequest: playbackActiveRequest,
            activeRequests: playbackActiveRequest.map { [$0] },
            queue: []
        )
        let status = SpeakSwiftly.StatusEvent(
            stage: .residentModelReady,
            residentState: .ready,
            speechBackend: .qwen3
        )
        return .init(
            status: status,
            speechBackend: .qwen3,
            generationQueue: generationQueue,
            playbackQueue: playbackQueue,
            playbackState: playbackStateSummary()
        )
    }

    private func cancelQueuedRequest(_ requestID: String, reason: String) {
        guard let index = queuedRequests.firstIndex(where: { $0.request.id == requestID }) else { return }
        let queued = queuedRequests.remove(at: index)
        queued.continuation.finish(
            throwing: SpeakSwiftly.Error(code: .requestCancelled, message: reason)
        )
    }

    private func cancelRequestNow(_ requestID: String) throws -> String {
        if activeRequest?.id == requestID {
            activeContinuation?.finish(
                throwing: SpeakSwiftly.Error(
                    code: .requestCancelled,
                    message: "The request was cancelled by the mock SpeakSwiftly runtime control surface."
                )
            )
            playbackState = .idle
            activeContinuation = nil
            activeRequest = nil
            startNextQueuedRequestIfNeeded()
            return requestID
        }

        if queuedRequests.contains(where: { $0.request.id == requestID }) {
            cancelQueuedRequest(
                requestID,
                reason: "The queued request was cancelled by the mock SpeakSwiftly runtime control surface."
            )
            return requestID
        }

        throw SpeakSwiftly.Error(
            code: .requestNotFound,
            message: "The mock SpeakSwiftly runtime could not find request '\(requestID)' to cancel."
        )
    }
}
