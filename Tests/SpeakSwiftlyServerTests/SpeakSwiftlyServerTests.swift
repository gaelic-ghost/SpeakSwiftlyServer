import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftlyCore
import Testing
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - Mock Runtime

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct MockRequest: Sendable {
        let id: String
        let operationName: String
        let profileName: String?
    }

    struct QueuedSpeechInvocation: Sendable, Equatable {
        let text: String
        let profileName: String
        let normalizationContext: SpeechNormalizationContext?
    }

    struct CreateCloneInvocation: Sendable, Equatable {
        let profileName: String
        let referenceAudioPath: String
        let transcript: String?
    }

    struct QueuedRequestState: Sendable {
        let request: MockRequest
        let continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    }

    enum SpeakBehavior: Sendable {
        case completeImmediately
        case holdOpen
    }

    enum MutationRefreshBehavior: Sendable {
        case applyMutations
        case leaveProfilesUnchanged
    }

    var profiles: [SpeakSwiftly.ProfileSummary]
    var speakBehavior: SpeakBehavior
    var mutationRefreshBehavior: MutationRefreshBehavior
    private var statusContinuation: AsyncStream<SpeakSwiftly.StatusEvent>.Continuation?
    private var activeRequest: MockRequest?
    private var activeContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
    private var queuedRequests = [QueuedRequestState]()
    private var queuedSpeechInvocations = [QueuedSpeechInvocation]()
    private var createCloneInvocations = [CreateCloneInvocation]()
    private var playbackState: SpeakSwiftly.PlaybackState = .idle

    // MARK: - Lifecycle

    init(
        profiles: [SpeakSwiftly.ProfileSummary] = [sampleProfile()],
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

    func statusEvents() -> AsyncStream<SpeakSwiftly.StatusEvent> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
        }
    }

    // MARK: - Runtime Protocol

    func queueSpeechHandle(
        text: String,
        profileName: String,
        normalizationContext: SpeechNormalizationContext?,
        as jobType: SpeakSwiftly.Job,
        id: String
    ) async -> RuntimeRequestHandle {
        let request = MockRequest(id: id, operationName: speechOperationName(for: jobType), profileName: profileName)
        queuedSpeechInvocations.append(
            .init(
                text: text,
                profileName: profileName,
                normalizationContext: normalizationContext
            )
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
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
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    createdAt: Date(),
                    voiceDescription: voiceDescription,
                    sourceText: text
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "create_profile", profileName: profileName, events: events)
    }

    func createCloneHandle(
        profileName: String,
        referenceAudioPath: String,
        transcript: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        createCloneInvocations.append(
            .init(
                profileName: profileName,
                referenceAudioPath: referenceAudioPath,
                transcript: transcript
            )
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    createdAt: Date(),
                    voiceDescription: "Imported reference audio clone.",
                    sourceText: transcript ?? "Imported clone transcript."
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "create_clone", profileName: profileName, events: events)
    }

    func listProfilesHandle(id: String) async -> RuntimeRequestHandle {
        let profiles = self.profiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profiles: profiles)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "list_profiles", profileName: nil, events: events)
    }

    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle {
        if mutationRefreshBehavior == .applyMutations {
            profiles.removeAll { $0.profileName == profileName }
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operationName: "remove_profile", profileName: profileName, events: events)
    }

    func listQueueHandle(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle {
        let activeRequest: SpeakSwiftly.ActiveRequest? =
            switch queueType {
            case .generation:
                self.activeRequest.map(self.activeSummary(for:))
            case .playback:
                playbackState == .idle ? nil : self.activeRequest.map(self.activeSummary(for:))
            }
        let queue: [SpeakSwiftly.QueuedRequest] =
            switch queueType {
            case .generation:
                self.queuedSummaries()
            case .playback:
                []
            }
        let operationName = queueType == .generation ? "list_queue_generation" : "list_queue_playback"
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
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

    func playbackHandle(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
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
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
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
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, clearedCount: clearedCount)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operationName: "clear_queue", profileName: nil, events: events)
    }

    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle {
        do {
            let cancelledRequestID = try cancelRequestNow(id)
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.yield(
                    .completed(
                        SpeakSwiftly.Success(
                            id: requestID,
                            cancelledRequestID: cancelledRequestID
                        )
                    )
                )
                continuation.finish()
            }
            return RuntimeRequestHandle(id: requestID, operationName: "cancel_request", profileName: nil, events: events)
        } catch {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(throwing: error)
            }
            return RuntimeRequestHandle(id: requestID, operationName: "cancel_request", profileName: nil, events: events)
        }
    }

    // MARK: - Test Control

    func publishStatus(_ stage: SpeakSwiftly.StatusStage) {
        statusContinuation?.yield(.init(stage: stage))
    }

    func finishHeldSpeak(id: String) {
        guard activeRequest?.id == id, let continuation = activeContinuation else { return }
        continuation.yield(
            SpeakSwiftly.RequestEvent.progress(
                .init(id: id, stage: .playbackFinished)
            )
        )
            continuation.yield(
                SpeakSwiftly.RequestEvent.completed(
                    .init(id: id)
            )
        )
        continuation.finish()
        playbackState = .idle
        activeContinuation = nil
        activeRequest = nil
        startNextQueuedRequestIfNeeded()
    }

    func latestQueuedSpeechInvocation() -> QueuedSpeechInvocation? {
        queuedSpeechInvocations.last
    }

    func latestCreateCloneInvocation() -> CreateCloneInvocation? {
        createCloneInvocations.last
    }

    // MARK: - Internal Helpers

    private func startActiveRequest(
        _ request: MockRequest,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
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

    private func activeSummary(for request: MockRequest) -> SpeakSwiftly.ActiveRequest {
        .init(id: request.id, op: request.operationName, profileName: request.profileName)
    }

    private func queuedSummaries() -> [SpeakSwiftly.QueuedRequest] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.operationName,
                profileName: queued.request.profileName,
                queuePosition: offset + 1
            )
        }
    }

    private func speechOperationName(for jobType: SpeakSwiftly.Job) -> String {
        switch jobType {
        case .live:
            "queue_speech_live"
        }
    }

    private func playbackOperationName(for action: SpeakSwiftly.PlaybackAction) -> String {
        switch action {
        case .pause:
            "playback_pause"
        case .resume:
            "playback_resume"
        case .state:
            "playback_state"
        }
    }

    private func playbackStateSummary() -> SpeakSwiftly.PlaybackStateSnapshot {
        .init(
            state: playbackState,
            activeRequest: playbackState == .idle ? nil : activeRequest.map(activeSummary(for:))
        )
    }

    private func cancelQueuedRequest(_ requestID: String, reason: String) {
        guard let index = queuedRequests.firstIndex(where: { $0.request.id == requestID }) else { return }
        let queued = queuedRequests.remove(at: index)
        queued.continuation.finish(
            throwing: SpeakSwiftly.Error(code: .requestCancelled, message: reason)
        )
    }

    private func cancelRequestNow(_ requestID: String) throws -> String {
        if activeRequest?.id == requestID {
            activeContinuation?.finish(
                throwing: SpeakSwiftly.Error(
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

        throw SpeakSwiftly.Error(
            code: .requestNotFound,
            message: "The mock SpeakSwiftly runtime could not find request '\(requestID)' to cancel."
        )
    }
}

// MARK: - Host and Route Tests

@Test func configurationLoadsDefaultsAndRejectsInvalidValues() async throws {
    let defaults = try await AppConfig.load(environment: [:])
    #expect(defaults.server.host == "127.0.0.1")
    #expect(defaults.server.port == 7337)
    #expect(defaults.http.host == "127.0.0.1")
    #expect(defaults.http.port == 7337)
    #expect(defaults.http.sseHeartbeatSeconds == 10)
    #expect(defaults.server.sseHeartbeatSeconds == 10)
    #expect(defaults.server.completedJobTTLSeconds == 900)

    let appConfig = try await AppConfig.load(environment: [
        "APP_PORT": "7550",
        "APP_HTTP_ENABLED": "false",
        "APP_HTTP_HOST": "0.0.0.0",
        "APP_HTTP_PORT": "7444",
        "APP_HTTP_SSE_HEARTBEAT_SECONDS": "2.5",
        "APP_MCP_ENABLED": "true",
        "APP_MCP_PATH": "/assistant/mcp",
        "APP_MCP_SERVER_NAME": "speak-swiftly-agent",
        "APP_MCP_TITLE": "SpeakSwiftly Server MCP",
    ])
    #expect(appConfig.server.port == 7550)
    #expect(appConfig.http.enabled == false)
    #expect(appConfig.http.host == "0.0.0.0")
    #expect(appConfig.http.port == 7444)
    #expect(appConfig.http.sseHeartbeatSeconds == 2.5)
    #expect(appConfig.mcp.enabled == true)
    #expect(appConfig.mcp.path == "/assistant/mcp")
    #expect(appConfig.mcp.serverName == "speak-swiftly-agent")
    #expect(appConfig.mcp.title == "SpeakSwiftly Server MCP")

    let configDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let yamlURL = configDirectory.appendingPathComponent("server.yaml")
    try """
    app:
      name: yaml-server
      environment: staging
      host: 192.168.1.10
      port: 7555
      sseHeartbeatSeconds: 4
      completedJobTTLSeconds: 30
      completedJobMaxCount: 25
      jobPruneIntervalSeconds: 5
      http:
        enabled: false
        host: 0.0.0.0
        port: 7666
        sseHeartbeatSeconds: 1.5
      mcp:
        enabled: true
        path: /assistant/mcp
        serverName: yaml-mcp
        title: YAML MCP
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let yamlConfig = try await AppConfig.load(environment: [
        "APP_CONFIG_FILE": yamlURL.path,
        "APP_HTTP_PORT": "7777",
    ])
    #expect(yamlConfig.server.name == "yaml-server")
    #expect(yamlConfig.server.environment == "staging")
    #expect(yamlConfig.server.host == "192.168.1.10")
    #expect(yamlConfig.server.port == 7555)
    #expect(yamlConfig.http.enabled == false)
    #expect(yamlConfig.http.host == "0.0.0.0")
    #expect(yamlConfig.http.port == 7777)
    #expect(yamlConfig.mcp.enabled == true)
    #expect(yamlConfig.mcp.path == "/assistant/mcp")
    #expect(yamlConfig.mcp.serverName == "yaml-mcp")
    #expect(yamlConfig.mcp.title == "YAML MCP")

    let inheritedTransportConfig = try await AppConfig.load(environment: [
        "APP_HOST": "0.0.0.0",
        "APP_PORT": "7999",
        "APP_SSE_HEARTBEAT_SECONDS": "3.25",
    ])
    #expect(inheritedTransportConfig.server.host == "0.0.0.0")
    #expect(inheritedTransportConfig.server.port == 7999)
    #expect(inheritedTransportConfig.server.sseHeartbeatSeconds == 3.25)
    #expect(inheritedTransportConfig.http.host == "0.0.0.0")
    #expect(inheritedTransportConfig.http.port == 7999)
    #expect(inheritedTransportConfig.http.sseHeartbeatSeconds == 3.25)

    do {
        _ = try await AppConfig.load(environment: ["APP_PORT": "zero"])
        Issue.record("Expected invalid APP_PORT to throw a configuration error.")
    } catch let error as ServerConfigurationError {
        #expect(error.message.contains("APP_PORT"))
    }

    do {
        _ = try await AppConfig.load(environment: ["APP_HTTP_PORT": "zero"])
        Issue.record("Expected invalid APP_HTTP_PORT to throw a configuration error.")
    } catch let error as ServerConfigurationError {
        #expect(error.message.contains("APP_HTTP_PORT"))
    }
}

@Test func configStoreLoadsYamlAndExposesReloadingServiceWhenConfigFileIsSet() async throws {
    let configDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let yamlURL = configDirectory.appendingPathComponent("server.yaml")
    try """
    app:
      name: initial-server
      environment: development
      host: 127.0.0.1
      port: 7337
      sseHeartbeatSeconds: 4
      completedJobTTLSeconds: 30
      completedJobMaxCount: 25
      jobPruneIntervalSeconds: 5
      http:
        enabled: true
        host: 127.0.0.1
        port: 7337
        sseHeartbeatSeconds: 4
      mcp:
        enabled: false
        path: /mcp
        serverName: speak-to-user-mcp
        title: SpeakSwiftlyMCP
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let store = try await ConfigStore(environment: [
        "APP_CONFIG_FILE": yamlURL.path,
        "APP_CONFIG_RELOAD_INTERVAL_SECONDS": "0.05",
    ])
    #expect(store.services.count == 1)

    let initialConfig = try store.loadAppConfig()
    #expect(initialConfig.server.name == "initial-server")
    #expect(initialConfig.server.completedJobMaxCount == 25)
}

@available(macOS 14, *)
@Test func stateCompletesQueuedSpeechJobsAndPrunesExpiredEntries() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(completedJobTTLSeconds: 0.05, jobPruneIntervalSeconds: 0.02),
        runtime: runtime,
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
@Test func hostPublishesSharedStateForUiAndServerConsumers() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-to-user-mcp",
            title: "SpeakSwiftlyMCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let updates = await host.stateUpdates()
    let jobID = try await host.submitSpeak(text: "Observe me", profileName: "default")
    var iterator = updates.makeAsyncIterator()
    let deadline = ContinuousClock.now + .seconds(1)
    var publishedState: HostStateSnapshot?
    while ContinuousClock.now < deadline {
        guard let snapshot = await iterator.next() else { break }
        if snapshot.currentGenerationJob?.jobID == jobID,
           snapshot.generationQueue.activeCount == 1
        {
            publishedState = snapshot
            break
        }
    }
    let liveState = try #require(publishedState)

    #expect(liveState.playback.state == "playing")
    #expect(liveState.transports.contains { $0.name == "http" && $0.advertisedAddress == "http://127.0.0.1:7337" })
    #expect(liveState.transports.contains { $0.name == "mcp" && $0.advertisedAddress == "http://127.0.0.1:7337/mcp" })

    let uiOverview = await MainActor.run { state.overview }
    let uiCurrentJob = await MainActor.run { state.currentGenerationJob }
    let uiPlayback = await MainActor.run { state.playback }
    #expect(uiOverview.workerReady == true)
    #expect(uiCurrentJob?.jobID == jobID)
    #expect(uiPlayback.state == "playing")

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func hostPublishesTypedEventsForServerConsumers() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-to-user-mcp",
            title: "SpeakSwiftlyMCP"
        ),
        runtime: runtime,
        state: state
    )

    let events = await host.eventUpdates()
    var iterator = events.makeAsyncIterator()

    await host.start()
    await host.markTransportStarting(name: "http")
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    let jobID = try await host.submitSpeak(text: "Observe my events", profileName: "default")

    var sawTransportChange = false
    var sawProfileCacheChange = false
    var sawJobChange = false
    var sawJobEvent = false
    var sawPlaybackChange = false

    let deadline = ContinuousClock.now + .seconds(1)
    while ContinuousClock.now < deadline {
        guard let event = await iterator.next() else { break }
        switch event {
        case .transportChanged(let snapshot):
            if snapshot.name == "http", snapshot.state == "starting" {
                sawTransportChange = true
            }
        case .profileCacheChanged(let snapshot):
            if snapshot.state == "fresh", snapshot.profileCount == 1 {
                sawProfileCacheChange = true
            }
        case .jobChanged(let snapshot):
            if snapshot.jobID == jobID {
                sawJobChange = true
            }
        case .jobEvent(let update):
            if update.jobID == jobID {
                sawJobEvent = true
            }
        case .playbackChanged(let snapshot):
            if snapshot.state == "playing" {
                sawPlaybackChange = true
            }
        case .recentErrorRecorded:
            break
        }

        if sawTransportChange, sawProfileCacheChange, sawJobChange, sawJobEvent, sawPlaybackChange {
            break
        }
    }

    #expect(sawTransportChange)
    #expect(sawProfileCacheChange)
    #expect(sawJobChange)
    #expect(sawJobEvent)
    #expect(sawPlaybackChange)

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func hostTracksTransportLifecycleBeyondStaticConfiguration() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-to-user-mcp",
            title: "SpeakSwiftlyMCP"
        ),
        runtime: runtime,
        state: state
    )

    let initial = await host.hostStateSnapshot()
    #expect(initial.transports.contains { $0.name == "http" && $0.state == "stopped" })
    #expect(initial.transports.contains { $0.name == "mcp" && $0.state == "stopped" })

    await host.markTransportStarting(name: "http")
    await host.markTransportListening(name: "mcp")

    let updated = await host.hostStateSnapshot()
    #expect(updated.transports.contains { $0.name == "http" && $0.state == "starting" })
    #expect(updated.transports.contains { $0.name == "mcp" && $0.state == "listening" })
}

