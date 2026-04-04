import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import SpeakSwiftlyCore
import Testing
@testable import SpeakSwiftlyServer

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct QueuedRequestState: Sendable {
        let request: WorkerRequest
        let continuation: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation
    }

    enum SpeakBehavior: Sendable {
        case completeImmediately
        case holdOpen
    }

    enum MutationRefreshBehavior: Sendable {
        case applyMutations
        case leaveProfilesUnchanged
    }

    var profiles: [ProfileSummary]
    var speakBehavior: SpeakBehavior
    var mutationRefreshBehavior: MutationRefreshBehavior
    private var statusContinuation: AsyncStream<WorkerStatusEvent>.Continuation?
    private var activeRequest: WorkerRequest?
    private var activeContinuation: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation?
    private var queuedRequests = [QueuedRequestState]()
    private var playbackState: PlaybackState = .idle

    init(
        profiles: [ProfileSummary] = [sampleProfile()],
        speakBehavior: SpeakBehavior = .completeImmediately,
        mutationRefreshBehavior: MutationRefreshBehavior = .applyMutations
    ) {
        self.profiles = profiles
        self.speakBehavior = speakBehavior
        self.mutationRefreshBehavior = mutationRefreshBehavior
    }

    func start() {}

    func shutdown() async {
        statusContinuation?.finish()
        activeContinuation?.finish()
        activeContinuation = nil
        activeRequest = nil
        playbackState = .idle
        for queued in queuedRequests {
            queued.continuation.finish()
        }
        queuedRequests.removeAll()
    }

    func statusEvents() -> AsyncStream<WorkerStatusEvent> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
        }
    }

    func submit(_ request: WorkerRequest) async -> RuntimeRequestHandle {
        switch request {
        case .listProfiles:
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(.completed(WorkerSuccessResponse(id: request.id, profiles: profiles)))
                    continuation.finish()
                }
            )

        case .listQueue(_, let queueType):
            let activeRequest: ActiveWorkerRequestSummary? =
                switch queueType {
                case .generation:
                    self.activeRequest.map(self.activeSummary(for:))
                case .playback:
                    playbackState == .idle ? nil : self.activeRequest.map(self.activeSummary(for:))
                }
            let queue: [QueuedWorkerRequestSummary] =
                switch queueType {
                case .generation:
                    self.queuedSummaries()
                case .playback:
                    []
                }
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(
                        .completed(
                            WorkerSuccessResponse(
                                id: request.id,
                                activeRequest: activeRequest,
                                queue: queue
                            )
                        )
                    )
                    continuation.finish()
                }
            )

        case .playback(_, let action):
            switch action {
            case .pause:
                if activeRequest != nil {
                    playbackState = .paused
                }
            case .resume:
                if activeRequest != nil {
                    playbackState = .playing
                }
            case .state:
                break
            }
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(
                        .completed(
                            WorkerSuccessResponse(
                                id: request.id,
                                playbackState: self.playbackStateSummary()
                            )
                        )
                    )
                    continuation.finish()
                }
            )

        case .clearQueue:
            let clearedRequestIDs = queuedRequests.map(\.request.id)
            let clearedCount = clearedRequestIDs.count
            for requestID in clearedRequestIDs {
                cancelQueuedRequest(
                    requestID,
                    reason: "The request was cancelled because queued work was cleared from the mock SpeakSwiftly runtime."
                )
            }
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(.completed(WorkerSuccessResponse(id: request.id, clearedCount: clearedCount)))
                    continuation.finish()
                }
            )

        case .cancelRequest(_, let requestID):
            do {
                let cancelledRequestID = try cancelRequestNow(requestID)
                return RuntimeRequestHandle(
                    id: request.id,
                    request: request,
                    events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                        continuation.yield(
                            .completed(
                                WorkerSuccessResponse(
                                    id: request.id,
                                    cancelledRequestID: cancelledRequestID
                                )
                            )
                        )
                        continuation.finish()
                    }
                )
            } catch {
                return RuntimeRequestHandle(
                    id: request.id,
                    request: request,
                    events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                        continuation.finish(throwing: error)
                    }
                )
            }

        case .queueSpeech:
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(.acknowledged(.init(id: request.id)))

                    if self.activeRequest == nil {
                        self.startActiveRequest(request, continuation: continuation)
                    } else {
                        self.queuedRequests.append(.init(request: request, continuation: continuation))
                        continuation.yield(
                            .queued(
                                .init(
                                    id: request.id,
                                    reason: .waitingForActiveRequest,
                                    queuePosition: self.queuedRequests.count
                                )
                            )
                        )
                    }
                }
            )

        case .createProfile(_, let profileName, let text, let voiceDescription, _):
            if mutationRefreshBehavior == .applyMutations {
                profiles.append(
                    ProfileSummary(
                        profileName: profileName,
                        createdAt: Date(),
                        voiceDescription: voiceDescription,
                        sourceText: text
                    )
                )
            }
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(.completed(WorkerSuccessResponse(id: request.id, profileName: profileName)))
                    continuation.finish()
                }
            )

        case .removeProfile(_, let profileName):
            if mutationRefreshBehavior == .applyMutations {
                profiles.removeAll { $0.profileName == profileName }
            }
            return RuntimeRequestHandle(
                id: request.id,
                request: request,
                events: AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                    continuation.yield(.completed(WorkerSuccessResponse(id: request.id, profileName: profileName)))
                    continuation.finish()
                }
            )

        }
    }

    func publishStatus(_ stage: WorkerStatusStage) {
        statusContinuation?.yield(.init(stage: stage))
    }

    func finishHeldSpeak(id: String) {
        guard activeRequest?.id == id, let continuation = activeContinuation else { return }
        continuation.yield(.progress(.init(id: id, stage: .playbackFinished)))
        continuation.yield(.completed(.init(id: id)))
        continuation.finish()
        playbackState = .idle
        activeContinuation = nil
        activeRequest = nil
        startNextQueuedRequestIfNeeded()
    }

    private func startActiveRequest(
        _ request: WorkerRequest,
        continuation: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation
    ) {
        activeRequest = request
        playbackState = .playing
        continuation.yield(.started(.init(id: request.id, op: request.opName)))

        if speakBehavior == .completeImmediately {
            continuation.yield(.progress(.init(id: request.id, stage: .startingPlayback)))
            continuation.yield(.completed(.init(id: request.id)))
            continuation.finish()
            playbackState = .idle
            activeRequest = nil
            activeContinuation = nil
            startNextQueuedRequestIfNeeded()
        } else {
            activeContinuation = continuation
        }
    }

    private func startNextQueuedRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }
        let next = queuedRequests.removeFirst()
        startActiveRequest(next.request, continuation: next.continuation)
    }

    private func activeSummary(for request: WorkerRequest) -> ActiveWorkerRequestSummary {
        .init(id: request.id, op: request.opName, profileName: request.profileName)
    }

    private func queuedSummaries() -> [QueuedWorkerRequestSummary] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.opName,
                profileName: queued.request.profileName,
                queuePosition: offset + 1
            )
        }
    }

    private func playbackStateSummary() -> PlaybackStateSummary {
        .init(
            state: playbackState,
            activeRequest: playbackState == .idle ? nil : activeRequest.map(activeSummary(for:))
        )
    }

    private func cancelQueuedRequest(_ requestID: String, reason: String) {
        guard let index = queuedRequests.firstIndex(where: { $0.request.id == requestID }) else { return }
        let queued = queuedRequests.remove(at: index)
        queued.continuation.finish(
            throwing: WorkerError(code: .requestCancelled, message: reason)
        )
    }

    private func cancelRequestNow(_ requestID: String) throws -> String {
        if activeRequest?.id == requestID {
            activeContinuation?.finish(
                throwing: WorkerError(
                    code: .requestCancelled,
                    message: "The request was cancelled by the mock SpeakSwiftly runtime control surface."
                )
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
                reason: "The queued request was cancelled by the mock SpeakSwiftly runtime control surface."
            )
            return requestID
        }

        throw WorkerError(
            code: .requestNotFound,
            message: "The mock SpeakSwiftly runtime could not find request '\(requestID)' to cancel."
        )
    }
}

