import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

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
                        if let mutationExpectation = jobs[handle.id]?.profileMutation {
                            await finalizeMutationSuccess(
                                success: success,
                                requestID: handle.id,
                                expectation: mutationExpectation,
                            )
                        } else if let backendSwitchExpectation = jobs[handle.id]?.runtimeBackendSwitch {
                            await finalizeRuntimeBackendSwitchSuccess(
                                success: success,
                                requestID: handle.id,
                                expectation: backendSwitchExpectation,
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

    func finalizeRuntimeBackendSwitchSuccess(
        success: SpeakSwiftly.Success,
        requestID: String,
        expectation: RuntimeBackendSwitchExpectation,
    ) async {
        guard let resolvedSpeechBackend = success.speechBackend else {
            let failure = ServerFailureEvent(
                id: requestID,
                code: SpeakSwiftly.ErrorCode.internalError.rawValue,
                message: "SpeakSwiftly reported a successful speech-backend switch request '\(requestID)', but it did not include the active speech_backend payload.",
            )
            await record(.failed(failure), for: requestID, terminal: true)
            return
        }
        guard resolvedSpeechBackend == expectation.requestedSpeechBackend else {
            let failure = ServerFailureEvent(
                id: requestID,
                code: SpeakSwiftly.ErrorCode.internalError.rawValue,
                message: "SpeakSwiftly reported speech-backend switch request '\(requestID)' as '\(resolvedSpeechBackend.rawValue)' instead of the requested '\(expectation.requestedSpeechBackend.rawValue)'.",
            )
            await record(.failed(failure), for: requestID, terminal: true)
            return
        }

        activeRuntimeSpeechBackend = resolvedSpeechBackend
        let runtimeConfigurationSnapshot = runtimeConfigurationStore.snapshot(
            activeRuntimeSpeechBackend: resolvedSpeechBackend,
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await record(mapSuccessEvent(success, acknowledged: false), for: requestID, terminal: true)
    }

    func finalizeMutationSuccess(
        success: SpeakSwiftly.Success,
        requestID: String,
        expectation: ProfileMutationExpectation,
    ) async {
        do {
            let previousProfiles = profileCache
            let profiles = try await reconcileProfilesAfterMutation(
                expectation: expectation,
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
                textProfile: success.textProfile.map(TextProfileSnapshot.init(details:)),
                textProfiles: success.textProfiles?.map(TextProfileSnapshot.init(summary:)),
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
            profileCacheWarning = "SpeakSwiftly reported a successful \(expectation.operationName) mutation, but the server could not confirm the refreshed profile list afterward. The cached profile list may be stale. Likely cause: \(error.localizedDescription)"
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
        expectation: ProfileMutationExpectation,
        requestID: String,
        success: SpeakSwiftly.Success,
        previousProfiles: [ProfileSnapshot],
    ) async throws -> [ProfileSnapshot] {
        guard let reportedProfileName = success.profileName, !reportedProfileName.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly returned a successful \(expectation.operationName) payload for request '\(requestID)', but it did not include a usable profile name for cache reconciliation.",
            )
        }
        guard reportedProfileName == expectation.expectedSuccessProfileName else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly returned a successful \(expectation.operationName) payload for request '\(requestID)', but it reported profile '\(reportedProfileName)' instead of the expected profile '\(expectation.expectedSuccessProfileName)'.",
            )
        }

        let retryDelays = Self.mutationRefreshRetryDelays
        for attempt in 0...retryDelays.count {
            let refreshedProfiles = try await refreshProfiles(reason: "\(expectation.operationName):\(requestID):\(attempt)")
            if refreshedProfilesMatchExpectedMutation(
                expectation: expectation,
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
            message: "SpeakSwiftly refreshed the profile cache after \(expectation.operationName) for profile '\(expectation.expectedSuccessProfileName)', but the list still did not reflect the expected mutation.",
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

    func refreshedProfilesMatchExpectedMutation(
        expectation: ProfileMutationExpectation,
        previousProfiles: [ProfileSnapshot],
        refreshedProfiles: [ProfileSnapshot],
    ) -> Bool {
        switch expectation {
            case let .create(profileName):
                guard let refreshedProfile = refreshedProfiles.first(where: { $0.profileName == profileName }) else {
                    return false
                }
                guard let previousProfile = previousProfiles.first(where: { $0.profileName == profileName }) else {
                    return true
                }

                return refreshedProfile != previousProfile
            case let .rename(previousProfileName, newProfileName):
                guard refreshedProfiles.contains(where: { $0.profileName == previousProfileName }) == false else {
                    return false
                }
                guard let refreshedProfile = refreshedProfiles.first(where: { $0.profileName == newProfileName }) else {
                    return false
                }

                if previousProfiles.contains(where: { $0.profileName == previousProfileName }) {
                    return true
                }

                guard let previousRenamedProfile = previousProfiles.first(where: { $0.profileName == newProfileName }) else {
                    return true
                }

                return refreshedProfile != previousRenamedProfile
            case let .reroll(profileName):
                guard
                    let previousProfile = previousProfiles.first(where: { $0.profileName == profileName }),
                    let refreshedProfile = refreshedProfiles.first(where: { $0.profileName == profileName })
                else {
                    return false
                }

                return refreshedProfile != previousProfile
            case let .delete(profileName):
                return refreshedProfiles.contains(where: { $0.profileName == profileName }) == false
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
