import Foundation
import Logging
import ServiceLifecycle
import Testing
@testable import SpeakSwiftlyServer

// MARK: - Host Lifecycle Tests

@available(macOS 14, *)
@Test func embeddedServerSessionPublishesObservableStateForAppConsumers() async throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let session = try await EmbeddedServerSession.start(
        environment: ["APP_ENV": "test"],
        options: .init(port: 7811, runtimeProfileRootURL: runtimeProfileRootURL)
    ) { environment, state in
        #expect(environment["APP_ENV"] == "test")
        #expect(environment["APP_PORT"] == "7811")
        #expect(environment["APP_HTTP_PORT"] == "7811")
        #expect(environment["SPEAKSWIFTLY_PROFILE_ROOT"] == runtimeProfileRootURL.standardizedFileURL.path)
        #expect(environment[AppRuntimeDefaultProfile.environmentKey] == AppRuntimeDefaultProfile.embeddedSession.rawValue)

        await MainActor.run {
            state.overview = HostOverviewSnapshot(
                service: "speak-swiftly-server-tests",
                environment: "test",
                defaultVoiceProfileName: "default-femme",
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
            state.voiceProfiles = [
                .init(
                    profileName: "default-femme",
                    vibe: "femme",
                    createdAt: "2026-04-07T12:00:00Z",
                    voiceDescription: "Warm and steady.",
                    sourceText: "Reference text."
                ),
            ]
            state.playback = PlaybackStatusSnapshot(
                state: "playing",
                activeRequest: .init(id: "req-1", op: "speak", profileName: "default"),
                isStableForConcurrentGeneration: true,
                isRebuffering: false,
                stableBufferedAudioMS: 320,
                stableBufferTargetMS: 400
            )
            state.currentGenerationJobs = [
                CurrentGenerationJobSnapshot(
                    jobID: "job-1",
                    op: "speak",
                    profileName: "default",
                    submittedAt: "2026-04-07T12:00:00Z",
                    startedAt: "2026-04-07T12:00:01Z",
                    latestStage: "speaking",
                    elapsedGenerationSeconds: 0.25
                ),
            ]
            state.transports = [
                .init(
                    name: "http",
                    enabled: true,
                    state: "listening",
                    host: "127.0.0.1",
                    port: 7811,
                    path: nil,
                    advertisedAddress: "http://127.0.0.1:7811"
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
    let currentGenerationJobs = await MainActor.run { state.currentGenerationJobs }
    let playback = await MainActor.run { state.playback }
    let voiceProfiles = await MainActor.run { state.voiceProfiles }
    let transports = await MainActor.run { state.transports }

    #expect(overview.workerReady == true)
    #expect(overview.profileCount == 1)
    #expect(overview.defaultVoiceProfileName == "default-femme")
    #expect(currentGenerationJobs.contains { $0.jobID == "job-1" })
    #expect(playback.state == "playing")
    #expect(voiceProfiles.contains { $0.profileName == "default-femme" })
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
@Test func hostLifecycleServiceWaitsForSiblingShutdownBeforeStoppingRuntime() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        httpConfig: testHTTPConfig(testConfiguration()),
        mcpConfig: .init(
            enabled: false,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly"
        ),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state
    )
    let readinessGate = EmbeddedLifecycleReadinessGate()
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = HostLifecycleService(
        host: host,
        readinessGate: readinessGate,
        shutdownBarrier: shutdownBarrier
    )
    let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HostLifecycle")
    )

    let runTask = Task {
        try await serviceGroup.run()
    }

    try await readinessGate.waitUntilReady()
    let startedCounts = await runtime.lifecycleCounts()
    #expect(startedCounts.start == 1)
    #expect(startedCounts.shutdown == 0)

    await serviceGroup.triggerGracefulShutdown()
    try? await Task.sleep(for: .milliseconds(50))

    let countsBeforeBarrier = await runtime.lifecycleCounts()
    #expect(countsBeforeBarrier.shutdown == 0)

    await shutdownBarrier.markCompleted()
    try await runTask.value

    let finalCounts = await runtime.lifecycleCounts()
    #expect(finalCounts.shutdown == 1)
}

@available(macOS 14, *)
@Test func hostStartWaitsForRuntimeStartToFinish() async throws {
    actor StartCompletionProbe {
        private(set) var didFinish = false

        func markFinished() {
            didFinish = true
        }
    }

    let runtime = MockRuntime(startBehavior: .waitForRelease)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state
    )
    let probe = StartCompletionProbe()

    let startTask = Task {
        await host.start()
        await probe.markFinished()
    }

    await runtime.waitUntilStartReachesBarrier()
    #expect(await probe.didFinish == false)

    let countsWhileBlocked = await runtime.lifecycleCounts()
    #expect(countsWhileBlocked.start == 1)

    await runtime.allowStartToFinish()
    await startTask.value

    let finalCounts = await runtime.lifecycleCounts()
    #expect(finalCounts.start == 1)
}

@available(macOS 14, *)
@Test func hostShutdownCancelsTrackedRequestMonitorTasks() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    _ = try await host.submitSpeak(text: "Keep this request open until shutdown", profileName: "default")
    #expect(await host.requestMonitorTaskCount() == 1)

    await host.shutdown()

    let lifecycleCounts = await runtime.lifecycleCounts()
    #expect(lifecycleCounts.shutdown == 1)
    #expect(await host.requestMonitorTaskCount() == 0)
}

