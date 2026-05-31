import Foundation
import SpeakSwiftly

package extension ServerHost {
    func mapPlaybackEvent(_ update: SpeakSwiftly.PlaybackUpdate) -> PlaybackEventSnapshot {
        let base = PlaybackEventBase(
            sequence: update.sequence,
            publishedAt: TimestampFormatter.string(from: update.date),
            state: update.state.rawValue,
        )

        switch update.event {
            case let .stateChanged(state):
                return base.snapshot(event: "state_changed", state: state.rawValue)
            case let .started(requestID):
                return base.snapshot(event: "started", requestID: requestID)
            case let .activeRequestChanged(activeRequest):
                return base.snapshot(
                    event: "active_request_changed",
                    requestID: activeRequest?.id,
                    activeRequest: activeRequest.map(ActiveRequestSnapshot.init(summary:)),
                )
            case let .queueChanged(activeRequest, queuedRequests):
                return base.snapshot(
                    event: "queue_changed",
                    requestID: activeRequest?.id,
                    activeRequest: activeRequest.map(ActiveRequestSnapshot.init(summary:)),
                    queuedRequests: queuedRequests.map(QueuedRequestSnapshot.init(summary:)),
                )
            case let .firstChunk(requestID):
                return base.snapshot(event: "first_chunk", requestID: requestID)
            case let .prerollReady(requestID, bufferedAudioMS, startupBufferTargetMS):
                return base.snapshot(
                    event: "preroll_ready",
                    requestID: requestID,
                    bufferedAudioMS: bufferedAudioMS,
                    bufferTargetMS: startupBufferTargetMS,
                )
            case let .rebufferStarted(requestID, queuedAudioMS, resumeBufferTargetMS):
                return base.snapshot(
                    event: "rebuffer_started",
                    requestID: requestID,
                    queuedAudioMS: queuedAudioMS,
                    bufferTargetMS: resumeBufferTargetMS,
                )
            case let .rebufferResumed(requestID, bufferedAudioMS, resumeBufferTargetMS):
                return base.snapshot(
                    event: "rebuffer_resumed",
                    requestID: requestID,
                    bufferedAudioMS: bufferedAudioMS,
                    bufferTargetMS: resumeBufferTargetMS,
                )
            case let .completed(requestID):
                return base.snapshot(event: "completed", requestID: requestID)
            case let .outputDeviceChanged(previousDevice, currentDevice):
                return base.snapshot(
                    event: "output_device_changed",
                    previousDevice: previousDevice,
                    currentDevice: currentDevice,
                )
            case let .interruptionChanged(isInterrupted, shouldResume):
                return base.snapshot(
                    event: "interruption_changed",
                    isInterrupted: isInterrupted,
                    shouldResume: shouldResume,
                )
        }
    }
}

private struct PlaybackEventBase {
    let sequence: Int
    let publishedAt: String
    let state: String

    func snapshot(
        event: String,
        state overrideState: String? = nil,
        requestID: String? = nil,
        activeRequest: ActiveRequestSnapshot? = nil,
        queuedRequests: [QueuedRequestSnapshot]? = nil,
        bufferedAudioMS: Int? = nil,
        queuedAudioMS: Int? = nil,
        bufferTargetMS: Int? = nil,
        previousDevice: String? = nil,
        currentDevice: String? = nil,
        isInterrupted: Bool? = nil,
        shouldResume: Bool? = nil,
    ) -> PlaybackEventSnapshot {
        .init(
            sequence: sequence,
            publishedAt: publishedAt,
            event: event,
            state: overrideState ?? state,
            requestID: requestID,
            activeRequest: activeRequest,
            queuedRequests: queuedRequests,
            bufferedAudioMS: bufferedAudioMS,
            queuedAudioMS: queuedAudioMS,
            bufferTargetMS: bufferTargetMS,
            previousDevice: previousDevice,
            currentDevice: currentDevice,
            isInterrupted: isInterrupted,
            shouldResume: shouldResume,
        )
    }
}
