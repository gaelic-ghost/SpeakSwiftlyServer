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

// MARK: - Configuration and Host State Tests

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
        serverName: speak-swiftly-mcp
        title: SpeakSwiftly
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

@Test func hostReportsAndPersistsRuntimeConfigurationState() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: configurationStore,
        state: state
    )

    let initialSnapshot = await host.runtimeConfigurationSnapshot()
    #expect(initialSnapshot.activeRuntimeSpeechBackend == "qwen3")
    #expect(initialSnapshot.nextRuntimeSpeechBackend == "qwen3")
    #expect(initialSnapshot.persistedConfigurationExists == false)
    #expect(initialSnapshot.persistedConfigurationState == "missing")
    #expect(initialSnapshot.persistedConfigurationWillAffectNextRuntimeStart == true)

    let updatedSnapshot = try await host.saveRuntimeConfiguration(speechBackend: .marvis)
    #expect(updatedSnapshot.activeRuntimeSpeechBackend == "qwen3")
    #expect(updatedSnapshot.nextRuntimeSpeechBackend == "marvis")
    #expect(updatedSnapshot.persistedSpeechBackend == "marvis")
    #expect(updatedSnapshot.persistedConfigurationExists == true)
    #expect(updatedSnapshot.persistedConfigurationState == "loaded")
    #expect(updatedSnapshot.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == updatedSnapshot)

    let hostStateSnapshot = await host.hostStateSnapshot()
    #expect(hostStateSnapshot.runtimeConfiguration == updatedSnapshot)
}