@Test func configurationLoadsDefaultsAndRejectsInvalidValues() throws {
    let defaults = try ServerConfiguration.load(environment: [:])
    #expect(defaults.host == "127.0.0.1")
    #expect(defaults.port == 7337)
    #expect(defaults.sseHeartbeatSeconds == 10)
    #expect(defaults.completedJobTTLSeconds == 900)

    do {
        _ = try ServerConfiguration.load(environment: ["APP_PORT": "zero"])
        Issue.record("Expected invalid APP_PORT to throw a configuration error.")
    } catch let error as ServerConfigurationError {
        #expect(error.message.contains("APP_PORT"))
    }
}

@available(macOS 14, *)
@Test func stateCompletesQueuedSpeechJobsAndPrunesExpiredEntries() async throws {
    let runtime = MockRuntime()
    let state = ServerState(
        configuration: testConfiguration(completedJobTTLSeconds: 0.05, jobPruneIntervalSeconds: 0.02),
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let jobID = try await state.submitSpeak(text: "Hello from the test suite", profileName: "default")
    let snapshot = try await waitForJobSnapshot(jobID, on: state)

    #expect(snapshot.jobID == jobID)
    #expect(snapshot.status == "completed")
    #expect(snapshot.terminalEvent != nil)
    #expect(snapshot.history.count >= 3)

    try await Task.sleep(for: .milliseconds(120))
    try await waitUntilJobDisappears(jobID, on: state)

    await state.shutdown()
}

@available(macOS 14, *)
@Test func statePrunesOldestCompletedJobsWhenMaxCountIsExceeded() async throws {
    let runtime = MockRuntime()
    let state = ServerState(
        configuration: testConfiguration(completedJobTTLSeconds: 60, completedJobMaxCount: 2),
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let first = try await state.submitSpeak(text: "One", profileName: "default")
    let second = try await state.submitSpeak(text: "Two", profileName: "default")
    let third = try await state.submitSpeak(text: "Three", profileName: "default")

    _ = try await waitForJobSnapshot(first, on: state)
    _ = try await waitForJobSnapshot(second, on: state)
    _ = try await waitForJobSnapshot(third, on: state)

    try await waitUntilJobDisappears(first, on: state)
    let secondSnapshot = try await state.jobSnapshot(id: second)
    let thirdSnapshot = try await state.jobSnapshot(id: third)
    #expect(secondSnapshot.status == "completed")
    #expect(thirdSnapshot.status == "completed")

    await state.shutdown()
}

@available(macOS 14, *)
@Test func sseReplayIncludesWorkerStatusHistoryAndHeartbeat() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = ServerState(
        configuration: testConfiguration(sseHeartbeatSeconds: 0.02),
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let jobID = try await state.submitSpeak(text: "Keep speaking", profileName: "default")
    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10)
    ) {
        let snapshot = try await state.jobSnapshot(id: jobID)
        return snapshot.history.count >= 2 ? snapshot : nil
    }

    let stream = try await state.sseStream(for: jobID)
    var iterator = stream.makeAsyncIterator()
    let first = try #require(await iterator.next())
    let second = try #require(await iterator.next())
    let third = try #require(await iterator.next())

    #expect(string(from: first).contains("event: worker_status"))
    #expect(string(from: second).contains("event: message"))
    #expect(string(from: third).contains("event: started"))

    var heartbeat: String?
    for _ in 0..<20 {
        guard let chunk = await iterator.next() else { break }
        let text = string(from: chunk)
        if text == ": keep-alive\n\n" {
            heartbeat = text
            break
        }
    }
    #expect(heartbeat == ": keep-alive\n\n")

    await runtime.finishHeldSpeak(id: jobID)
    await state.shutdown()
}