@available(macOS 14, *)
@Test func hostAppliesSafeLiveConfigurationChangesAndReportsRestartRequiredOnes() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(completedJobMaxCount: 2)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-to-user-mcp",
            title: "SpeakSwiftlyMCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let first = try await host.submitSpeak(text: "One", profileName: "default")
    let second = try await host.submitSpeak(text: "Two", profileName: "default")
    _ = try await waitForJobSnapshot(first, on: host)
    _ = try await waitForJobSnapshot(second, on: host)

    await host.applyConfigurationUpdate(
        .init(
            server: .init(
                name: "reloaded-service",
                environment: "qa",
                host: configuration.host,
                port: configuration.port,
                sseHeartbeatSeconds: 0.01,
                completedJobTTLSeconds: configuration.completedJobTTLSeconds,
                completedJobMaxCount: 1,
                jobPruneIntervalSeconds: 0.01
            ),
            http: .init(
                enabled: true,
                host: "0.0.0.0",
                port: 7999,
                sseHeartbeatSeconds: 5
            ),
            mcp: .init(
                enabled: true,
                path: "/assistant/mcp",
                serverName: "new-mcp-name",
                title: "New MCP Title"
            )
        )
    )

    let hostState = await host.hostStateSnapshot()
    #expect(hostState.overview.service == "reloaded-service")
    #expect(hostState.overview.environment == "qa")
    #expect(hostState.recentErrors.contains {
        $0.source == "config" &&
            $0.code == "reload_requires_restart" &&
            $0.message.contains("app.http.port") &&
            $0.message.contains("app.mcp.path")
    })

    let snapshots = await host.jobSnapshots()
    #expect(snapshots.count == 1)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func hostRecordsRejectedConfigurationReloadsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.markConfigurationReloadRejected("Configuration value 'APP_PORT' could not be loaded: invalid integer.")

    let hostState = await host.hostStateSnapshot()
    #expect(hostState.recentErrors.contains {
        $0.source == "config" &&
            $0.code == "reload_rejected" &&
            $0.message.contains("APP_PORT")
    })
}

