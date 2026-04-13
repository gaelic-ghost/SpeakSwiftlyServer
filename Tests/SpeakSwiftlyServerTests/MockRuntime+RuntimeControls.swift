import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer

// MARK: - Mock Runtime Controls

@available(macOS 14, *)
extension MockRuntime {
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