@available(macOS 14, *)
@Test func routesExposeHealthProfilesAndQueuedSpeechJobLifecycle() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = ServerState(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let app = makeApplication(configuration: configuration, state: state)
    try await app.test(.router) { client in
        let healthResponse = try await client.execute(uri: "/healthz", method: .get)
        let healthJSON = try jsonObject(from: healthResponse.body)
        #expect(healthResponse.status == .ok)
        #expect(healthJSON["status"] as? String == "ok")
        #expect(healthJSON["worker_ready"] as? Bool == true)

        let profilesResponse = try await client.execute(uri: "/profiles", method: .get)
        let profilesJSON = try jsonObject(from: profilesResponse.body)
        let profiles = try #require(profilesJSON["profiles"] as? [[String: Any]])
        #expect(profiles.count == 1)
        #expect(profiles.first?["profile_name"] as? String == "default")

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Route test","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        let speakJobID = try #require(speakJSON["job_id"] as? String)
        #expect(speakResponse.status == .accepted)
        #expect((speakJSON["job_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["events_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["job_url"] as? String)?.hasPrefix("http://") == true)

        _ = try await waitForJobSnapshot(speakJobID, on: state)

        let foregroundJobResponse = try await client.execute(uri: "/jobs/\(speakJobID)", method: .get)
        let foregroundJobJSON = try jsonObject(from: foregroundJobResponse.body)
        #expect(foregroundJobResponse.status == .ok)
        #expect(foregroundJobJSON["job_id"] as? String == speakJobID)
        #expect(foregroundJobJSON["status"] as? String == "completed")
        let foregroundHistory = try #require(foregroundJobJSON["history"] as? [[String: Any]])
        #expect(foregroundHistory.contains { $0["event"] as? String == "started" })
        #expect(foregroundHistory.filter { $0["ok"] as? Bool == true }.count == 2)
    }

    await state.shutdown()
}