@available(macOS 14, *)
@Test func routesExposeHealthProfilesAndQueuedSpeechJobLifecycle() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
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

        let cloneResponse = try await client.execute(
            uri: "/profiles/clone",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"profile_name":"clone-default","reference_audio_path":"./Fixtures/reference.wav","transcript":"Cloned route test transcript."}"#
            )
        )
        let cloneJSON = try jsonObject(from: cloneResponse.body)
        let cloneJobID = try #require(cloneJSON["job_id"] as? String)
        #expect(cloneResponse.status == .accepted)
        _ = try await waitForJobSnapshot(cloneJobID, on: host)

        let cloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
        #expect(cloneInvocation.profileName == "clone-default")
        #expect(cloneInvocation.referenceAudioPath == "./Fixtures/reference.wav")
        #expect(cloneInvocation.transcript == "Cloned route test transcript.")

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Route test","profile_name":"default","cwd":"./Sources","repo_root":"../SpeakSwiftlyServer"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        let speakJobID = try #require(speakJSON["job_id"] as? String)
        #expect(speakResponse.status == .accepted)
        #expect((speakJSON["job_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["events_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["job_url"] as? String)?.hasPrefix("http://") == true)
        let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
        #expect(
            queuedSpeechInvocation.normalizationContext
                == SpeechNormalizationContext(cwd: "./Sources", repoRoot: "../SpeakSwiftlyServer")
        )

        _ = try await waitForJobSnapshot(speakJobID, on: host)

        let jobsResponse = try await client.execute(uri: "/jobs", method: .get)
        let jobsJSON = try jsonObject(from: jobsResponse.body)
        let jobs = try #require(jobsJSON["jobs"] as? [[String: Any]])
        #expect(jobsResponse.status == .ok)
        #expect(jobs.contains { $0["job_id"] as? String == speakJobID })

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