@Test func hostReportsLiveBackendSwitchWithoutMutatingNextStartupConfiguration() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: configurationStore,
        state: state
    )

    let response = try await host.switchSpeechBackend(to: .marvis)
    #expect(response.speechBackend == "marvis")

    let runtimeConfiguration = await host.runtimeConfigurationSnapshot()
    #expect(runtimeConfiguration.activeRuntimeSpeechBackend == "marvis")
    #expect(runtimeConfiguration.nextRuntimeSpeechBackend == "qwen3")
    #expect(runtimeConfiguration.persistedSpeechBackend == nil)
    #expect(runtimeConfiguration.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == runtimeConfiguration)
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
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
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

    let runtimeRefresh = try #require(liveState.runtimeRefresh)
    #expect(liveState.playback.state == "playing")
    #expect(runtimeRefresh.sequenceID > 0)
    #expect(runtimeRefresh.source == "fallback")
    #expect(runtimeRefresh.startedAt.isEmpty == false)
    #expect(runtimeRefresh.completedAt.isEmpty == false)
    #expect(liveState.transports.contains { $0.name == "http" && $0.advertisedAddress == "http://127.0.0.1:7337" })
    #expect(liveState.transports.contains { $0.name == "mcp" && $0.advertisedAddress == "http://127.0.0.1:7337/mcp" })

    let uiOverview = await MainActor.run { state.overview }
    let uiRuntimeRefresh = await MainActor.run { state.runtimeRefresh }
    let uiCurrentJob = await MainActor.run { state.currentGenerationJob }
    let uiPlayback = await MainActor.run { state.playback }
    #expect(uiOverview.workerReady == true)
    #expect(uiRuntimeRefresh == runtimeRefresh)
    #expect(uiCurrentJob?.jobID == jobID)
    #expect(uiPlayback.state == "playing")

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func hostUsesFallbackRuntimeSnapshotsForQueuedLiveSpeechJobs() async throws {
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
    try await Task.sleep(for: .milliseconds(50))

    let baselineRefreshCounts = await runtime.runtimeRefreshActionCounts()

    let firstJobID = try await host.submitSpeak(text: "Keep talking", profileName: "default")
    let secondJobID = try await host.submitSpeak(text: "Wait your turn", profileName: "default")

    let snapshot: HostStateSnapshot = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10)
    ) {
        let snapshot = await host.hostStateSnapshot()
        guard
            snapshot.runtimeRefresh?.source == "fallback",
            snapshot.playback.activeRequest?.id == firstJobID,
            snapshot.playbackQueue.activeRequest?.id == firstJobID,
            snapshot.generationQueue.queuedCount == 1
        else {
            return nil
        }

        return snapshot
    }

    let countsAfterQueuedLiveRequests = await runtime.runtimeRefreshActionCounts()
    #expect(countsAfterQueuedLiveRequests == baselineRefreshCounts)
    #expect(snapshot.currentGenerationJob?.jobID == firstJobID)

    let secondJobSnapshot = try await host.jobSnapshot(id: secondJobID)
    #expect(secondJobSnapshot.history.contains {
        guard case .queued(let event) = $0 else { return false }
        return event.reason == "waiting_for_active_request"
    })

    await runtime.finishHeldSpeak(id: firstJobID)
    await runtime.finishHeldSpeak(id: secondJobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func hostDoesNotRefreshRuntimeSnapshotsForHeldLiveProgressEvents() async throws {
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

    let jobID = try await host.submitSpeak(text: "Hold steady", profileName: "default")
    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10)
    ) {
        let snapshot = try await host.jobSnapshot(id: jobID)
        return snapshot.history.count >= 2 ? snapshot : nil
    }

    try await Task.sleep(for: .milliseconds(50))
    let baselineRefreshCounts = await runtime.runtimeRefreshActionCounts()

    await runtime.publishHeldSpeakProgress(id: jobID, stage: .bufferingAudio)

    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10)
    ) {
        let snapshot = try await host.jobSnapshot(id: jobID)
        return snapshot.history.contains {
            guard case .progress(let event) = $0 else { return false }
            return event.stage == "buffering_audio"
        } ? snapshot : nil
    }

    try await Task.sleep(for: .milliseconds(50))
    let countsAfterProgress = await runtime.runtimeRefreshActionCounts()
    #expect(countsAfterProgress == baselineRefreshCounts)

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedServerSessionPublishesObservableStateForAppConsumers() async throws {
    let session = try await EmbeddedServerSession.start(environment: ["APP_ENV": "test"]) { environment, state in
        #expect(environment["APP_ENV"] == "test")

        await MainActor.run {
            state.overview = HostOverviewSnapshot(
                service: "speak-swiftly-server-tests",
                environment: "test",
                serverMode: "ready",
                workerMode: "resident",
                workerStage: "resident_model_ready",
                workerReady: true,
                startupError: nil,
                profileCacheState: "fresh",
                profileCacheWarning: nil,
                profileCount: 1,
                lastProfileRefreshAt: "2026-04-07T12:00:00Z"
            )
            state.playback = PlaybackStatusSnapshot(
                state: "playing",
                activeRequest: .init(id: "req-1", op: "speak", profileName: "default")
            )
            state.currentGenerationJob = CurrentGenerationJobSnapshot(
                jobID: "job-1",
                op: "speak",
                profileName: "default",
                submittedAt: "2026-04-07T12:00:00Z",
                startedAt: "2026-04-07T12:00:01Z",
                latestStage: "speaking",
                elapsedGenerationSeconds: 0.25
            )
            state.transports = [
                .init(
                    name: "http",
                    enabled: true,
                    state: "listening",
                    host: "127.0.0.1",
                    port: 7337,
                    path: nil,
                    advertisedAddress: "http://127.0.0.1:7337"
                ),
            ]
        }

        return .init(
            requestStop: {},
            waitUntilStopped: {}
        )
    }

    let state = await MainActor.run { session.state }
    let overview = await MainActor.run { state.overview }
    let currentGenerationJob = await MainActor.run { state.currentGenerationJob }
    let playback = await MainActor.run { state.playback }
    let transports = await MainActor.run { state.transports }

    #expect(overview.workerReady == true)
    #expect(overview.profileCount == 1)
    #expect(currentGenerationJob?.jobID == "job-1")
    #expect(playback.state == "playing")
    #expect(transports.contains { $0.name == "http" && $0.state == "listening" })

    try await session.stop()
}

@available(macOS 14, *)
@Test func embeddedServerSessionRequestsGracefulStopOnlyOnce() async throws {
    let probe = EmbeddedSessionLifecycleProbe()
    let session = try await EmbeddedServerSession.start(environment: [:]) { _, _ in
        .init(
            requestStop: {
                await probe.recordRequestStop()
            },
            waitUntilStopped: {
                await probe.recordWaitUntilStopped()
            }
        )
    }

    try await session.stop()
    try await session.stop()

    let counts = await probe.counts()
    #expect(counts.requestStop == 1)
    #expect(counts.waitUntilStopped == 2)
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
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
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
        case .textProfilesChanged:
            break
        case .runtimeConfigurationChanged:
            break
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
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
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
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
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
