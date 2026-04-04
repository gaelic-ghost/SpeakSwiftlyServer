import Foundation
import Hummingbird
import HummingbirdTesting
import NIOCore
import SpeakSwiftlyCore
import Testing
@testable import SpeakSwiftlyServer

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct MockRequest: Sendable {
        let id: String
        let operationName: String
        let profileName: String?
    }

    struct QueuedRequestState: Sendable {
        let request: MockRequest
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
    private var activeRequest: MockRequest?
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

    func queueSpeechHandle(text: String, profileName: String, as jobType: SpeechJobType, id: String) async -> RuntimeRequestHandle {
        let request = MockRequest(id: id, operationName: speechOperationName(for: jobType), profileName: profileName)
        var requestContinuation: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation?
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a speech request continuation for request '\(id)'.")
        }

        continuation.yield(.acknowledged(.init(id: id)))

        if self.activeRequest == nil {
            self.startActiveRequest(request, continuation: continuation)
        } else {
            self.queuedRequests.append(.init(request: request, continuation: continuation))
            continuation.yield(
                .queued(
                    .init(
                        id: id,
                        reason: .waitingForActiveRequest,
                        queuePosition: self.queuedRequests.count
                    )
                )
            )
        }

        return RuntimeRequestHandle(id: id, operationName: request.operationName, profileName: profileName, events: events)
    }

    func createProfileHandle(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        _ = outputPath
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
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(.completed(WorkerSuccessResponse(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "create_profile", profileName: profileName, events: events)
    }

    func listProfilesHandle(id: String) async -> RuntimeRequestHandle {
        let profiles = self.profiles
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(.completed(WorkerSuccessResponse(id: id, profiles: profiles)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "list_profiles", profileName: nil, events: events)
    }

    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle {
        if mutationRefreshBehavior == .applyMutations {
            profiles.removeAll { $0.profileName == profileName }
        }
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(.completed(WorkerSuccessResponse(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "remove_profile", profileName: profileName, events: events)
    }

    func listQueueHandle(_ queueType: WorkerQueueType, id requestID: String) async -> RuntimeRequestHandle {
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
        let operationName = queueType == .generation ? "list_queue_generation" : "list_queue_playback"
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    WorkerSuccessResponse(
                        id: requestID,
                        activeRequest: activeRequest,
                        queue: queue
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operationName: operationName, profileName: nil, events: events)
    }

    func playbackHandle(_ action: PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
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
        let playbackState = self.playbackStateSummary()
        let operationName = playbackOperationName(for: action)
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    WorkerSuccessResponse(
                        id: requestID,
                        playbackState: playbackState
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operationName: operationName, profileName: nil, events: events)
    }

    func clearQueueHandle(id requestID: String) async -> RuntimeRequestHandle {
        let clearedRequestIDs = queuedRequests.map(\.request.id)
        let clearedCount = clearedRequestIDs.count
        for queuedRequestID in clearedRequestIDs {
            cancelQueuedRequest(
                queuedRequestID,
                reason: "The request was cancelled because queued work was cleared from the mock SpeakSwiftly runtime."
            )
        }
        let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
            continuation.yield(.completed(WorkerSuccessResponse(id: requestID, clearedCount: clearedCount)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operationName: "clear_queue", profileName: nil, events: events)
    }

    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle {
        do {
            let cancelledRequestID = try cancelRequestNow(id)
            let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                continuation.yield(
                    .completed(
                        WorkerSuccessResponse(
                            id: requestID,
                            cancelledRequestID: cancelledRequestID
                        )
                    )
                )
                continuation.finish()
            }
            return RuntimeRequestHandle(id: requestID, operationName: "cancel_request", profileName: nil, events: events)
        } catch {
            let events = AsyncThrowingStream<WorkerRequestStreamEvent, Error> { continuation in
                continuation.finish(throwing: error)
            }
            return RuntimeRequestHandle(id: requestID, operationName: "cancel_request", profileName: nil, events: events)
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
        _ request: MockRequest,
        continuation: AsyncThrowingStream<WorkerRequestStreamEvent, Error>.Continuation
    ) {
        activeRequest = request
        playbackState = .playing
        continuation.yield(.started(.init(id: request.id, op: request.operationName)))

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

    private func activeSummary(for request: MockRequest) -> ActiveWorkerRequestSummary {
        .init(id: request.id, op: request.operationName, profileName: request.profileName)
    }

    private func queuedSummaries() -> [QueuedWorkerRequestSummary] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.operationName,
                profileName: queued.request.profileName,
                queuePosition: offset + 1
            )
        }
    }

    private func speechOperationName(for jobType: SpeechJobType) -> String {
        switch jobType {
        case .live:
            "queue_speech_live"
        }
    }

    private func playbackOperationName(for action: PlaybackAction) -> String {
        switch action {
        case .pause:
            "playback_pause"
        case .resume:
            "playback_resume"
        case .state:
            "playback_state"
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
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(completedJobTTLSeconds: 0.05, jobPruneIntervalSeconds: 0.02),
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitSpeak(text: "Hello from the test suite", profileName: "default")
    let snapshot = try await waitForJobSnapshot(jobID, on: host)

    #expect(snapshot.jobID == jobID)
    #expect(snapshot.status == "completed")
    #expect(snapshot.terminalEvent != nil)
    #expect(snapshot.history.count >= 3)

    try await Task.sleep(for: .milliseconds(120))
    try await waitUntilJobDisappears(jobID, on: host)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func statePrunesOldestCompletedJobsWhenMaxCountIsExceeded() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(completedJobTTLSeconds: 60, completedJobMaxCount: 2),
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let first = try await host.submitSpeak(text: "One", profileName: "default")
    let second = try await host.submitSpeak(text: "Two", profileName: "default")
    let third = try await host.submitSpeak(text: "Three", profileName: "default")

    _ = try await waitForJobSnapshot(first, on: host)
    _ = try await waitForJobSnapshot(second, on: host)
    _ = try await waitForJobSnapshot(third, on: host)

    try await waitUntilJobDisappears(first, on: host)
    let secondSnapshot = try await host.jobSnapshot(id: second)
    let thirdSnapshot = try await host.jobSnapshot(id: third)
    #expect(secondSnapshot.status == "completed")
    #expect(thirdSnapshot.status == "completed")

    await host.shutdown()
}

@available(macOS 14, *)
@Test func sseReplayIncludesWorkerStatusHistoryAndHeartbeat() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(sseHeartbeatSeconds: 0.02),
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitSpeak(text: "Keep speaking", profileName: "default")
    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10)
    ) {
        let snapshot = try await host.jobSnapshot(id: jobID)
        return snapshot.history.count >= 2 ? snapshot : nil
    }

    let stream = try await host.sseStream(for: jobID)
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
    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesExposeHealthProfilesAndQueuedSpeechJobLifecycle() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = makeApplication(configuration: configuration, host: host)
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

        _ = try await waitForJobSnapshot(speakJobID, on: host)

        let foregroundJobResponse = try await client.execute(uri: "/jobs/\(speakJobID)", method: .get)
        let foregroundJobJSON = try jsonObject(from: foregroundJobResponse.body)
        #expect(foregroundJobResponse.status == .ok)
        #expect(foregroundJobJSON["job_id"] as? String == speakJobID)
        #expect(foregroundJobJSON["status"] as? String == "completed")
        let foregroundHistory = try #require(foregroundJobJSON["history"] as? [[String: Any]])
        #expect(foregroundHistory.contains { $0["event"] as? String == "started" })
        #expect(foregroundHistory.filter { $0["ok"] as? Bool == true }.count == 2)
    }

    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesExposeQueueInspectionAndControlOperations() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = makeApplication(configuration: configuration, host: host)
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

        let cancelledSnapshot = try await waitForJobSnapshot(queuedJobID, on: host)
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

        let clearedSnapshot = try await waitForJobSnapshot(anotherQueuedJobID, on: host)
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

    await runtime.finishHeldSpeak(id: try await waitForActiveRequestID(on: host))
    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesReportNotReadyAndMissingJobsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()

    let app = makeApplication(configuration: configuration, host: host)
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

    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesReportWorkerStartupFailureClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelFailed)

    let app = makeApplication(configuration: configuration, host: host)
    try await app.test(.router) { client in
        let readyResponse = try await client.execute(uri: "/readyz", method: .get)
        let readyJSON = try jsonObject(from: readyResponse.body)
        #expect(readyResponse.status == .serviceUnavailable)
        #expect(readyJSON["status"] as? String == "not_ready")
        #expect(readyJSON["worker_mode"] as? String == "failed")
        #expect((readyJSON["startup_error"] as? String)?.contains("startup failure") == true)

        let statusResponse = try await client.execute(uri: "/status", method: .get)
        let statusJSON = try jsonObject(from: statusResponse.body)
        #expect(statusResponse.status == .ok)
        #expect(statusJSON["worker_mode"] as? String == "failed")
        #expect(statusJSON["worker_stage"] as? String == "resident_model_failed")
        #expect((statusJSON["worker_failure_summary"] as? String)?.contains("startup failure") == true)

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Still broken","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        #expect(speakResponse.status == .serviceUnavailable)
        let speakError = try #require(speakJSON["error"] as? [String: Any])
        #expect((speakError["message"] as? String)?.contains("startup failure") == true)
    }

    await host.shutdown()
}

