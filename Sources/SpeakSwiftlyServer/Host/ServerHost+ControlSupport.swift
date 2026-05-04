import Foundation
import SpeakSwiftly

extension ServerHost {
    // MARK: - Playback Control Helpers

    func playbackStateResponse(
        handle: RuntimeRequestHandle,
        requestName: String,
    ) async throws -> PlaybackStateResponse {
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        guard case let .playbackState(playbackState) = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the '\(requestName)' control request, but it did not return a playback state payload.",
            )
        }

        return .init(playback: .init(summary: playbackState))
    }

    func playbackControlResponse(
        handle: RuntimeRequestHandle,
        requestName: String,
        expectedState: SpeakSwiftly.PlaybackState,
    ) async throws -> PlaybackStateResponse {
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request.",
        )
        if case let .playbackState(playbackState) = completion, playbackState.state == expectedState {
            let response = PlaybackStateResponse(playback: .init(summary: playbackState))
            await applyPlaybackControlSnapshot(response.playback, expectedState: expectedState)
            return response
        }
        let response = try await settledPlaybackStateResponse(
            for: requestName,
            expectedState: expectedState,
        )
        await applyPlaybackControlSnapshot(response.playback, expectedState: expectedState)
        return response
    }

    func settledPlaybackStateResponse(
        for requestName: String,
        expectedState: SpeakSwiftly.PlaybackState,
    ) async throws -> PlaybackStateResponse {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        var lastResponse: PlaybackStateResponse?

        while true {
            let response = try await playbackStateResponse(
                handle: runtime.playbackState(),
                requestName: requestName,
            )
            lastResponse = response
            if response.playback.state == expectedState.rawValue {
                return response
            }
            if clock.now >= deadline {
                return optimisticPlaybackStateResponse(
                    from: lastResponse ?? response,
                    expectedState: expectedState,
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func optimisticPlaybackStateResponse(
        from response: PlaybackStateResponse,
        expectedState: SpeakSwiftly.PlaybackState,
    ) -> PlaybackStateResponse {
        let status = PlaybackStatusSnapshot(
            state: expectedState.rawValue,
            activeRequest: response.playback.activeRequest ?? playbackStatus.activeRequest,
            isStableForConcurrentGeneration: expectedState == .playing
                ? response.playback.isStableForConcurrentGeneration
                : false,
            isRebuffering: expectedState == .playing
                ? response.playback.isRebuffering
                : false,
            stableBufferedAudioMS: expectedState == .playing
                ? response.playback.stableBufferedAudioMS
                : nil,
            stableBufferTargetMS: expectedState == .playing
                ? response.playback.stableBufferTargetMS
                : nil,
        )
        return .init(playback: status)
    }

    func applyPlaybackControlSnapshot(
        _ snapshot: PlaybackStatusSnapshot,
        expectedState: SpeakSwiftly.PlaybackState,
    ) async {
        let previousPlaybackStatus = playbackStatus
        playbackStatus = snapshot
        if playbackStatus != previousPlaybackStatus {
            hostEventContinuation.yield(.playbackChanged(playbackStatus))
            await requestPublish(mode: .coalesced, refreshRuntimeState: false)
        }
        if expectedState == .paused {
            playbackQueueStatus = .init(
                queueType: playbackQueueStatus.queueType,
                activeCount: playbackQueueStatus.activeRequest == nil ? 0 : 1,
                queuedCount: playbackQueueStatus.queuedCount,
                activeRequest: playbackStatus.activeRequest,
                activeRequests: playbackStatus.activeRequest.map { [$0] } ?? [],
                queuedRequests: playbackQueueStatus.queuedRequests,
            )
        } else if expectedState == .playing, let activeRequest = playbackStatus.activeRequest {
            playbackQueueStatus = .init(
                queueType: playbackQueueStatus.queueType,
                activeCount: 1,
                queuedCount: playbackQueueStatus.queuedCount,
                activeRequest: activeRequest,
                activeRequests: [activeRequest],
                queuedRequests: playbackQueueStatus.queuedRequests,
            )
        }
    }

    // MARK: - Runtime Responses

    func runtimeStatusResponse(
        handle: RuntimeRequestHandle,
        requestName: String,
    ) async throws -> RuntimeStatusResponse {
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the \(requestName) request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the \(requestName) request.",
        )
        guard case let .runtimeStatus(status: status?, speechBackend: _) = completion else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the \(requestName) request, but it did not return a status payload.",
            )
        }

        await self.handle(status: status)
        return .init(status: status, runtimeBackendTransition: runtimeBackendTransitionSnapshot())
    }

    func awaitImmediateCompletion(
        handle: RuntimeRequestHandle,
        missingTerminalMessage: String,
        unexpectedFailureMessagePrefix: String,
    ) async throws -> SpeakSwiftly.RequestCompletion {
        do {
            for try await event in handle.events {
                if case let .completed(completion) = event {
                    return completion
                }
            }
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: missingTerminalMessage,
            )
        } catch let error as SpeakSwiftly.Error {
            throw error
        } catch {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "\(unexpectedFailureMessagePrefix) \(error.localizedDescription)",
            )
        }
    }
}