// MARK: - MCP Tests

@available(macOS 14, *)
@Test func embeddedMCPRoutesListToolsAndReadSharedHostResources() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: "mcp")

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()
    await host.markTransportListening(name: "mcp")
    let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
    let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
    try await drainMCPResponse(initializeMCPResponse)

    let initializedNotificationResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: initializeSessionID
        )
    )
    #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

    let listToolsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListToolsRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listToolsResult = try #require(mcpResultPayload(from: listToolsEnvelope))
    let tools = try #require(listToolsResult["tools"] as? [[String: Any]])
    #expect(tools.contains { $0["name"] as? String == "queue_speech_live" })
    #expect(tools.contains { $0["name"] as? String == "create_clone" })
    #expect(tools.contains { $0["name"] as? String == "status" })

    let queueSpeechToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "queue_speech_live",
                    arguments: [
                        "text": "Inspect MCP resources",
                        "profile_name": "default",
                        "cwd": "./Tests",
                        "repo_root": "../SpeakSwiftlyServer",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let queueSpeechToolPayload = try mcpToolPayload(from: queueSpeechToolEnvelope)
    let jobID = try #require(queueSpeechToolPayload["job_id"] as? String)
    #expect(queueSpeechToolPayload["status_resource_uri"] as? String == "speak://status")
    #expect(queueSpeechToolPayload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")
    let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
    #expect(
        queuedSpeechInvocation.normalizationContext
            == SpeechNormalizationContext(cwd: "./Tests", repoRoot: "../SpeakSwiftlyServer")
    )

    let createCloneToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "create_clone",
                    arguments: [
                        "profile_name": "clone-from-mcp",
                        "reference_audio_path": "./Fixtures/mcp-reference.wav",
                        "transcript": "Imported from MCP",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let createCloneToolPayload = try mcpToolPayload(from: createCloneToolEnvelope)
    let createCloneJobID = try #require(createCloneToolPayload["job_id"] as? String)
    #expect(createCloneToolPayload["job_resource_uri"] as? String == "speak://jobs/\(createCloneJobID)")
    let createCloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
    #expect(createCloneInvocation.profileName == "clone-from-mcp")
    #expect(createCloneInvocation.referenceAudioPath == "./Fixtures/mcp-reference.wav")
    #expect(createCloneInvocation.transcript == "Imported from MCP")

    let listResourcesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListResourcesRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listResourcesResult = try #require(mcpResultPayload(from: listResourcesEnvelope))
    let resources = try #require(listResourcesResult["resources"] as? [[String: Any]])
    #expect(resources.contains { $0["uri"] as? String == "speak://status" })
    #expect(resources.contains { $0["uri"] as? String == "speak://jobs" })
    #expect(resources.contains { $0["uri"] as? String == "speak://runtime" })

    let listResourceTemplatesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListResourceTemplatesRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listResourceTemplatesResult = try #require(mcpResultPayload(from: listResourceTemplatesEnvelope))
    let templates = try #require(listResourceTemplatesResult["resourceTemplates"] as? [[String: Any]])
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://profiles/{profile_name}/detail" })
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://jobs/{job_id}" })

    let listPromptsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListPromptsRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listPromptsResult = try #require(mcpResultPayload(from: listPromptsEnvelope))
    let prompts = try #require(listPromptsResult["prompts"] as? [[String: Any]])
    #expect(prompts.contains { $0["name"] as? String == "draft_profile_voice_description" })
    #expect(prompts.contains { $0["name"] as? String == "draft_queue_playback_notice" })

    let getPromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "draft_profile_voice_description",
                    arguments: [
                        "profile_goal": "gentle narration",
                        "voice_traits": "warm, steady, intimate",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let getPromptResult = try #require(mcpResultPayload(from: getPromptEnvelope))
    let promptMessages = try #require(getPromptResult["messages"] as? [[String: Any]])
    let firstPromptMessage = try #require(promptMessages.first)
    let promptContent = try #require(firstPromptMessage["content"] as? [String: Any])
    #expect((promptContent["text"] as? String)?.contains("gentle narration") == true)

    let statusToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpStatusToolRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let statusToolPayload = try mcpToolPayload(from: statusToolEnvelope)
    #expect(statusToolPayload["worker_mode"] as? String == "ready")
    let transports = try #require(statusToolPayload["transports"] as? [[String: Any]])
    #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })

    let runtimeResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://runtime"),
                sessionID: initializeSessionID
            )
        )
    )
    let runtimeResourceResult = try #require(mcpResultPayload(from: runtimeResourceEnvelope))
    let contents = try #require(runtimeResourceResult["contents"] as? [[String: Any]])
    let firstContent = try #require(contents.first)
    let runtimeText = try #require(firstContent["text"] as? String)
    let runtimePayload = try jsonObject(from: Data(runtimeText.utf8))
    let runtimeTransports = try #require(runtimePayload["transports"] as? [[String: Any]])
    #expect(runtimeTransports.contains { $0["name"] as? String == "mcp" && $0["advertised_address"] as? String == "http://127.0.0.1:7337/mcp" })

    let jobsResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://jobs"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobsResourceResult = try #require(mcpResultPayload(from: jobsResourceEnvelope))
    let jobsContents = try #require(jobsResourceResult["contents"] as? [[String: Any]])
    let jobsText = try #require(jobsContents.first?["text"] as? String)
    let jobsPayload = try #require(try JSONSerialization.jsonObject(with: Data(jobsText.utf8)) as? [[String: Any]])
    #expect(jobsPayload.contains { $0["job_id"] as? String == jobID })

    let profileDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://profiles/default/detail"),
                sessionID: initializeSessionID
            )
        )
    )
    let profileDetailResult = try #require(mcpResultPayload(from: profileDetailEnvelope))
    let profileDetailContents = try #require(profileDetailResult["contents"] as? [[String: Any]])
    let profileDetailText = try #require(profileDetailContents.first?["text"] as? String)
    let profileDetailPayload = try jsonObject(from: Data(profileDetailText.utf8))
    #expect(profileDetailPayload["profile_name"] as? String == "default")

    let jobDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://jobs/\(jobID)"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobDetailResult = try #require(mcpResultPayload(from: jobDetailEnvelope))
    let jobDetailContents = try #require(jobDetailResult["contents"] as? [[String: Any]])
    let jobDetailText = try #require(jobDetailContents.first?["text"] as? String)
    let jobDetailPayload = try jsonObject(from: Data(jobDetailText.utf8))
    #expect(jobDetailPayload["job_id"] as? String == jobID)

    let smokeSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp-smoke",
                title: "SpeakSwiftly Test MCP Smoke"
            ),
            host: host
        )
    )
    let smokeApp = assembleHBApp(
        configuration: testHTTPConfig(configuration),
        host: host,
        mcpSurface: smokeSurface
    )
    try await smokeSurface.start()
    try await smokeApp.test(.router) { client in
        let initializeResponse = try await client.execute(
            uri: "/mcp",
            method: .post,
            headers: [
                .contentType: "application/json",
                .accept: "application/json, text/event-stream",
            ],
            body: byteBuffer(mcpInitializeRequestJSON(id: "initialize-smoke"))
        )
        #expect(initializeResponse.status == .ok)
        #expect(mcpSessionID(from: initializeResponse)?.isEmpty == false)
    }
    await smokeSurface.stop()

    await runtime.finishHeldSpeak(id: jobID)
    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedMCPResourceSubscriptionsEmitUpdatedNotifications() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: "mcp")

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()
    await host.markTransportListening(name: "mcp")

    let initializeResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
    let sessionID = try #require(mcpSessionID(from: initializeResponse))
    try await drainMCPResponse(initializeResponse)

    let initializedNotificationResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: sessionID
        )
    )
    #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

    let streamResponse = await mcpSurface.handle(mcpGETRequest(sessionID: sessionID))
    guard case .stream(let stream, _) = streamResponse else {
        Issue.record("Expected the embedded MCP GET transport to return a standalone streaming response.")
        await mcpSurface.stop()
        await host.shutdown()
        return
    }
    var streamIterator = stream.makeAsyncIterator()
    _ = try await nextMCPStreamEnvelope(from: &streamIterator)

    let subscribeEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpSubscribeResourceRequestJSON(uri: "speak://runtime"),
                sessionID: sessionID
            )
        )
    )
    #expect(subscribeEnvelope["result"] != nil)

    await host.markTransportFailed(
        name: "http",
        message: "SpeakSwiftlyServer test transport failure for MCP resource subscription coverage."
    )

    let updatedNotification = try await nextMCPStreamEnvelope(from: &streamIterator)
    #expect(updatedNotification["method"] as? String == "notifications/resources/updated")
    let notificationParams = try #require(updatedNotification["params"] as? [String: Any])
    #expect(notificationParams["uri"] as? String == "speak://runtime")

    await mcpSurface.stop()
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
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
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
            #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
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
            #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
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
        state: state
    )

    await host.start()

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
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
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelFailed)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
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