@available(macOS 14, *)
@Test func routesExposeQueueInspectionAndControlOperations() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = ServerState(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let app = makeApplication(configuration: configuration, state: state)
    try await app.test(.router) { client in
        let activeResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Hold the line","profile_name":"default"}"#)
        )
        let activeJobID = try #require(try jsonObject(from: activeResponse.body)["job_id"] as? String)

        let queuedResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue this request","profile_name":"default"}"#)
        )
        let queuedJobID = try #require(try jsonObject(from: queuedResponse.body)["job_id"] as? String)

        let queueResponse = try await client.execute(uri: "/queue/generation", method: .get)
        let queueJSON = try jsonObject(from: queueResponse.body)
        #expect(queueResponse.status == .ok)
        #expect(queueJSON["queue_type"] as? String == "generation")
        let activeRequest = try #require(queueJSON["active_request"] as? [String: Any])
        #expect(activeRequest["id"] as? String == activeJobID)
        let queuedRequests = try #require(queueJSON["queue"] as? [[String: Any]])
        #expect(queuedRequests.count == 1)
        #expect(queuedRequests.first?["id"] as? String == queuedJobID)
        #expect(queuedRequests.first?["queue_position"] as? Int == 1)

        let playbackStateResponse = try await client.execute(uri: "/playback", method: .get)
        let playbackStateJSON = try jsonObject(from: playbackStateResponse.body)
        #expect(playbackStateResponse.status == .ok)
        let playback = try #require(playbackStateJSON["playback"] as? [String: Any])
        #expect(playback["state"] as? String == "playing")
        let playbackActiveRequest = try #require(playback["active_request"] as? [String: Any])
        #expect(playbackActiveRequest["id"] as? String == activeJobID)

        let pauseResponse = try await client.execute(uri: "/playback/pause", method: .post)
        let pauseJSON = try jsonObject(from: pauseResponse.body)
        #expect(pauseResponse.status == .ok)
        #expect((pauseJSON["playback"] as? [String: Any])?["state"] as? String == "paused")

        let resumeResponse = try await client.execute(uri: "/playback/resume", method: .post)
        let resumeJSON = try jsonObject(from: resumeResponse.body)
        #expect(resumeResponse.status == .ok)
        #expect((resumeJSON["playback"] as? [String: Any])?["state"] as? String == "playing")

        let playbackQueueResponse = try await client.execute(uri: "/queue/playback", method: .get)
        let playbackQueueJSON = try jsonObject(from: playbackQueueResponse.body)
        #expect(playbackQueueResponse.status == .ok)
        #expect(playbackQueueJSON["queue_type"] as? String == "playback")
        #expect((playbackQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
        #expect((playbackQueueJSON["queue"] as? [[String: Any]])?.isEmpty == true)

        let cancelResponse = try await client.execute(uri: "/queue/\(queuedJobID)", method: .delete)
        let cancelJSON = try jsonObject(from: cancelResponse.body)
        #expect(cancelResponse.status == .ok)
        #expect(cancelJSON["cancelled_request_id"] as? String == queuedJobID)

        let cancelledSnapshot = try await waitForJobSnapshot(queuedJobID, on: state)
        switch cancelledSnapshot.terminalEvent {
        case .failed(let failure):
            #expect(failure.code == WorkerErrorCode.requestCancelled.rawValue)
        default:
            Issue.record("Expected the cancelled queued request to terminate with a request_cancelled failure.")
        }

        let anotherQueuedResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue another request","profile_name":"default"}"#)
        )
        let anotherQueuedJobID = try #require(try jsonObject(from: anotherQueuedResponse.body)["job_id"] as? String)

        let clearResponse = try await client.execute(uri: "/queue", method: .delete)
        let clearJSON = try jsonObject(from: clearResponse.body)
        #expect(clearResponse.status == .ok)
        #expect(clearJSON["cleared_count"] as? Int == 1)

        let clearedSnapshot = try await waitForJobSnapshot(anotherQueuedJobID, on: state)
        switch clearedSnapshot.terminalEvent {
        case .failed(let failure):
            #expect(failure.code == WorkerErrorCode.requestCancelled.rawValue)
        default:
            Issue.record("Expected the cleared queued request to terminate with a request_cancelled failure.")
        }

        let emptyQueueResponse = try await client.execute(uri: "/queue/generation", method: .get)
        let emptyQueueJSON = try jsonObject(from: emptyQueueResponse.body)
        let remainingQueue = try #require(emptyQueueJSON["queue"] as? [[String: Any]])
        #expect(remainingQueue.isEmpty)
        #expect((emptyQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
    }

    await runtime.finishHeldSpeak(id: try await waitForActiveRequestID(on: state))
    await state.shutdown()
}

