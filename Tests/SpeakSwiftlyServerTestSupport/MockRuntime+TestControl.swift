import Foundation
import SpeakSwiftly

// MARK: - Mock Runtime Test Control

@available(macOS 14, *)
package extension MockRuntime {
    func publishStatus(_ state: SpeakSwiftly.RuntimeState) {
        runtimeState = state
        runtimeUpdateContinuation?.yield(runtimeUpdate(state))
    }

    func publishPlaybackUpdate(_ event: SpeakSwiftly.PlaybackEvent) {
        playbackUpdateContinuation?.yield(playbackUpdate(event))
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
                .empty,
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

    func replaceScriptedAudioStreamChunks(_ chunks: [SpeakSwiftly.GeneratedAudioChunk]) {
        scriptedAudioStreamChunks = chunks
    }

    func latestAudioStreamInvocation() -> AudioStreamInvocation? {
        audioStreamInvocations.last
    }

    func latestCreateProfileInvocation() -> CreateProfileInvocation? {
        createProfileInvocations.last
    }

    func createProfileInvocationNames() -> [String] {
        createProfileInvocations.map(\.profileName)
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

    func rerollProfileInvocationNames() -> [String] {
        rerollProfileInvocations.map(\.profileName)
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
package extension MockRuntime {
    func startActiveRequest(
        _ request: MockRequest,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation,
    ) {
        activeRequest = request
        if request.operation == "switch_speech_backend", let requestedSpeechBackend = request.requestedSpeechBackend {
            continuation.yield(.started(.init(id: request.id, kind: SpeakSwiftly.RequestKind(rawValue: request.operation))))
            activeSpeechBackend = requestedSpeechBackend
            continuation.yield(
                .completed(
                    .runtimeUpdate(runtimeUpdate(.residentModelReady)),
                ),
            )
            continuation.finish()
            activeRequest = nil
            startNextQueuedRequestIfNeeded()
            return
        }

        playbackState = .playing
        continuation.yield(.started(.init(id: request.id, kind: SpeakSwiftly.RequestKind(rawValue: request.operation))))

        if speakBehavior == .completeImmediately {
            continuation.yield(.progress(.init(id: request.id, stage: .startingPlayback)))
            continuation.yield(.completed(.empty))
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
        .init(
            id: request.id,
            kind: SpeakSwiftly.RequestKind(rawValue: request.operation),
            voiceProfile: request.profileName,
            requestContext: nil,
        )
    }

    func queuedSummaries() -> [SpeakSwiftly.QueuedRequest] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                kind: SpeakSwiftly.RequestKind(rawValue: queued.request.operation),
                voiceProfile: queued.request.profileName,
                requestContext: nil,
                queuePosition: offset + 1,
            )
        }
    }

    func playbackSnapshotSummary() -> SpeakSwiftly.PlaybackSnapshot {
        decodedSpeakSwiftlyValue(
            SpeakSwiftly.PlaybackSnapshot.self,
            from: PlaybackSnapshotPayload(
                sequence: 0,
                capturedAt: Date(),
                state: playbackState,
                activeRequest: playbackState == .idle ? nil : activeRequest.map { activeSummary(for: $0) },
                queuedRequests: [],
                isRebuffering: false,
                stableBufferedAudioMS: playbackState == .playing ? 320 : nil,
                stableBufferTargetMS: playbackState == .playing ? 400 : nil,
            ),
        )
    }

    func generationSnapshotSummary() -> SpeakSwiftly.GenerateSnapshot {
        let generationActiveRequest = activeRequest.map { activeSummary(for: $0) }
        return decodedSpeakSwiftlyValue(
            SpeakSwiftly.GenerateSnapshot.self,
            from: GenerateSnapshotPayload(
                sequence: 0,
                capturedAt: Date(),
                state: generationActiveRequest == nil ? SpeakSwiftly.GenerateState.idle : .running,
                activeRequests: generationActiveRequest.map { [$0] } ?? [],
                queuedRequests: queuedSummaries(),
            ),
        )
    }

    func runtimeSnapshotSummary(_ state: SpeakSwiftly.RuntimeState? = nil) -> SpeakSwiftly.RuntimeSnapshot {
        let resolvedState = state ?? runtimeState
        return decodedSpeakSwiftlyValue(
            SpeakSwiftly.RuntimeSnapshot.self,
            from: RuntimeSnapshotPayload(
                sequence: 0,
                capturedAt: Date(),
                state: resolvedState,
                speechBackend: activeSpeechBackend,
                residentState: residentState(for: resolvedState),
                defaultVoiceProfile: "default",
                storage: RuntimeStorageSnapshotPayload(
                    stateRootPath: NSTemporaryDirectory(),
                    profileStoreRootPath: NSTemporaryDirectory(),
                    configurationPath: NSTemporaryDirectory(),
                    textProfilesPath: NSTemporaryDirectory(),
                    generatedFilesRootPath: NSTemporaryDirectory(),
                    generationJobsRootPath: NSTemporaryDirectory(),
                ),
            ),
        )
    }

    func runtimeUpdate(_ state: SpeakSwiftly.RuntimeState) -> SpeakSwiftly.RuntimeUpdate {
        decodedSpeakSwiftlyValue(
            SpeakSwiftly.RuntimeUpdate.self,
            from: RuntimeUpdatePayload(
                sequence: 0,
                date: Date(),
                state: state,
                event: SpeakSwiftly.RuntimeEvent.stateChanged(state),
            ),
        )
    }

    func playbackUpdate(_ event: SpeakSwiftly.PlaybackEvent) -> SpeakSwiftly.PlaybackUpdate {
        decodedSpeakSwiftlyValue(
            SpeakSwiftly.PlaybackUpdate.self,
            from: PlaybackUpdatePayload(
                sequence: 1,
                date: Date(),
                state: playbackState,
                event: event,
            ),
        )
    }

    func residentState(for state: SpeakSwiftly.RuntimeState) -> SpeakSwiftly.ResidentModelState {
        switch state {
            case .warmingResidentModel:
                .warming
            case .residentModelReady:
                .ready
            case .residentModelsUnloaded:
                .unloaded
            case .residentModelFailed:
                .failed
        }
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

private struct RuntimeUpdatePayload: Encodable {
    let sequence: Int
    let date: Date
    let state: SpeakSwiftly.RuntimeState
    let event: SpeakSwiftly.RuntimeEvent
}

private struct GenerateSnapshotPayload: Encodable {
    let sequence: Int
    let capturedAt: Date
    let state: SpeakSwiftly.GenerateState
    let activeRequests: [SpeakSwiftly.ActiveRequest]
    let queuedRequests: [SpeakSwiftly.QueuedRequest]
}

private struct PlaybackSnapshotPayload: Encodable {
    let sequence: Int
    let capturedAt: Date
    let state: SpeakSwiftly.PlaybackState
    let activeRequest: SpeakSwiftly.ActiveRequest?
    let queuedRequests: [SpeakSwiftly.QueuedRequest]
    let isRebuffering: Bool
    let stableBufferedAudioMS: Int?
    let stableBufferTargetMS: Int?
}

private struct PlaybackUpdatePayload: Encodable {
    let sequence: Int
    let date: Date
    let state: SpeakSwiftly.PlaybackState
    let event: SpeakSwiftly.PlaybackEvent
}

private struct RuntimeSnapshotPayload: Encodable {
    let sequence: Int
    let capturedAt: Date
    let state: SpeakSwiftly.RuntimeState
    let speechBackend: SpeakSwiftly.SpeechBackend
    let residentState: SpeakSwiftly.ResidentModelState
    let defaultVoiceProfile: String
    let storage: RuntimeStorageSnapshotPayload
}

private struct RuntimeStorageSnapshotPayload: Encodable {
    let stateRootPath: String
    let profileStoreRootPath: String
    let configurationPath: String
    let textProfilesPath: String
    let generatedFilesRootPath: String
    let generationJobsRootPath: String

    enum CodingKeys: String, CodingKey {
        case stateRootPath = "state_root_path"
        case profileStoreRootPath = "profile_store_root_path"
        case configurationPath = "configuration_path"
        case textProfilesPath = "text_profiles_path"
        case generatedFilesRootPath = "generated_files_root_path"
        case generationJobsRootPath = "generation_jobs_root_path"
    }
}

private func decodedSpeakSwiftlyValue<Value: Decodable>(
    _ type: Value.Type,
    from payload: some Encodable,
) -> Value {
    do {
        let data = try JSONEncoder().encode(payload)
        return try JSONDecoder().decode(type, from: data)
    } catch {
        fatalError("MockRuntime could not construct \(type) from its test payload. Likely cause: the resolved SpeakSwiftly Codable shape changed. Error: \(error.localizedDescription)")
    }
}