private func testHTTPConfig(_ configuration: ServerConfiguration) -> HTTPConfig {
    .init(
        enabled: true,
        host: configuration.host,
        port: configuration.port,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds
    )
}

private func sampleProfile() -> SpeakSwiftly.ProfileSummary {
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
    return try jsonObject(from: data)
}

private func jsonObject(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = json as? [String: Any] else {
        throw JSONError.notDictionary
    }
    return dictionary
}

private func mcpSessionID(from response: TestResponse) -> String? {
    guard let headerName = HTTPField.Name("Mcp-Session-Id") else {
        return nil
    }
    return response.headers[headerName]
}

private func mcpHeaders(sessionID: String) -> HTTPFields {
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    headers[.accept] = "application/json, text/event-stream"
    if let sessionHeader = HTTPField.Name("Mcp-Session-Id") {
        headers[sessionHeader] = sessionID
    }
    return headers
}

private func mcpEnvelope(from buffer: ByteBuffer) throws -> [String: Any] {
    try mcpEnvelope(from: Data(buffer.readableBytesView))
}

private func mcpEnvelope(from response: MCP.HTTPResponse) async throws -> [String: Any] {
    switch response {
    case .stream(let stream, _):
        var data = Data()
        for try await chunk in stream {
            data.append(chunk)
        }
        guard data.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP surface returned an empty streaming body for a JSON-RPC request.")
        }
        return try mcpEnvelope(from: data)

    case .data(let data, _):
        guard data.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP surface returned an empty data body for a JSON-RPC request.")
        }
        return try mcpEnvelope(from: data)

    case .error:
        let data = response.bodyData ?? Data()
        guard data.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP surface returned an empty error body for a JSON-RPC request.")
        }
        return try mcpEnvelope(from: data)

    case .accepted, .ok:
        throw JSONError.emptyBody("The embedded MCP surface returned status \(response.statusCode) without a JSON body.")
    }
}