@available(macOS 14, *)
@Test func runtimeDegradationWhileSpeechJobsAreInFlightMarksJobsDegradedAndRejectsNewWork() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let activeJobID = try await host.submitSpeak(text: "Keep talking", profileName: "default")
    let queuedJobID = try await host.submitSpeak(text: "Wait your turn", profileName: "default")

    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: queuedJobID)
        return snapshot.history.contains {
            guard case .queued = $0 else { return false }
            return true
        } ? snapshot : nil
    }

    await runtime.publishStatus(.residentModelFailed)

    let degradedReadiness = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = await host.readinessSnapshot()
        return snapshot.1.workerMode == "failed" ? snapshot : nil
    }
    #expect(degradedReadiness.0 == false)
    #expect(degradedReadiness.1.workerMode == "failed")
    #expect(degradedReadiness.1.workerStage == "resident_model_failed")
    #expect(degradedReadiness.1.startupError?.contains("startup failure") == true)

    let activeSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: activeJobID)
        return snapshot.history.contains {
            guard case .workerStatus(let event) = $0 else { return false }
            return event.workerMode == "failed" && event.stage == "resident_model_failed"
        } ? snapshot : nil
    }
    #expect(activeSnapshot.terminalEvent == nil)

    let queuedSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: queuedJobID)
        return snapshot.history.contains {
            guard case .workerStatus(let event) = $0 else { return false }
            return event.workerMode == "failed" && event.stage == "resident_model_failed"
        } ? snapshot : nil
    }
    #expect(queuedSnapshot.terminalEvent == nil)

    do {
        _ = try await host.submitSpeak(text: "Do not accept this", profileName: "default")
        Issue.record("Expected the degraded worker state to reject new speech work.")
    } catch {
        let message = String(describing: error)
        #expect(message.contains("startup failure"))
    }

    await runtime.finishHeldSpeak(id: activeJobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func profileMutationFailureMarksCacheStaleAndFailsJob() async throws {
    let runtime = MockRuntime(mutationRefreshBehavior: .leaveProfilesUnchanged)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        makeRuntime: { runtime },
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitCreateProfile(
        profileName: "bright-guide",
        text: "Hello there",
        voiceDescription: "Warm and bright",
        outputPath: nil
    )
    let snapshot = try await waitForJobSnapshot(jobID, on: host)

    switch snapshot.terminalEvent {
    case .failed(let failure):
        #expect(failure.code == "profile_refresh_mismatch")
        #expect(failure.message.contains("could not confirm the profile list"))
    default:
        Issue.record("Expected create_profile reconciliation failure to produce a failed terminal event.")
    }

    let status = await host.statusSnapshot()
    #expect(status.profileCacheState == "stale")
    #expect(status.profileCacheWarning?.contains("could not confirm the refreshed profile list") == true)

    await host.shutdown()
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
private func waitUntilReady(_ host: ServerHost) async throws {
    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let (ready, _) = await host.readinessSnapshot()
        return ready ? true : nil
    }
}

@available(macOS 14, *)
private func waitForJobSnapshot(_ jobID: String, on host: ServerHost) async throws -> JobSnapshot {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            let snapshot = try await host.jobSnapshot(id: jobID)
            return snapshot.terminalEvent == nil ? nil : snapshot
        } catch {
            return nil
        }
    }
}

@available(macOS 14, *)
private func waitUntilJobDisappears(_ jobID: String, on host: ServerHost) async throws {
    let _: Bool = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            _ = try await host.jobSnapshot(id: jobID)
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
private func waitForActiveRequestID(on host: ServerHost) async throws -> String {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.queueSnapshot(queueType: .generation)
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