@available(macOS 14, *)
@Test func hostPruneServiceCancelsOnGracefulShutdownAndMarksShutdownBarrier() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(jobPruneIntervalSeconds: 60)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state
    )
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = HostPruneService(
        host: host,
        shutdownBarrier: shutdownBarrier
    )
    let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HostPrune")
    )

    let runTask = Task {
        try await serviceGroup.run()
    }

    try? await Task.sleep(for: .milliseconds(10))
    await serviceGroup.triggerGracefulShutdown()
    try await runTask.value
    await shutdownBarrier.waitUntilCompleted()
}

@available(macOS 14, *)
@Test func embeddedApplicationServiceMarksShutdownBarrierWhenWrappedServiceFails() async throws {
    struct FailingService: Service {
        struct ExpectedFailure: Error {}

        func run() async throws {
            throw ExpectedFailure()
        }
    }

    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = EmbeddedApplicationService(
        application: FailingService(),
        shutdownBarrier: shutdownBarrier
    )

    await #expect(throws: FailingService.ExpectedFailure.self) {
        try await service.run()
    }

    await shutdownBarrier.waitUntilCompleted()
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
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
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
        case .textProfilesChanged, .runtimeConfigurationChanged, .recentErrorRecorded:
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
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
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
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
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
                defaultVoiceProfileName: "default-femme",
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
    #expect(hostState.overview.defaultVoiceProfileName == "default-femme")
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
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
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
@Test func appManagedDefaultVoiceProfileOverrideSurvivesConfigurationReload() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(defaultVoiceProfileName: "configured-default")
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    _ = try await host.setDefaultVoiceProfileName("app-selected-default")
    #expect(await host.defaultVoiceProfileName() == "app-selected-default")

    await host.applyConfigurationUpdate(
        .init(
            server: .init(
                name: configuration.name,
                environment: configuration.environment,
                defaultVoiceProfileName: "reloaded-config-default",
                host: configuration.host,
                port: configuration.port,
                sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
                completedJobTTLSeconds: configuration.completedJobTTLSeconds,
                completedJobMaxCount: configuration.completedJobMaxCount,
                jobPruneIntervalSeconds: configuration.jobPruneIntervalSeconds
            ),
            http: testHTTPConfig(configuration),
            mcp: .init(enabled: false, path: "/mcp", serverName: "speak-swiftly-mcp", title: "SpeakSwiftly")
        )
    )

    #expect(await host.defaultVoiceProfileName() == "app-selected-default")
    let hostState = await host.hostStateSnapshot()
    #expect(hostState.overview.defaultVoiceProfileName == "app-selected-default")

    await host.shutdown()
}
