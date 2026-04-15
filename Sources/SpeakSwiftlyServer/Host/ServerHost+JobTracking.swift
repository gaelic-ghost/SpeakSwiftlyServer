import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

// MARK: - Job Tracking

extension ServerHost {
    func jobSnapshot(id: String) throws -> JobSnapshot {
        pruneCompletedJobs()
        guard let job = jobs[id] else {
            throw HTTPError(
                .notFound,
                message: "Request '\(id)' was not found in the shared server request cache. It may be unknown or may have expired from in-memory retention.",
            )
        }

        return job.snapshot
    }

    func sseStream(for jobID: String) throws -> AsyncStream<ByteBuffer> {
        pruneCompletedJobs()
        let updates = eventUpdates()
        guard let job = jobs[jobID] else {
            throw HTTPError(
                .notFound,
                message: "Request '\(jobID)' was not found in the shared server request cache. It may be unknown or may have expired from in-memory retention.",
            )
        }

        let history = job.history
        let terminalEvent = job.terminalEvent
        let workerStatusEvent = currentWorkerStatusEvent
        let replayedHistoryCount = history.count

        return AsyncStream { continuation in
            continuation.yield(self.encodeSSEBuffer(for: workerStatusEvent))
            for event in history {
                continuation.yield(self.encodeSSEBuffer(for: event))
            }

            if terminalEvent != nil {
                continuation.finish()
                return
            }

            let heartbeatTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(self.configuration.sseHeartbeatSeconds))
                    continuation.yield(self.encodeHeartbeatBuffer())
                }
            }

            let eventTask = Task {
                var iterator = updates.makeAsyncIterator()
                var lastDeliveredHistoryIndex = replayedHistoryCount

                while !Task.isCancelled, let update = await iterator.next() {
                    guard case let .jobEvent(jobUpdate) = update else {
                        continue
                    }
                    guard jobUpdate.jobID == jobID else {
                        continue
                    }
                    guard jobUpdate.historyIndex > lastDeliveredHistoryIndex else {
                        continue
                    }

                    lastDeliveredHistoryIndex = jobUpdate.historyIndex
                    continuation.yield(self.encodeSSEBuffer(for: jobUpdate.event))

                    if jobUpdate.terminal {
                        continuation.finish()
                        break
                    }
                }
            }

            continuation.onTermination = { _ in
                heartbeatTask.cancel()
                eventTask.cancel()
            }
        }
    }

    var currentWorkerStatusEvent: ServerJobEvent {
        .workerStatus(
            .init(
                stage: workerStage,
                workerMode: workerMode,
            ),
        )
    }

    func consume(handle: RuntimeRequestHandle) async {
        do {
            for try await event in handle.events {
                switch event {
                    case let .queued(queued):
                        await record(mapQueuedEvent(queued), for: handle.id, terminal: false)
                    case let .acknowledged(success):
                        await record(mapSuccessEvent(success, acknowledged: true), for: handle.id, terminal: false)
                    case let .started(started):
                        await record(mapStartedEvent(started), for: handle.id, terminal: false)
                    case let .progress(progress):
                        await record(mapProgressEvent(progress), for: handle.id, terminal: false)
                    case let .completed(success):
                        if handle.operation == "create_voice_profile_from_description"
                            || handle.operation == "create_voice_profile_from_audio"
                            || handle.operation == "update_voice_profile_name"
                            || handle.operation == "delete_voice_profile" {
                            await finalizeMutationSuccess(
                                success: success,
                                requestID: handle.id,
                                operationName: handle.operation,
                            )
                        } else if handle.operation == "list_voice_profiles" {
                            await applyProfileRefresh(from: success)
                            await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                        } else {
                            await record(mapSuccessEvent(success, acknowledged: false), for: handle.id, terminal: true)
                        }
                }
            }
        } catch let error as SpeakSwiftly.Error {
            let failure = ServerFailureEvent(id: handle.id, code: error.code.rawValue, message: error.message)
            await record(.failed(failure), for: handle.id, terminal: true)
        } catch {
            let failure = ServerFailureEvent(
                id: handle.id,
                code: SpeakSwiftly.ErrorCode.internalError.rawValue,
                message: "SpeakSwiftly request '\(handle.id)' failed unexpectedly while the server was monitoring its typed event stream. \(error.localizedDescription)",
            )
            await record(.failed(failure), for: handle.id, terminal: true)
        }
    }

    func finalizeMutationSuccess(
        success: SpeakSwiftly.Success,
        requestID: String,
        operationName: String,
    ) async {
        do {
            let previousProfiles = profileCache
            let profiles = try await reconcileProfilesAfterMutation(
                op: operationName,
                requestID: requestID,
                success: success,
                previousProfiles: previousProfiles,
            )
            profileCache = profiles
            profileCacheState = "fresh"
            profileCacheWarning = nil
            let finalSuccess = ServerSuccessEvent(
                id: success.id,
                generatedFile: success.generatedFile,
                generatedFiles: success.generatedFiles,
                generatedBatch: success.generatedBatch,
                generatedBatches: success.generatedBatches,
                generationJob: success.generationJob,
                generationJobs: success.generationJobs,
                profileName: success.profileName,
                profilePath: success.profilePath,
                profiles: nil,
                textProfile: success.textProfile.map(TextProfileSnapshot.init(profile:)),
                textProfiles: success.textProfiles?.map(TextProfileSnapshot.init(profile:)),
                textProfilePath: success.textProfilePath,
                activeRequest: success.activeRequest.map(ActiveRequestSnapshot.init(summary:)),
                activeRequests: success.activeRequests?.map(ActiveRequestSnapshot.init(summary:)),
                queue: success.queue?.map(QueuedRequestSnapshot.init(summary:)),
                playbackState: success.playbackState.map(PlaybackStateSnapshot.init(summary:)),
                status: success.status,
                speechBackend: success.speechBackend?.rawValue,
                clearedCount: success.clearedCount,
                cancelledRequestID: success.cancelledRequestID,
            )
            await record(.completed(finalSuccess), for: requestID, terminal: true)
        } catch {
            profileCacheState = "stale"
            profileCacheWarning = "SpeakSwiftly reported a successful profile mutation, but the server could not confirm the refreshed profile list afterward. The cached profile list may be stale. Likely cause: \(error.localizedDescription)"
            emitProfileCacheChanged()
            recordRecentError(
                source: "profile_cache",
                code: "profile_refresh_mismatch",
                message: profileCacheWarning ?? "SpeakSwiftly could not reconcile the refreshed profile cache after a successful mutation.",
            )
            let failure = ServerFailureEvent(
                id: requestID,
                code: "profile_refresh_mismatch",
                message: "SpeakSwiftly reported success, but the server could not confirm the profile list changed as expected after the mutation.",
            )
            await record(.failed(failure), for: requestID, terminal: true)
        }
    }

    func reconcileProfilesAfterMutation(
        op: String,
        requestID: String,
        success: SpeakSwiftly.Success,
        previousProfiles: [ProfileSnapshot],
    ) async throws -> [ProfileSnapshot] {
        guard let profileName = success.profileName, !profileName.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly returned a successful \(op) payload for request '\(requestID)', but it did not include a usable profile name for cache reconciliation.",
            )
        }

        let retryDelays = Self.mutationRefreshRetryDelays
        for attempt in 0...retryDelays.count {
            let refreshedProfiles = try await refreshProfiles(reason: "\(op):\(requestID):\(attempt)")
            if profilesMatchExpectedMutation(
                op: op,
                profileName: profileName,
                previousProfiles: previousProfiles,
                refreshedProfiles: refreshedProfiles,
            ) {
                return refreshedProfiles
            }

            if attempt < retryDelays.count {
                try await Task.sleep(for: retryDelays[attempt])
            }
        }

        throw SpeakSwiftly.Error(
            code: .internalError,
            message: "SpeakSwiftly refreshed the profile cache after \(op) for profile '\(profileName)', but the list still did not reflect the expected mutation.",
        )
    }

    func refreshProfiles(reason: String) async throws -> [ProfileSnapshot] {
        let handle = await runtime.listVoiceProfiles()
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the internal list_voice_profiles request without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while refreshing cached profiles.",
        )
        let profiles = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        profileCache = profiles
        lastProfileRefreshAt = Date()
        profileCacheState = "fresh"
        profileCacheWarning = nil
        emitProfileCacheChanged()
        _ = reason
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return profiles
    }

    func applyProfileRefresh(from success: SpeakSwiftly.Success) async {
        profileCache = success.profiles?.map(ProfileSnapshot.init(profile:)) ?? []
        lastProfileRefreshAt = Date()
        profileCacheState = "fresh"
        profileCacheWarning = nil
        emitProfileCacheChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
    }

    func profilesMatchExpectedMutation(
        op: String,
        profileName: String,
        previousProfiles: [ProfileSnapshot],
        refreshedProfiles: [ProfileSnapshot],
    ) -> Bool {
        let previousNames = Set(previousProfiles.map(\.profileName))
        let refreshedNames = Set(refreshedProfiles.map(\.profileName))

        switch op {
            case "create_voice_profile_from_description":
                return refreshedNames.contains(profileName) && refreshedNames != previousNames
            case "create_voice_profile_from_audio":
                return refreshedNames.contains(profileName) && refreshedNames != previousNames
            case "update_voice_profile_name":
                return refreshedNames.contains(profileName)
                    && !previousNames.contains(profileName)
                    && refreshedNames.count == previousNames.count
            case "delete_voice_profile":
                return !refreshedNames.contains(profileName) && refreshedNames != previousNames
            default:
                return false
        }
    }

    func handle(status: SpeakSwiftly.StatusEvent) async {
        switch status.stage {
            case .warmingResidentModel:
                workerMode = "starting"
                workerStage = status.stage.rawValue
                startupError = nil
            case .residentModelReady:
                workerMode = "ready"
                workerStage = status.stage.rawValue
                startupError = nil
                if !hasRequestedStartupProfileRefresh {
                    hasRequestedStartupProfileRefresh = true
                    do {
                        _ = try await refreshProfiles(reason: "startup")
                    } catch {
                        profileCacheState = "stale"
                        profileCacheWarning = "SpeakSwiftly became ready, but the server could not refresh the initial profile cache. Likely cause: \(error.localizedDescription)"
                        emitProfileCacheChanged()
                    }
                }
            case .residentModelsUnloaded:
                workerMode = "starting"
                workerStage = status.stage.rawValue
                startupError = nil
            case .residentModelFailed:
                workerMode = "failed"
                workerStage = status.stage.rawValue
                startupError = "SpeakSwiftly reported resident model startup failure."
                recordRecentError(
                    source: "worker",
                    code: "resident_model_failed",
                    message: startupError ?? "SpeakSwiftly reported resident model startup failure.",
                )
        }

        let event = currentWorkerStatusEvent
        for (jobID, job) in jobs where job.terminalEvent == nil {
            await record(event, for: jobID, terminal: false)
        }
        await requestPublish(mode: .immediate, refreshRuntimeState: true)
    }

    func record(_ event: ServerJobEvent, for jobID: String, terminal: Bool) async {
        guard var job = jobs[jobID] else { return }

        job.latestEvent = event
        if job.startedAt == nil, case .started = event {
            job.startedAt = Date()
        }
        job.history.append(event)
        let historyIndex = job.history.count
        if terminal {
            job.terminalEvent = event
            job.terminalAt = Date()
        }
        jobs[jobID] = job
        hostEventContinuation.yield(.jobChanged(job.snapshot))
        hostEventContinuation.yield(
            .jobEvent(
                .init(
                    jobID: jobID,
                    event: event,
                    historyIndex: historyIndex,
                    terminal: terminal,
                ),
            ),
        )

        if terminal {
            if case let .failed(failure) = event {
                recordRecentError(
                    source: "job:\(job.op)",
                    code: failure.code,
                    message: failure.message,
                )
            }
            pruneCompletedJobs()
        }
        await requestPublish(
            mode: terminal ? .immediate : .coalesced,
            refreshRuntimeState: shouldRefreshRuntimeDerivedState(after: event, terminal: terminal),
        )
    }

    func pruneCompletedJobs() {
        let now = Date()
        let expiredIDs = jobs.compactMap { jobID, job -> String? in
            guard let terminalAt = job.terminalAt else { return nil }

            let age = now.timeIntervalSince(terminalAt)
            return age > configuration.completedJobTTLSeconds ? jobID : nil
        }
        for jobID in expiredIDs {
            jobs.removeValue(forKey: jobID)
        }

        let completed = jobs.values
            .filter { $0.terminalAt != nil }
            .sorted { lhs, rhs in
                let lhsTerminalAt = lhs.terminalAt ?? .distantPast
                let rhsTerminalAt = rhs.terminalAt ?? .distantPast
                if lhsTerminalAt == rhsTerminalAt {
                    return lhs.submittedAt < rhs.submittedAt
                }
                return lhsTerminalAt < rhsTerminalAt
            }
        let overflow = completed.count - configuration.completedJobMaxCount
        guard overflow > 0 else { return }

        for job in completed.prefix(overflow) {
            jobs.removeValue(forKey: job.jobID)
        }
    }
}
