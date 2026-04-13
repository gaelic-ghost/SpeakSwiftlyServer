import Foundation
import Hummingbird
import SpeakSwiftly

// MARK: - Host Event Support

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
                    activeDefaultVoiceProfileName: snapshot.activeDefaultVoiceProfileName,
                    nextDefaultVoiceProfileName: snapshot.nextDefaultVoiceProfileName,
                    persistedSpeechBackend: snapshot.persistedSpeechBackend,
                    persistedDefaultVoiceProfileName: snapshot.persistedDefaultVoiceProfileName,
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
        .started(.init(id: event.id, op: canonicalOperationName(event.op)))
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

    func encodeHeartbeatBuffer() -> ByteBuffer {
        var buffer = byteBufferAllocator.buffer(capacity: 15)
        buffer.writeString(": keep-alive\n\n")
        return buffer
    }

    func isGenerationOperation(_ operation: String) -> Bool {
        operation == "generate_speech"
            || operation == "generate_audio_file"
            || operation == "generate_batch"
    }
}