@available(macOS 14, *)
@Test func routesReportNotReadyAndMissingJobsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = ServerState(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()

    let app = makeApplication(configuration: configuration, state: state)
    try await app.test(.router) { client in
        let readyResponse = try await client.execute(uri: "/readyz", method: .get)
        let readyJSON = try jsonObject(from: readyResponse.body)
        #expect(readyResponse.status == .serviceUnavailable)
        #expect(readyJSON["status"] as? String == "not_ready")

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Too soon","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        #expect(speakResponse.status == .serviceUnavailable)
        let speakError = try #require(speakJSON["error"] as? [String: Any])
        #expect((speakError["message"] as? String)?.contains("cannot accept new work") == true)

        let missingJob = try await client.execute(uri: "/jobs/missing-job", method: .get)
        let missingJSON = try jsonObject(from: missingJob.body)
        #expect(missingJob.status == .notFound)
        let missingJobError = try #require(missingJSON["error"] as? [String: Any])
        #expect((missingJobError["message"] as? String)?.contains("expired from in-memory retention") == true)

        let missingEvents = try await client.execute(uri: "/jobs/missing-job/events", method: .get)
        let missingEventsJSON = try jsonObject(from: missingEvents.body)
        #expect(missingEvents.status == .notFound)
        let missingEventsError = try #require(missingEventsJSON["error"] as? [String: Any])
        #expect((missingEventsError["message"] as? String)?.contains("expired from in-memory retention") == true)
    }

    await state.shutdown()
}

