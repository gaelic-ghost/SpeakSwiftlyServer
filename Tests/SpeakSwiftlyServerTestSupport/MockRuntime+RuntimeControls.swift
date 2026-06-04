import Foundation
import SpeakSwiftly
import SpeakSwiftlyServer
import SSSCore
import SSSHTTP
import SSSMCP

// MARK: - Mock Runtime Controls

@available(macOS 14, *)
package extension MockRuntime {
    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let request = MockRequest(
            id: requestID,
            operation: "switch_speech_backend",
            profileName: nil,
            requestedSpeechBackend: speechBackend,
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a backend switch continuation for request '\(requestID)'.")
        }

        if activeRequest == nil {
            startActiveRequest(request, continuation: continuation)
        } else {
            queuedRequests.append(.init(request: request, continuation: continuation))
            continuation.yield(
                .queued(
                    .init(
                        id: requestID,
                        reason: .waitingForActiveRequest,
                        queuePosition: queuedRequests.count,
                    ),
                ),
            )
        }
        return RuntimeRequestHandle(id: requestID, operation: "switch_speech_backend", profileName: nil, events: events)
    }

    func reloadModels() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        runtimeState = .residentModelReady
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(.runtimeUpdate(self.runtimeUpdate(.residentModelReady))))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "reload_models", profileName: nil, events: events)
    }

    func unloadModels() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        runtimeState = .residentModelsUnloaded
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(.runtimeUpdate(self.runtimeUpdate(.residentModelsUnloaded))))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "unload_models", profileName: nil, events: events)
    }

    func generationQueue() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        generationQueueRequestCount += 1
        let activeRequest = activeRequest.map { activeSummary(for: $0) }
        let queue = queuedSummaries()
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    .queue(
                        activeRequests: activeRequest.map { [$0] } ?? [],
                        queuedRequests: queue,
                    ),
                ),
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generation_queue_snapshot", profileName: nil, events: events)
    }

    func playbackQueue() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        playbackQueueRequestCount += 1
        let activeRequest = playbackState == .idle ? nil : activeRequest.map { activeSummary(for: $0) }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    .queue(
                        activeRequests: activeRequest.map { [$0] } ?? [],
                        queuedRequests: [],
                    ),
                ),
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "playback_queue_snapshot", profileName: nil, events: events)
    }

    func recentGeneratedAudio() async -> SpeakSwiftly.RecentGeneratedAudioSnapshot {
        recentGeneratedAudioSnapshot
    }

    func recentGeneratedAudioChunks(for recentAudioID: String) async -> [SpeakSwiftly.GeneratedAudioChunk] {
        recentGeneratedAudioChunks[recentAudioID] ?? []
    }

    func replayRecentAudio(
        id recentAudioID: String,
        mode: SpeakSwiftly.RecentGeneratedAudioReplayMode,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> RuntimeRequestHandle {
        replayRecentAudioInvocations.append((recentAudioID, mode, requestContext))
        let requestID = UUID().uuidString
        let request = MockRequest(
            id: requestID,
            operation: "replay_recent_audio",
            profileName: recentGeneratedAudioSnapshot.items.first { $0.id == recentAudioID }?.voiceProfileName,
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a recent-audio replay continuation for request '\(requestID)'.")
        }

        startActiveRequest(request, continuation: continuation)
        return RuntimeRequestHandle(id: requestID, operation: "replay_recent_audio", profileName: request.profileName, events: events)
    }

    func replayRecentAudioAll(
        mode: SpeakSwiftly.RecentGeneratedAudioReplayMode,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> [RuntimeRequestHandle] {
        replayRecentAudioAllInvocations.append((mode, requestContext))
        var handles = [RuntimeRequestHandle]()
        for item in recentGeneratedAudioSnapshot.items where item.bufferState == .complete {
            await handles.append(
                replayRecentAudio(
                    id: item.id,
                    mode: mode,
                    requestContext: requestContext,
                ),
            )
        }
        return handles
    }

    func clearRecentGeneratedAudio() async {
        clearRecentGeneratedAudioCallCount += 1
        recentGeneratedAudioSnapshot = .init(
            items: [],
            limit: recentGeneratedAudioSnapshot.limit,
            memorySecondsPerItem: recentGeneratedAudioSnapshot.memorySecondsPerItem,
        )
        recentGeneratedAudioChunks.removeAll()
    }

    func pausePlayback() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        if activeRequest != nil {
            playbackState = .paused
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    .playbackSnapshot(self.playbackSnapshotSummary()),
                ),
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
                    .playbackSnapshot(self.playbackSnapshotSummary()),
                ),
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "resume_playback", profileName: nil, events: events)
    }

    func clearQueue() async -> RuntimeRequestHandle {
        await clearQueue(.generation, operation: "clear_queue")
    }

    func clearQueue(_ queueType: SpeakSwiftly.QueueType) async -> RuntimeRequestHandle {
        await clearQueue(queueType, operation: "clear_\(queueType.rawValue)_queue")
    }

    private func clearQueue(_ queueType: SpeakSwiftly.QueueType, operation: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let clearedRequestIDs = queueType == .generation ? queuedRequests.map(\.request.id) : []
        let clearedCount = clearedRequestIDs.count
        for queuedRequestID in clearedRequestIDs {
            cancelQueuedRequest(
                queuedRequestID,
                reason: "The request was cancelled because queued work was cleared from the mock SpeakSwiftly runtime.",
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(.queueCleared(count: clearedCount)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: operation, profileName: nil, events: events)
    }

    func cancelRequest(_ requestIDToCancel: String) async -> RuntimeRequestHandle {
        await cancel(requestIDToCancel, operation: "cancel_request")
    }

    func cancel(_ queueType: SpeakSwiftly.QueueType, requestID requestIDToCancel: String) async -> RuntimeRequestHandle {
        await cancel(requestIDToCancel, operation: "cancel_\(queueType.rawValue)")
    }

    private func cancel(_ requestIDToCancel: String, operation: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        do {
            let cancelledRequestID = try cancelRequestNow(requestIDToCancel)
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.yield(
                    .completed(
                        .requestCancelled(id: cancelledRequestID),
                    ),
                )
                continuation.finish()
            }
            return RuntimeRequestHandle(id: requestID, operation: operation, profileName: nil, events: events)
        } catch {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(throwing: error)
            }
            return RuntimeRequestHandle(id: requestID, operation: operation, profileName: nil, events: events)
        }
    }
}