private func drainMCPResponse(_ response: MCP.HTTPResponse) async throws {
    switch response {
    case .stream(let stream, _):
        for try await _ in stream {}
    case .data, .accepted, .ok, .error:
        return
    }
}

private func mcpEnvelope(from data: Data) throws -> [String: Any] {
    let body = String(decoding: data, as: UTF8.self)
    if let dataLine = body
        .split(separator: "\n")
        .reversed()
        .first(where: {
            $0.hasPrefix("data: ")
                && $0.dropFirst("data: ".count).isEmpty == false
        })
    {
        let payload = dataLine.dropFirst("data: ".count)
        guard payload.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP response contained an empty data: payload. Raw body: \(body)")
        }
        return try jsonObject(from: Data(payload.utf8))
    }
    return try jsonObject(from: data)
}

private func mcpToolPayload(from envelope: [String: Any]) throws -> [String: Any] {
    let result = try #require(mcpResultPayload(from: envelope))
    let content = try #require(result["content"] as? [[String: Any]])
    let text = try #require(content.first?["text"] as? String)
    return try jsonObject(from: Data(text.utf8))
}

private func mcpResultPayload(from envelope: [String: Any]) -> [String: Any]? {
    (envelope["result"] as? [String: Any]) ?? envelope
}

private func mcpPOSTRequest(body: String, sessionID: String? = nil) -> MCP.HTTPRequest {
    var headers = [
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    ]
    if let sessionID {
        headers["Mcp-Session-Id"] = sessionID
    }
    return MCP.HTTPRequest(
        method: "POST",
        headers: headers,
        body: Data(body.utf8),
        path: "/mcp"
    )
}