@available(macOS 14, *)
@Test func profileMutationFailureMarksCacheStaleAndFailsJob() async throws {
    let runtime = MockRuntime(mutationRefreshBehavior: .leaveProfilesUnchanged)
    let state = ServerState(
        configuration: testConfiguration(),
        runtime: runtime,
        makeRuntime: { runtime }
    )

    await state.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(state)

    let jobID = try await state.submitCreateProfile(
        profileName: "bright-guide",
        text: "Hello there",
        voiceDescription: "Warm and bright",
        outputPath: nil
    )
    let snapshot = try await waitForJobSnapshot(jobID, on: state)

    switch snapshot.terminalEvent {
    case .failed(let failure):
        #expect(failure.code == "profile_refresh_mismatch")
        #expect(failure.message.contains("could not confirm the profile list"))
    default:
        Issue.record("Expected create_profile reconciliation failure to produce a failed terminal event.")
    }

    let status = await state.statusSnapshot()
    #expect(status.profileCacheState == "stale")
    #expect(status.profileCacheWarning?.contains("could not confirm the refreshed profile list") == true)

    await state.shutdown()
}

private func testConfiguration(
    sseHeartbeatSeconds: Double = 0.05,
    completedJobTTLSeconds: Double = 30,
    completedJobMaxCount: Int = 20,
    jobPruneIntervalSeconds: Double = 0.05
) -> ServerConfiguration {
    .init(
        name: "speak-swiftly-server-tests",
        environment: "test",
        host: "127.0.0.1",
        port: 7337,
        sseHeartbeatSeconds: sseHeartbeatSeconds,
        completedJobTTLSeconds: completedJobTTLSeconds,
        completedJobMaxCount: completedJobMaxCount,
        jobPruneIntervalSeconds: jobPruneIntervalSeconds
    )
}

private func sampleProfile() -> ProfileSummary {
    .init(
        profileName: "default",
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        voiceDescription: "Warm and clear",
        sourceText: "A reference voice sample."
    )
}

@available(macOS 14, *)
private func waitUntilReady(_ state: ServerState) async throws {
    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let (ready, _) = await state.readinessSnapshot()
        return ready ? true : nil
    }
}

@available(macOS 14, *)
private func waitForJobSnapshot(_ jobID: String, on state: ServerState) async throws -> JobSnapshot {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            let snapshot = try await state.jobSnapshot(id: jobID)
            return snapshot.terminalEvent == nil ? nil : snapshot
        } catch {
            return nil
        }
    }
}

@available(macOS 14, *)
private func waitUntilJobDisappears(_ jobID: String, on state: ServerState) async throws {
    let _: Bool = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            _ = try await state.jobSnapshot(id: jobID)
            return nil
        } catch {
            return true
        }
    }
}

private func waitUntil<T: Sendable>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping @Sendable () async throws -> T?
) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(for: pollInterval)
    }
    throw TimeoutError()
}

@available(macOS 14, *)
private func waitForActiveRequestID(on state: ServerState) async throws -> String {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await state.queueSnapshot(queueType: .generation)
        return snapshot.activeRequest?.id
    }
}

private struct TimeoutError: Error {}

private func byteBuffer(_ string: String) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
    buffer.writeString(string)
    return buffer
}

private func string(from buffer: ByteBuffer) -> String {
    String(decoding: buffer.readableBytesView, as: UTF8.self)
}

private func jsonObject(from buffer: ByteBuffer) throws -> [String: Any] {
    let data = Data(buffer.readableBytesView)
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = json as? [String: Any] else {
        throw JSONError.notDictionary
    }
    return dictionary
}

private enum JSONError: Error {
    case notDictionary
}
