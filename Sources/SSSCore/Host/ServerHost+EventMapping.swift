import Foundation
import NIOCore
import SpeakSwiftly

package extension ServerHost {
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
            advertisedAddress: current.advertisedAddress,
        )
        guard updated != current else {
            return
        }

        transportStatuses[name] = updated
        hostEventContinuation.yield(.transportChanged(updated))
    }

    static func initialTransportStatuses(
        httpConfig: HTTPConfig,
        mcpConfig: MCPConfig,
    ) -> [String: TransportStatusSnapshot] {
        let http = TransportStatusSnapshot(
            name: "http",
            enabled: httpConfig.enabled,
            state: httpConfig.enabled ? "stopped" : "disabled",
            host: httpConfig.enabled ? httpConfig.host : nil,
            port: httpConfig.enabled ? httpConfig.port : nil,
            path: nil,
            advertisedAddress: httpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)" : nil,
        )
        let mcp = TransportStatusSnapshot(
            name: "mcp",
            enabled: mcpConfig.enabled,
            state: mcpConfig.enabled ? "stopped" : "disabled",
            host: mcpConfig.enabled ? httpConfig.host : nil,
            port: mcpConfig.enabled ? httpConfig.port : nil,
            path: mcpConfig.enabled ? mcpConfig.path : nil,
            advertisedAddress: mcpConfig.enabled ? "http://\(httpConfig.host):\(httpConfig.port)\(mcpConfig.path)" : nil,
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
           last.message == message {
            return
        }
        let snapshot = RecentErrorSnapshot(
            occurredAt: TimestampFormatter.string(from: Date()),
            source: source,
            code: code,
            message: message,
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
                    lastRefreshAt: lastProfileRefreshAt.map(TimestampFormatter.string(from:)),
                ),
            ),
        )
    }

    func emitTextProfilesChanged() async throws {
        let activeProfile = try await runtime.activeTextProfile()
        let storedProfiles = try await runtime.textProfiles()
        hostEventContinuation.yield(
            .textProfilesChanged(
                .init(
                    activeProfileID: activeProfile.id,
                    storedProfileCount: storedProfiles.count,
                ),
            ),
        )
    }

    func emitRuntimeConfigurationChanged(_ snapshot: RuntimeConfigurationSnapshot) {
        hostEventContinuation.yield(
            .runtimeConfigurationChanged(
                .init(
                    activeRuntimeSpeechBackend: snapshot.activeRuntimeSpeechBackend,
                    nextRuntimeSpeechBackend: snapshot.nextRuntimeSpeechBackend,
                    activeDuckMediaVolume: snapshot.activeDuckMediaVolume,
                    nextDuckMediaVolume: snapshot.nextDuckMediaVolume,
                    activeDefaultVoiceProfileName: snapshot.activeDefaultVoiceProfileName,
                    nextDefaultVoiceProfileName: snapshot.nextDefaultVoiceProfileName,
                    persistedSpeechBackend: snapshot.persistedSpeechBackend,
                    persistedDuckMediaVolume: snapshot.persistedDuckMediaVolume,
                    persistedDefaultVoiceProfileName: snapshot.persistedDefaultVoiceProfileName,
                    environmentSpeechBackendOverride: snapshot.environmentSpeechBackendOverride,
                    persistedConfigurationPath: snapshot.persistedConfigurationPath,
                    persistedConfigurationState: snapshot.persistedConfigurationState,
                ),
            ),
        )
    }

    // MARK: - Event Mapping and Encoding

    func mapQueuedEvent(_ event: SpeakSwiftly.QueuedEvent) -> ServerJobEvent {
        .queued(
            .init(
                id: event.id,
                reason: event.reason.rawValue,
                queuePosition: event.queuePosition,
            ),
        )
    }

    func mapStartedEvent(_ event: SpeakSwiftly.StartedEvent) -> ServerJobEvent {
        .started(.init(id: event.id, op: canonicalOperationName(event.kind.rawValue)))
    }

    func mapProgressEvent(_ event: SpeakSwiftly.ProgressEvent) -> ServerJobEvent {
        .progress(.init(id: event.id, stage: event.stage.rawValue))
    }

    func queueStatusSnapshot(from summary: SpeakSwiftly.QueueSnapshot) -> QueueStatusSnapshot {
        let activeRequests = summary.activeRequests.map(ActiveRequestSnapshot.init(summary:))
        return .init(
            queueType: summary.queueType.rawValue,
            activeCount: activeRequests.count,
            queuedCount: summary.queue.count,
            activeRequest: activeRequests.first,
            activeRequests: activeRequests,
            queuedRequests: summary.queue.map(QueuedRequestSnapshot.init(summary:)),
        )
    }

    func queueStatusSnapshot(from summary: SpeakSwiftly.GenerateSnapshot) -> QueueStatusSnapshot {
        let activeRequests = summary.activeRequests.map(ActiveRequestSnapshot.init(summary:))
        return .init(
            queueType: SpeakSwiftly.QueueType.generation.rawValue,
            activeCount: activeRequests.count,
            queuedCount: summary.queuedRequests.count,
            activeRequest: activeRequests.first,
            activeRequests: activeRequests,
            queuedRequests: summary.queuedRequests.map(QueuedRequestSnapshot.init(summary:)),
        )
    }

    func queueStatusSnapshot(from summary: SpeakSwiftly.PlaybackSnapshot) -> QueueStatusSnapshot {
        let activeRequests = summary.activeRequest.map { [ActiveRequestSnapshot(summary: $0)] } ?? []
        return .init(
            queueType: SpeakSwiftly.QueueType.playback.rawValue,
            activeCount: activeRequests.count,
            queuedCount: summary.queuedRequests.count,
            activeRequest: activeRequests.first,
            activeRequests: activeRequests,
            queuedRequests: summary.queuedRequests.map(QueuedRequestSnapshot.init(summary:)),
        )
    }

    func queueSnapshotResponse(from snapshot: QueueStatusSnapshot) -> QueueSnapshotResponse {
        .init(snapshot: snapshot)
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

    func mapAcknowledgementEvent(_ event: SpeakSwiftly.RequestAcknowledgement) -> ServerJobEvent {
        .acknowledged(.init(id: event.id, generationJob: event.generationJob))
    }

    func mapCompletionEvent(
        id: String,
        _ completion: SpeakSwiftly.RequestCompletion,
        acknowledged: Bool = false,
    ) async -> ServerJobEvent {
        let success: ServerSuccessEvent = switch completion {
            case let .artifact(value):
                .init(id: id, artifact: value)
            case let .artifacts(values):
                .init(id: id, artifacts: values)
            case let .generationJob(value):
                .init(id: id, generationJob: value)
            case let .generationJobs(values):
                .init(id: id, generationJobs: values)
            case let .voiceProfile(name: name, path: path):
                .init(id: id, profileName: name, profilePath: path)
            case let .voiceProfiles(values):
                .init(id: id, profiles: values.map(ProfileSnapshot.init(profile:)))
            case let .textProfile(
            profile: profile,
            profiles: profileList,
            styleOptions: _,
            activeStyle: _,
            persistencePath: persistencePath,
        ):
                .init(
                    id: id,
                    textProfile: profile.map(TextProfileSnapshot.init(details:)),
                    textProfiles: profileList?.map(TextProfileSnapshot.init(summary:)),
                    textProfilePath: persistencePath,
                )
            case let .queue(activeRequests: active, queuedRequests: queued):
                ServerSuccessEvent(
                    id: id,
                    activeRequest: active.map(ActiveRequestSnapshot.init(summary:)).first,
                    activeRequests: active.map(ActiveRequestSnapshot.init(summary:)),
                    queue: queued.map(QueuedRequestSnapshot.init(summary:)),
                )
            case let .playbackSnapshot(value):
                .init(id: id, playbackState: PlaybackStatusSnapshot(summary: value))
            case let .runtimeSnapshot(value):
                .init(id: id, runtime: value, speechBackend: value.speechBackend.rawValue)
            case .runtimeUpdate:
                await runtimeSnapshotSuccessEvent(id: id)
            case let .defaultVoiceProfile(name):
                .init(id: id, profileName: name)
            case let .queueCleared(count: count):
                .init(id: id, clearedCount: count)
            case let .requestCancelled(id: cancelledID):
                .init(id: id, cancelledRequestID: cancelledID)
            case .empty:
                .init(id: id)
        }
        return acknowledged ? .acknowledged(success) : .completed(success)
    }

    func runtimeSnapshotSuccessEvent(id: String) async -> ServerSuccessEvent {
        let runtimeSnapshot = await runtime.runtimeSnapshot()
        return .init(id: id, runtime: runtimeSnapshot, speechBackend: runtimeSnapshot.speechBackend.rawValue)
    }

    func encodeSSEBuffer(for event: ServerJobEvent) -> ByteBuffer {
        let eventName = switch event {
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
