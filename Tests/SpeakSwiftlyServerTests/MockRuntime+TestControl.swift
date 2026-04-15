import Foundation
import SpeakSwiftly

// MARK: - Mock Runtime Test Control

@available(macOS 14, *)
extension MockRuntime {
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
                .init(id: id, stage: .playbackFinished),
            ),
        )
        continuation.yield(
            SpeakSwiftly.RequestEvent.completed(
                .init(id: id),
            ),
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

    func latestRenameProfileInvocation() -> RenameProfileInvocation? {
        renameProfileInvocations.last
    }

    func latestRerollProfileInvocation() -> RerollProfileInvocation? {
        rerollProfileInvocations.last
    }

    func textProfilePersistenceActionCounts() -> (load: Int, save: Int) {
        (loadTextProfilesCallCount, saveTextProfilesCallCount)
    }

    func runtimeRefreshActionCounts() -> (generationQueue: Int, playbackQueue: Int, playbackState: Int) {
        (
            generationQueueRequestCount,
            playbackQueueRequestCount,
            playbackStateRequestCount,
        )
    }
}

// MARK: - Mock Runtime Internals

@available(macOS 14, *)
extension MockRuntime {
    func startActiveRequest(
        _ request: MockRequest,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation,
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

    func startNextQueuedRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }

        let next = queuedRequests.removeFirst()
        startActiveRequest(next.request, continuation: next.continuation)
    }

    func activeSummary(for request: MockRequest) -> SpeakSwiftly.ActiveRequest {
        .init(id: request.id, op: request.operation, profileName: request.profileName)
    }

    func queuedSummaries() -> [SpeakSwiftly.QueuedRequest] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.operation,
                profileName: queued.request.profileName,
                queuePosition: offset + 1,
            )
        }
    }

    func playbackStateSummary() -> SpeakSwiftly.PlaybackStateSnapshot {
        .init(
            state: playbackState,
            activeRequest: playbackState == .idle ? nil : activeRequest.map(activeSummary(for:)),
            isStableForConcurrentGeneration: playbackState == .playing,
            isRebuffering: false,
            stableBufferedAudioMS: playbackState == .playing ? 320 : nil,
            stableBufferTargetMS: playbackState == .playing ? 400 : nil,
        )
    }

    func runtimeOverviewSummary() -> SpeakSwiftly.RuntimeOverview {
        let generationActiveRequest = activeRequest.map(activeSummary(for:))
        let generationQueue = SpeakSwiftly.QueueSnapshot(
            queueType: "generation",
            activeRequest: generationActiveRequest,
            activeRequests: generationActiveRequest.map { [$0] },
            queue: queuedSummaries(),
        )
        let playbackActiveRequest = playbackState == .idle ? nil : activeRequest.map(activeSummary(for:))
        let playbackQueue = SpeakSwiftly.QueueSnapshot(
            queueType: "playback",
            activeRequest: playbackActiveRequest,
            activeRequests: playbackActiveRequest.map { [$0] },
            queue: [],
        )
        let status = SpeakSwiftly.StatusEvent(
            stage: .residentModelReady,
            residentState: .ready,
            speechBackend: .qwen3,
        )
        return .init(
            status: status,
            speechBackend: .qwen3,
            generationQueue: generationQueue,
            playbackQueue: playbackQueue,
            playbackState: playbackStateSummary(),
        )
    }

    func cancelQueuedRequest(_ requestID: String, reason: String) {
        guard let index = queuedRequests.firstIndex(where: { $0.request.id == requestID }) else { return }

        let queued = queuedRequests.remove(at: index)
        queued.continuation.finish(
            throwing: SpeakSwiftly.Error(code: .requestCancelled, message: reason),
        )
    }

    func cancelRequestNow(_ requestID: String) throws -> String {
        if activeRequest?.id == requestID {
            activeContinuation?.finish(
                throwing: SpeakSwiftly.Error(
                    code: .requestCancelled,
                    message: "The request was cancelled by the mock SpeakSwiftly runtime control surface.",
                ),
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
                reason: "The queued request was cancelled by the mock SpeakSwiftly runtime control surface.",
            )
            return requestID
        }

        throw SpeakSwiftly.Error(
            code: .requestNotFound,
            message: "The mock SpeakSwiftly runtime could not find request '\(requestID)' to cancel.",
        )
    }
}