private func mcpGETRequest(sessionID: String) -> MCP.HTTPRequest {
    MCP.HTTPRequest(
        method: "GET",
        headers: [
            "Accept": "application/json, text/event-stream",
            "Mcp-Session-Id": sessionID,
        ],
        body: nil,
        path: "/mcp"
    )
}

// MARK: - MCP Test Helpers

private func mcpSessionID(from response: MCP.HTTPResponse) -> String? {
    response.headers.first { $0.key.caseInsensitiveCompare("Mcp-Session-Id") == .orderedSame }?.value
}

private func mcpStatusCode(from response: MCP.HTTPResponse) -> Int {
    response.statusCode
}

private func mcpInitializeRequestJSON(id: String = "initialize-1") -> String {
    #"{"jsonrpc":"2.0","id":"\#(id)","method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"SpeakSwiftlyServerTests","version":"1.0"}}}"#
}

private func mcpInitializedNotificationJSON() -> String {
    #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
}

private func mcpListToolsRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"tools-1","method":"tools/list","params":{}}"#
}

private func mcpListResourcesRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"resources-1","method":"resources/list","params":{}}"#
}

private func mcpListResourceTemplatesRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"resource-templates-1","method":"resources/templates/list","params":{}}"#
}

private func mcpListPromptsRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"prompts-1","method":"prompts/list","params":{}}"#
}

