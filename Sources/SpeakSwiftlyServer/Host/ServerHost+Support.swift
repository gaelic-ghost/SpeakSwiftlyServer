import Foundation
import Hummingbird
import SpeakSwiftlyCore

// MARK: - Host Support

extension ServerHost {
    // MARK: - Transport and Error Tracking

    func updateTransportStatus(named name: String, state: String) {
        guard let current = transportStatuses[name], current.enabled else {
            return
        }
        let updated = TransportStatusSnapshot(
            name: current.name,
            enabled: current.enabled,
            state: state,
            host: current.host,
            port: current.port,
            path: current.path,
            advertisedAddress: current.advertisedAddress
        )
        guard updated != current else {
            return
        }
        transportStatuses[name] = updated
        hostEventContinuation.yield(.transportChanged(updated))
    }

    static func initialTransportStatuses(
        httpConfig: HTTPConfig,
        mcpConfig: MCPConfig
    ) -> [String: TransportStatusSnapshot] {
        let http = TransportStatusSnapshot(
            name: "http",
            enabled: httpConfig.enabled,
            state: httpConfig.enabled ? "stopped" : "disabled",
            host: httpConfig.enabled ? httpConfig.host : nil,
            port: httpConfig.enabled ? httpConfig.port : nil,
            path: nil,
            advertisedAddress: httpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)" : nil
        )
        let mcp = TransportStatusSnapshot(
            name: "mcp",
            enabled: mcpConfig.enabled,
            state: mcpConfig.enabled ? "stopped" : "disabled",
            host: mcpConfig.enabled ? httpConfig.host : nil,
            port: mcpConfig.enabled ? httpConfig.port : nil,
            path: mcpConfig.enabled ? mcpConfig.path : nil,
            advertisedAddress: mcpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)\(mcpConfig.path)" : nil
        )
        return [
            http.name: http,
            mcp.name: mcp,
        ]
    }

    func recordRecentError(source: String, code: String, message: String) {
        if let last = recentErrors.last,
           last.source == source,
           last.code == code,
           last.message == message
        {
            return
        }
        let snapshot = RecentErrorSnapshot(
            occurredAt: TimestampFormatter.string(from: Date()),
            source: source,
            code: code,
            message: message
        )
        recentErrors.append(snapshot)
        if recentErrors.count > Self.recentErrorLimit {
            recentErrors.removeFirst(recentErrors.count - Self.recentErrorLimit)
        }
        hostEventContinuation.yield(.recentErrorRecorded(snapshot))
    }

    func emitProfileCacheChanged() {
        hostEventContinuation.yield(
            .profileCacheChanged(
                .init(
                    state: profileCacheState,
                    warning: profileCacheWarning,
                    profileCount: profileCache.count,
                    lastRefreshAt: lastProfileRefreshAt.map(TimestampFormatter.string(from:))
                )
            )
        )
    }

    func emitTextProfilesChanged() async {
        let activeProfile = await runtime.activeTextProfile()
        let storedProfiles = await runtime.textProfiles()
        hostEventContinuation.yield(
            .textProfilesChanged(
                .init(
                    activeProfileID: activeProfile.id,
                    storedProfileCount: storedProfiles.count
                )
            )
        )
    }

    func emitRuntimeConfigurationChanged(_ snapshot: RuntimeConfigurationSnapshot) {
        hostEventContinuation.yield(
            .runtimeConfigurationChanged(
                .init(
                    activeRuntimeSpeechBackend: snapshot.activeRuntimeSpeechBackend,
                    nextRuntimeSpeechBackend: snapshot.nextRuntimeSpeechBackend,
                    persistedSpeechBackend: snapshot.persistedSpeechBackend,
                    environmentSpeechBackendOverride: snapshot.environmentSpeechBackendOverride,
                    persistedConfigurationPath: snapshot.persistedConfigurationPath,
                    persistedConfigurationState: snapshot.persistedConfigurationState
                )
            )
        )
    }

    // MARK: - Event Mapping and Encoding

    func mapQueuedEvent(_ event: SpeakSwiftly.QueuedEvent) -> ServerJobEvent {
        .queued(
            .init(
                id: event.id,
                reason: event.reason.rawValue,
                queuePosition: event.queuePosition
            )
        )
    }

    func mapStartedEvent(_ event: SpeakSwiftly.StartedEvent) -> ServerJobEvent {
        .started(.init(id: event.id, op: event.op))
    }

    func mapProgressEvent(_ event: SpeakSwiftly.ProgressEvent) -> ServerJobEvent {
        .progress(.init(id: event.id, stage: event.stage.rawValue))
    }

    func queueStatusSnapshot(from summary: SpeakSwiftly.QueueSnapshot) -> QueueStatusSnapshot {
        let activeRequests = summary.activeRequests?.map(ActiveRequestSnapshot.init(summary:))
            ?? summary.activeRequest.map { [ActiveRequestSnapshot(summary: $0)] }
            ?? []
        return .init(
            queueType: summary.queueType,
            activeCount: activeRequests.count,
            queuedCount: summary.queue.count,
            activeRequest: activeRequests.first,
            activeRequests: activeRequests,
            queuedRequests: summary.queue.map(QueuedRequestSnapshot.init(summary:))
        )
    }

    func queueSnapshotResponse(from snapshot: QueueStatusSnapshot) -> QueueSnapshotResponse {
        .init(
            queueType: snapshot.queueType,
            activeRequest: snapshot.activeRequest,
            activeRequests: snapshot.activeRequests,
            queue: snapshot.queuedRequests
        )
    }

    func generationJobOrdering(lhs: JobRecord, rhs: JobRecord) -> Bool {
        let lhsPriority = generationPriority(for: lhs)
        let rhsPriority = generationPriority(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority > rhsPriority
        }

        let lhsActivity = lhs.startedAt ?? lhs.submittedAt
        let rhsActivity = rhs.startedAt ?? rhs.submittedAt
        if lhsActivity != rhsActivity {
            return lhsActivity > rhsActivity
        }

        return lhs.submittedAt > rhs.submittedAt
    }

    func mapSuccessEvent(_ event: SpeakSwiftly.Success, acknowledged: Bool) -> ServerJobEvent {
        let success = ServerSuccessEvent(
            id: event.id,
            generatedFile: event.generatedFile,
            generatedFiles: event.generatedFiles,
            generatedBatch: event.generatedBatch,
            generatedBatches: event.generatedBatches,
            generationJob: event.generationJob,
            generationJobs: event.generationJobs,
            profileName: event.profileName,
            profilePath: event.profilePath,
            profiles: event.profiles?.map(ProfileSnapshot.init(profile:)),
            textProfile: event.textProfile.map(TextProfileSnapshot.init(profile:)),
            textProfiles: event.textProfiles?.map(TextProfileSnapshot.init(profile:)),
            textProfilePath: event.textProfilePath,
            activeRequest: event.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
            activeRequests: event.activeRequests?.map(ActiveRequestSnapshot.init(summary:)),
            queue: event.queue?.map(QueuedRequestSnapshot.init(summary:)),
            playbackState: event.playbackState.map(PlaybackStateSnapshot.init(summary:)),
            status: event.status,
            speechBackend: event.speechBackend?.rawValue,
            clearedCount: event.clearedCount,
            cancelledRequestID: event.cancelledRequestID
        )
        return acknowledged ? .acknowledged(success) : .completed(success)
    }

    func encodeSSEBuffer(for event: ServerJobEvent) -> ByteBuffer {
        let eventName: String = switch event {
        case .workerStatus:
            "worker_status"
        case .queued:
            "queued"
        case .acknowledged, .completed:
            "message"
        case .started:
            "started"
        case .progress:
            "progress"
        case .failed:
            "message"
        }

        let data = (try? encoder.encode(event)) ?? Data(#"{"ok":false,"code":"encoding_error","message":"SpeakSwiftlyServer could not encode an SSE event payload."}"#.utf8)
        var buffer = byteBufferAllocator.buffer(capacity: eventName.utf8.count + data.count + 16)
        buffer.writeString("event: \(eventName)\n")
        buffer.writeString("data: ")
        buffer.writeBytes(data)
        buffer.writeString("\n\n")
        return buffer
    }

    // MARK: - Immediate Control Helpers

    func encodeHeartbeatBuffer() -> ByteBuffer {
        var buffer = byteBufferAllocator.buffer(capacity: 15)
        buffer.writeString(": keep-alive\n\n")
        return buffer
    }

    func playbackStateResponse(
        handle: RuntimeRequestHandle,
        requestName: String
    ) async throws -> PlaybackStateResponse {
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        guard let playbackState = success.playbackState else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the '\(requestName)' control request, but it did not return a playback state payload."
            )
        }
        return .init(playback: .init(summary: playbackState))
    }

    func playbackControlResponse(
        handle: RuntimeRequestHandle,
        requestName: String,
        expectedState: SpeakSwiftly.PlaybackState
    ) async throws -> PlaybackStateResponse {
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the '\(handle.operation)' control request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the '\(handle.operation)' control request."
        )
        if let playbackState = success.playbackState, playbackState.state == expectedState {
            let response = PlaybackStateResponse(playback: .init(summary: playbackState))
            await applyPlaybackControlSnapshot(response.playback, expectedState: expectedState)
            return response
        }
        let response = try await settledPlaybackStateResponse(
            for: requestName,
            expectedState: expectedState
        )
        await applyPlaybackControlSnapshot(response.playback, expectedState: expectedState)
        return response
    }

    func settledPlaybackStateResponse(
        for requestName: String,
        expectedState: SpeakSwiftly.PlaybackState
    ) async throws -> PlaybackStateResponse {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        var lastResponse: PlaybackStateResponse?

        while true {
            let response = try await playbackStateResponse(
                handle: await runtime.playbackState(),
                requestName: requestName
            )
            lastResponse = response
            if response.playback.state == expectedState.rawValue {
                return response
            }
            if clock.now >= deadline {
                return optimisticPlaybackStateResponse(
                    from: lastResponse ?? response,
                    expectedState: expectedState
                )
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    func optimisticPlaybackStateResponse(
        from response: PlaybackStateResponse,
        expectedState: SpeakSwiftly.PlaybackState
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
                : nil
        )
        return .init(playback: .init(status: status))
    }

    func applyPlaybackControlSnapshot(
        _ snapshot: PlaybackStateSnapshot,
        expectedState: SpeakSwiftly.PlaybackState
    ) async {
        let previousPlaybackStatus = playbackStatus
        playbackStatus = .init(
            state: snapshot.state,
            activeRequest: snapshot.activeRequest,
            isStableForConcurrentGeneration: snapshot.isStableForConcurrentGeneration,
            isRebuffering: snapshot.isRebuffering,
            stableBufferedAudioMS: snapshot.stableBufferedAudioMS,
            stableBufferTargetMS: snapshot.stableBufferTargetMS
        )
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
                queuedRequests: playbackQueueStatus.queuedRequests
            )
        } else if expectedState == .playing, playbackStatus.activeRequest != nil {
            playbackQueueStatus = .init(
                queueType: playbackQueueStatus.queueType,
                activeCount: 1,
                queuedCount: playbackQueueStatus.queuedCount,
                activeRequest: playbackStatus.activeRequest,
                activeRequests: [playbackStatus.activeRequest!],
                queuedRequests: playbackQueueStatus.queuedRequests
            )
        }
    }

    func isGenerationOperation(_ operation: String) -> Bool {
        operation == "queue_speech_live"
            || operation == "queue_speech_file"
            || operation == "queue_speech_batch"
    }

    func runtimeStatusResponse(
        handle: RuntimeRequestHandle,
        requestName: String
    ) async throws -> RuntimeStatusResponse {
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the \(requestName) request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while processing the \(requestName) request."
        )
        guard let status = success.status else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly accepted the \(requestName) request, but it did not return a status payload."
            )
        }
        return .init(status: status)
    }

    func awaitImmediateSuccess(
        handle: RuntimeRequestHandle,
        missingTerminalMessage: String,
        unexpectedFailureMessagePrefix: String
    ) async throws -> SpeakSwiftly.Success {
        do {
            for try await event in handle.events {
                if case .completed(let success) = event {
                    return success
                }
            }
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: missingTerminalMessage
            )
        } catch let error as SpeakSwiftly.Error {
            throw error
        } catch {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "\(unexpectedFailureMessagePrefix) \(error.localizedDescription)"
            )
        }
    }
}