private func mcpStatusToolRequestJSON() -> String {
    mcpCallToolRequestJSON(name: "status", arguments: [:], id: "status-1")
}

private func mcpCallToolRequestJSON(
    name: String,
    arguments: [String: String],
    id: String = "tool-1"
) -> String {
    let sortedArguments = arguments
        .sorted { $0.key < $1.key }
        .map { key, value in #""\#(key)":"\#(value)""# }
        .joined(separator: ",")
    return #"{"jsonrpc":"2.0","id":"\#(id)","method":"tools/call","params":{"name":"\#(name)","arguments":{\#(sortedArguments)}}}"#
}

private func mcpReadResourceRequestJSON(uri: String) -> String {
    #"{"jsonrpc":"2.0","id":"read-resource-1","method":"resources/read","params":{"uri":"\#(uri)"}}"#
}

private func mcpGetPromptRequestJSON(name: String, arguments: [String: String]) -> String {
    let sortedArguments = arguments
        .sorted { $0.key < $1.key }
        .map { key, value in #""\#(key)":"\#(value)""# }
        .joined(separator: ",")
    return #"{"jsonrpc":"2.0","id":"get-prompt-1","method":"prompts/get","params":{"name":"\#(name)","arguments":{\#(sortedArguments)}}}"#
}

private func mcpSubscribeResourceRequestJSON(uri: String) -> String {
    #"{"jsonrpc":"2.0","id":"subscribe-resource-1","method":"resources/subscribe","params":{"uri":"\#(uri)"}}"#
}

private func nextMCPStreamEnvelope(
    from iterator: inout AsyncThrowingStream<Data, Error>.AsyncIterator
) async throws -> [String: Any] {
    while let chunk = try await iterator.next() {
        let body = String(decoding: chunk, as: UTF8.self)
        if let dataLine = body
            .split(separator: "\n")
            .reversed()
            .first(where: { $0.hasPrefix("data: ") })
        {
            let payload = dataLine.dropFirst("data: ".count)
            if payload.isEmpty {
                return [:]
            }
            return try jsonObject(from: Data(payload.utf8))
        }
    }

    throw JSONError.emptyBody("The embedded MCP standalone stream ended before it delivered a JSON payload.")
}

private enum JSONError: Error {
    case notDictionary
    case emptyBody(String)
}
