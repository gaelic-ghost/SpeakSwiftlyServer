import Foundation
import Logging
import ServiceLifecycle
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
@testable import SSSHTTP
@testable import SSSMCP
import Testing

// MARK: - Host Lifecycle Tests

@available(macOS 14, *)
@Test func `embedded server publishes observable state for app consumers`() async throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let server = await MainActor.run {
        EmbeddedServer(options: .init(port: 7811, runtimeProfileRootURL: runtimeProfileRootURL))
    }
    try await server.liftoff(
        environment: ["APP_ENV": "test"],
        defaultProfile: .embeddedSession,
        bootstrap: { environment, server in
            #expect(environment["APP_ENV"] == "test")
            #expect(environment["APP_PORT"] == "7811")
            #expect(environment["APP_HTTP_PORT"] == "7811")
            #expect(environment["SPEAKSWIFTLY_PROFILE_ROOT"] == nil)
            #expect(environment[ServerConfigDefaultProfile.environmentKey] == ServerConfigDefaultProfile.embeddedSession.rawValue)

            await MainActor.run {
                server.overview = HostOverviewSnapshot(
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
                    lastProfileRefreshAt: "2026-04-07T12:00:00Z",
                )
                server.voiceProfiles = [
                    .init(
                        profileName: "default-femme",
                        vibe: "femme",
                        createdAt: "2026-04-07T12:00:00Z",
                        voiceDescription: "Warm and steady.",
                        sourceText: "Reference text.",
                    ),
                ]
                server.playback = PlaybackStatusSnapshot(
                    state: "playing",
                    activeRequest: .init(id: "req-1", op: "speak", profileName: "default"),
                    isStableForConcurrentGeneration: true,
                    isRebuffering: false,
                    stableBufferedAudioMS: 320,
                    stableBufferTargetMS: 400,
                )
                server.currentGenerationJobs = [
                    CurrentGenerationJobSnapshot(
                        jobID: "job-1",
                        op: "speak",
                        profileName: "default",
                        submittedAt: "2026-04-07T12:00:00Z",
                        startedAt: "2026-04-07T12:00:01Z",
                        latestStage: "speaking",
                        elapsedGenerationSeconds: 0.25,
                    ),
                ]
                server.transports = [
                    .init(
                        name: "http",
                        enabled: true,
                        state: "listening",
                        host: "127.0.0.1",
                        port: 7811,
                        path: nil,
                        advertisedAddress: "http://127.0.0.1:7811",
                    ),
                ]
            }

            return .init(
                requestStop: {},
                waitUntilStopped: {},
            )
        },
    )

    let overview = await MainActor.run { server.overview }
    let currentGenerationJobs = await MainActor.run { server.currentGenerationJobs }
    let playback = await MainActor.run { server.playback }
    let voiceProfiles = await MainActor.run { server.voiceProfiles }
    let transports = await MainActor.run { server.transports }

    #expect(overview.workerReady == true)
    #expect(overview.profileCount == 1)
    #expect(overview.defaultVoiceProfileName == "default-femme")
    #expect(currentGenerationJobs.contains { $0.jobID == "job-1" })
    #expect(playback.state == "playing")
    #expect(voiceProfiles.contains { $0.profileName == "default-femme" })
    #expect(transports.contains { $0.name == "http" && $0.state == "listening" })

    try await server.land()
}

@available(macOS 14, *)
@Test func `embedded server requests graceful stop only once`() async throws {
    let probe = EmbeddedSessionLifecycleProbe()
    let server = await MainActor.run { EmbeddedServer() }
    try await server.liftoff(
        environment: [:],
        defaultProfile: .embeddedSession,
        bootstrap: { _, _ in
            EmbeddedServerLifecycleHooks(
                requestStop: {
                    await probe.recordRequestStop()
                },
                waitUntilStopped: {
                    await probe.recordWaitUntilStopped()
                },
            )
        },
    )

    try await server.land()
    try await server.land()

    let counts = await probe.counts()
    #expect(counts.requestStop == 1)
    #expect(counts.waitUntilStopped == 1)
}

@available(macOS 14, *)
@Test func `network audio receiver accepts loopback stream and updates transport status`() async throws {
    actor ReceivedChunkProbe: ReceivedNetworkAudioChunkSnapshotting {
        private var chunks = [SpeakSwiftly.GeneratedAudioChunk]()

        func append(_ chunk: SpeakSwiftly.GeneratedAudioChunk) {
            chunks.append(chunk)
        }

        func snapshot() -> [SpeakSwiftly.GeneratedAudioChunk] {
            chunks
        }
    }

    let configuration = testConfiguration()
    let receiverConfig = NetworkAudioReceiverConfig(
        enabled: true,
        serviceName: "SpeakSwiftly Server Test Receiver",
        port: 0,
        sharedToken: "test-token",
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(enabled: false, path: "/mcp", serverName: "test-mcp", title: "Test MCP"),
        networkAudioReceiverConfig: receiverConfig,
        runtime: MockRuntime(),
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let probe = ReceivedChunkProbe()
    let service = NetworkAudioReceiverLifecycleService(
        host: host,
        config: receiverConfig,
        shutdownBarrier: shutdownBarrier,
        playbackSink: { inboundStream in
            for try await chunk in inboundStream.chunks {
                await probe.append(chunk)
            }
        },
    )
    let serviceGroup = ServiceGroup(
        configuration: .init(
            services: [
                .init(service: service),
            ],
            logger: Logger(label: "SpeakSwiftlyServerTests.NetworkAudioReceiver"),
        ),
    )
    let runTask = Task<Void, Error> {
        try await serviceGroup.run()
    }

    let port = try await waitForNetworkAudioReceiverPort(on: host)
    #expect(port > 0)

    let chunks = AsyncThrowingStream<SpeakSwiftly.GeneratedAudioChunk, any Error> { continuation in
        continuation.yield(
            .init(
                requestID: "lan-loopback",
                sequenceNumber: 0,
                sampleRate: 24000,
                channelCount: 1,
                samples: [0.1, 0.2, 0.3],
            ),
        )
        continuation.yield(
            .init(
                requestID: "lan-loopback",
                sequenceNumber: 1,
                sampleRate: 24000,
                channelCount: 1,
                samples: [],
                isFinal: true,
            ),
        )
        continuation.finish()
    }
    let sender = SpeakSwiftly.NetworkAudioStreamSender(
        endpoint: .init(host: "127.0.0.1", port: UInt16(port)),
        handshake: .init(
            requestID: "lan-loopback",
            senderName: "server-test",
            sharedToken: "test-token",
        ),
        connectionReadinessTimeout: .seconds(2),
    )

    try await sender.send(chunks: chunks)
    let receivedChunks = try await waitForReceivedNetworkAudioChunks(probe)
    #expect(receivedChunks.map(\.sequenceNumber) == [0, 1])
    #expect(receivedChunks.last?.isFinal == true)

    let activeSnapshot = await host.hostStateSnapshot()
    #expect(
        activeSnapshot.transports.contains {
            $0.name == NetworkAudioReceiverConfig.transportName &&
                ($0.state == "listening" || $0.state == "active") &&
                $0.activeStreamCount != nil
        },
    )

    await serviceGroup.triggerGracefulShutdown()
    _ = try await runTask.value
}

@available(macOS 14, *)
@Test func `embedded HTTP listeners bind localhost and LAN independently`() async throws {
    let configuration = testConfiguration()
    let localhostHTTPConfig = HTTPConfig(
        enabled: true,
        host: "127.0.0.1",
        port: 0,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
    )
    let lanListenerConfig = LANHTTPListenerConfig(
        enabled: true,
        host: "127.0.0.1",
        port: 0,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
        advertiseBonjour: true,
        serviceName: "SpeakSwiftly Server Test LAN",
    )
    let listenersConfig = HTTPListenersConfig(
        localhost: localhostHTTPConfig,
        lan: lanListenerConfig,
    )
    let runtime = MockRuntime(profiles: [sampleProfile()] + sampleSystemProfiles())
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: localhostHTTPConfig,
        listenersConfig: listenersConfig,
        mcpConfig: .init(enabled: false, path: "/mcp", serverName: "test-mcp", title: "Test MCP"),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let bonjourPublisher = HTTPListenerBonjourPublisher(serviceName: lanListenerConfig.serviceName)
    let localhostApp = assembleHBApp(
        configuration: localhostHTTPConfig,
        host: host,
        transportName: HTTPListenersConfig.localhostTransportName,
        additionalListeningTransports: ["http"],
    )
    let lanApp = assembleHBApp(
        configuration: lanListenerConfig.http,
        host: host,
        transportName: HTTPListenersConfig.lanTransportName,
        onServerRunning: { channel in
            guard let port = channel.localAddress?.port else { return }

            await bonjourPublisher.publish(port: port)
        },
    )
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 2)
    let serviceGroup = ServiceGroup(
        services: [
            EmbeddedApplicationService(
                application: localhostApp,
                shutdownBarrier: shutdownBarrier,
            ),
            EmbeddedApplicationService(
                application: lanApp,
                shutdownBarrier: shutdownBarrier,
                onStop: {
                    await bonjourPublisher.stop()
                },
            ),
        ],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.EmbeddedHTTPListeners"),
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: HTTPListenersConfig.localhostTransportName)
    await host.markTransportStarting(name: HTTPListenersConfig.lanTransportName)

    let runTask = Task<Void, Error> {
        try await serviceGroup.run()
    }
    do {
        let localhostTransport = try await waitForTransport(
            named: HTTPListenersConfig.localhostTransportName,
            state: "listening",
            on: host,
        )
        let lanTransport = try await waitForTransport(
            named: HTTPListenersConfig.lanTransportName,
            state: "listening",
            on: host,
        )
        let legacyHTTPTransport = try await waitForTransport(
            named: "http",
            state: "listening",
            requireBoundPort: false,
            on: host,
        )
        let localhostPort = try #require(localhostTransport.port)
        let lanPort = try #require(lanTransport.port)
        #expect(localhostPort > 0)
        #expect(lanPort > 0)
        #expect(localhostPort != lanPort)
        #expect(legacyHTTPTransport.state == "listening")

        let localhostOverview = try await httpJSON(path: "/overview", port: localhostPort)
        #expect(localhostOverview.statusCode == 200)
        #expect(localhostOverview.json["service"] as? String == configuration.name)

        let lanOverview = try await httpJSON(path: "/overview", port: lanPort)
        #expect(lanOverview.statusCode == 200)
        #expect(lanOverview.json["service"] as? String == configuration.name)

        let publishedServiceSnapshot = await bonjourPublisher.snapshot()
        let publishedService = try #require(publishedServiceSnapshot)
        #expect(publishedService.serviceName == lanListenerConfig.serviceName)
        #expect(publishedService.type == HTTPListenersConfig.lanBonjourType)
        #expect(publishedService.domain == HTTPListenersConfig.bonjourDomain)
        #expect(publishedService.port == lanPort)

        await serviceGroup.triggerGracefulShutdown()
        try await runTask.value
        await shutdownBarrier.waitUntilCompleted()
        let stoppedServiceSnapshot = await bonjourPublisher.snapshot()
        #expect(stoppedServiceSnapshot == nil)
    } catch {
        await serviceGroup.triggerGracefulShutdown()
        _ = try? await runTask.value
        throw error
    }
}

@available(macOS 14, *)
@Test func `HTTP listener runtime controls toggle localhost and LAN independently`() async throws {
    let configuration = testConfiguration()
    let localhostHTTPConfig = HTTPConfig(
        enabled: true,
        host: "127.0.0.1",
        port: 0,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
    )
    let lanListenerConfig = LANHTTPListenerConfig(
        enabled: false,
        host: "127.0.0.1",
        port: 0,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
        advertiseBonjour: false,
        serviceName: "SpeakSwiftly Server Runtime Toggle Test LAN",
    )
    let listenersConfig = HTTPListenersConfig(
        localhost: localhostHTTPConfig,
        lan: lanListenerConfig,
    )
    let runtime = MockRuntime(profiles: [sampleProfile()] + sampleSystemProfiles())
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: localhostHTTPConfig,
        listenersConfig: listenersConfig,
        mcpConfig: .init(enabled: false, path: "/mcp", serverName: "test-mcp", title: "Test MCP"),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let hostReadinessGate = EmbeddedLifecycleReadinessGate()
    let listenerController = HTTPListenerRuntimeController(
        host: host,
        localhostConfiguration: localhostHTTPConfig,
        lanConfiguration: lanListenerConfig,
        mcpConfig: .init(enabled: false, path: "/mcp", serverName: "test-mcp", title: "Test MCP"),
        localhostBeforeServerStarts: [
            {
                try await hostReadinessGate.waitUntilReady()
            },
        ],
        lanBeforeServerStarts: [
            {
                try await hostReadinessGate.waitUntilReady()
            },
        ],
        logger: Logger(label: "ServerTests.HTTPListenerRuntimeControls"),
    )
    await host.configureHTTPListenerRuntimeControl(listenerController.runtimeControl)
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let serviceGroup = ServiceGroup(
        services: [
            HTTPListenerRuntimeControllerService(
                controller: listenerController,
                shutdownBarrier: shutdownBarrier,
            ),
        ],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HTTPListenerRuntimeControls"),
    )

    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: HTTPListenersConfig.localhostTransportName)
    await host.start()
    await runtime.publishStatus(.residentModelReady)
    await hostReadinessGate.markReady()
    try await waitUntilReady(host)

    let runTask = Task<Void, Error> {
        try await serviceGroup.run()
    }
    do {
        let localhostTransport = try await waitForTransport(
            named: HTTPListenersConfig.localhostTransportName,
            state: "listening",
            on: host,
        )
        let localhostPort = try #require(localhostTransport.port)
        let initialLAN = try await host.transportStatus(named: HTTPListenersConfig.lanTransportName)
        #expect(initialLAN.enabled == false)
        #expect(initialLAN.state == "disabled")

        let enabledLANResponse = try await httpPOSTJSON(path: "/listeners/lan/enable", port: localhostPort)
        #expect(enabledLANResponse.statusCode == 200)
        #expect(enabledLANResponse.json["name"] as? String == HTTPListenersConfig.lanTransportName)
        #expect(enabledLANResponse.json["enabled"] as? Bool == true)
        #expect(enabledLANResponse.json["state"] as? String == "listening")

        let lanTransport = try await waitForTransport(
            named: HTTPListenersConfig.lanTransportName,
            state: "listening",
            on: host,
        )
        let lanPort = try #require(lanTransport.port)
        #expect(lanPort > 0)
        #expect(lanPort != localhostPort)
        #expect(lanTransport.advertisedAddress == "http://127.0.0.1:\(lanPort)")

        let lanOverview = try await httpJSON(path: "/overview", port: lanPort)
        #expect(lanOverview.statusCode == 200)
        #expect(lanOverview.json["service"] as? String == configuration.name)

        let disablingLANResponse = try await httpPOSTJSON(path: "/listeners/lan/disable", port: localhostPort)
        #expect(disablingLANResponse.statusCode == 200)
        #expect(disablingLANResponse.json["state"] as? String == "disabled")
        let disabledLAN = try await waitForTransport(
            named: HTTPListenersConfig.lanTransportName,
            state: "disabled",
            requireBoundPort: false,
            on: host,
        )
        #expect(disabledLAN.enabled == false)
        let localhostStillListening = try await waitForTransport(
            named: HTTPListenersConfig.localhostTransportName,
            state: "listening",
            on: host,
        )
        #expect(localhostStillListening.enabled == true)

        let reenabledLANResponse = try await httpPOSTJSON(path: "/listeners/lan/enable", port: localhostPort)
        #expect(reenabledLANResponse.statusCode == 200)
        let reenabledLAN = try await waitForTransport(
            named: HTTPListenersConfig.lanTransportName,
            state: "listening",
            on: host,
        )
        let reenabledLANPort = try #require(reenabledLAN.port)
        #expect(reenabledLAN.advertisedAddress == "http://127.0.0.1:\(reenabledLANPort)")
        let reenabledLANOverview = try await httpJSON(path: "/overview", port: reenabledLANPort)
        #expect(reenabledLANOverview.statusCode == 200)
        let unsupportedLocalhostDisable = try await httpPOSTJSON(
            path: "/listeners/localhost/disable",
            port: reenabledLANPort,
        )
        #expect(unsupportedLocalhostDisable.statusCode == 503)
        let finalLocalhost = try await waitForTransport(
            named: HTTPListenersConfig.localhostTransportName,
            state: "listening",
            on: host,
        )
        #expect(finalLocalhost.enabled == true)
        let finalLAN = try await waitForTransport(
            named: HTTPListenersConfig.lanTransportName,
            state: "listening",
            on: host,
        )
        #expect(finalLAN.enabled == true)

        await serviceGroup.triggerGracefulShutdown()
        try await runTask.value
        await shutdownBarrier.waitUntilCompleted()
    } catch {
        await serviceGroup.triggerGracefulShutdown()
        _ = try? await runTask.value
        throw error
    }
}

@available(macOS 14, *)
@Test func `embedded server can liftoff again after landing`() async throws {
    actor RestartProbe {
        private var bootstrapCallCount = 0
        private var requestStopCallCount = 0

        func recordBootstrap() {
            bootstrapCallCount += 1
        }

        func recordRequestStop() {
            requestStopCallCount += 1
        }

        func counts() -> (bootstrap: Int, requestStop: Int) {
            (bootstrapCallCount, requestStopCallCount)
        }
    }

    let probe = RestartProbe()
    let server = await MainActor.run { EmbeddedServer() }

    try await server.liftoff(
        environment: [:],
        defaultProfile: .embeddedSession,
        bootstrap: { _, _ in
            await probe.recordBootstrap()
            return EmbeddedServerLifecycleHooks(
                requestStop: {
                    await probe.recordRequestStop()
                },
                waitUntilStopped: {},
            )
        },
    )
    try await server.land()

    try await server.liftoff(
        environment: [:],
        defaultProfile: .embeddedSession,
        bootstrap: { _, _ in
            await probe.recordBootstrap()
            return EmbeddedServerLifecycleHooks(
                requestStop: {
                    await probe.recordRequestStop()
                },
                waitUntilStopped: {},
            )
        },
    )
    try await server.land()

    let counts = await probe.counts()
    #expect(counts.bootstrap == 2)
    #expect(counts.requestStop == 2)
}

@available(macOS 14, *)
@Test func `host lifecycle service waits for sibling shutdown before stopping runtime`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        httpConfig: testHTTPConfig(testConfiguration()),
        mcpConfig: .init(
            enabled: false,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "Speak Swiftly",
        ),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let readinessGate = EmbeddedLifecycleReadinessGate()
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = HostLifecycleService(
        host: host,
        readinessGate: readinessGate,
        shutdownBarrier: shutdownBarrier,
        startupTimeout: .seconds(15),
    )
    let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HostLifecycle"),
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
@Test func `host lifecycle service can shut down while startup is still in flight`() async throws {
    let runtime = MockRuntime(startBehavior: .waitForRelease)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let readinessGate = EmbeddedLifecycleReadinessGate()
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 0)
    let service = HostLifecycleService(
        host: host,
        readinessGate: readinessGate,
        shutdownBarrier: shutdownBarrier,
        startupTimeout: .seconds(15),
    )
    let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HostLifecycleStartupCancellation"),
    )

    let runTask = Task {
        try await serviceGroup.run()
    }

    await runtime.waitUntilStartReachesBarrier()
    await serviceGroup.triggerGracefulShutdown()
    try await runTask.value

    let lifecycleCounts = await runtime.lifecycleCounts()
    #expect(lifecycleCounts.start == 1)
    #expect(lifecycleCounts.shutdown == 1)
}

@available(macOS 14, *)
@Test func `host lifecycle service times out stuck startup clearly`() async throws {
    let runtime = MockRuntime(startBehavior: .waitForRelease)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let readinessGate = EmbeddedLifecycleReadinessGate()
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 0)
    let service = HostLifecycleService(
        host: host,
        readinessGate: readinessGate,
        shutdownBarrier: shutdownBarrier,
        startupTimeout: .milliseconds(20),
    )

    await #expect(throws: Error.self) {
        try await service.run()
    }

    let lifecycleCounts = await runtime.lifecycleCounts()
    #expect(lifecycleCounts.start == 1)
    #expect(lifecycleCounts.shutdown == 1)

    let readiness = await #expect(throws: Error.self) {
        try await readinessGate.waitUntilReady()
    }
    _ = readiness

    let snapshot = await host.hostStateSnapshot()
    #expect(snapshot.overview.startupError?.contains("timed out while waiting for the embedded runtime to finish startup") == true)
}

@available(macOS 14, *)
@Test func `host start waits for runtime start to finish`() async {
    actor StartCompletionProbe {
        private(set) var didFinish = false

        func markFinished() {
            didFinish = true
        }
    }

    let runtime = MockRuntime(startBehavior: .waitForRelease)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
@Test func `host shutdown cancels tracked request monitor tasks`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
@Test func `host prune service cancels on graceful shutdown and marks shutdown barrier`() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(jobPruneIntervalSeconds: 60)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = HostPruneService(
        host: host,
        shutdownBarrier: shutdownBarrier,
    )
    let serviceGroup = ServiceGroup(
        services: [service],
        gracefulShutdownSignals: [],
        cancellationSignals: [],
        logger: Logger(label: "ServerTests.HostPrune"),
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
@Test func `embedded application service marks shutdown barrier when wrapped service fails`() async throws {
    struct FailingService: Service {
        struct ExpectedFailure: Error {}

        func run() async throws {
            throw ExpectedFailure()
        }
    }

    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: 1)
    let service = EmbeddedApplicationService(
        application: FailingService(),
        shutdownBarrier: shutdownBarrier,
    )

    await #expect(throws: FailingService.ExpectedFailure.self) {
        try await service.run()
    }

    await shutdownBarrier.waitUntilCompleted()
}

@available(macOS 14, *)
@Test func `host publishes typed events for server consumers`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "Speak Swiftly",
        ),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
            case let .transportChanged(snapshot):
                if snapshot.name == "http", snapshot.state == "starting" {
                    sawTransportChange = true
                }
            case let .profileCacheChanged(snapshot):
                if snapshot.state == "fresh", snapshot.profileCount == 1 {
                    sawProfileCacheChange = true
                }
            case let .jobChanged(snapshot):
                if snapshot.jobID == jobID {
                    sawJobChange = true
                }
            case let .jobEvent(update):
                if update.jobID == jobID {
                    sawJobEvent = true
                }
            case let .playbackChanged(snapshot):
                if snapshot.state == "playing" {
                    sawPlaybackChange = true
                }
            case .textProfilesChanged, .runtimeConfigurationChanged, .networkAudioDestinationsChanged, .recentErrorRecorded:
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
@Test func `host tracks transport lifecycle beyond static configuration`() async {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "Speak Swiftly",
        ),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
    )

    let initial = await host.hostStateSnapshot()
    #expect(initial.transports.contains { $0.name == "http" && $0.state == "stopped" })
    #expect(initial.transports.contains { $0.name == "http_localhost" && $0.state == "stopped" })
    #expect(initial.transports.contains { $0.name == "http_lan" && $0.state == "disabled" })
    #expect(initial.transports.contains { $0.name == "mcp" && $0.state == "stopped" })

    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: "http_localhost")
    await host.markTransportListening(name: "mcp")

    let updated = await host.hostStateSnapshot()
    #expect(updated.transports.contains { $0.name == "http" && $0.state == "starting" })
    #expect(updated.transports.contains { $0.name == "http_localhost" && $0.state == "starting" })
    #expect(updated.transports.contains { $0.name == "mcp" && $0.state == "listening" })
}

@available(macOS 14, *)
@Test func `host applies safe live configuration changes and reports restart required ones`() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(completedJobMaxCount: 2)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "Speak Swiftly",
        ),
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
                jobPruneIntervalSeconds: 0.01,
            ),
            http: .init(
                enabled: true,
                host: "0.0.0.0",
                port: 7999,
                sseHeartbeatSeconds: 5,
            ),
            listeners: .init(
                localhost: .init(
                    enabled: true,
                    host: "127.0.0.1",
                    port: 7998,
                    sseHeartbeatSeconds: 5,
                ),
                lan: .init(
                    enabled: true,
                    host: "0.0.0.0",
                    port: 0,
                    sseHeartbeatSeconds: 5,
                    advertiseBonjour: true,
                    serviceName: "Reloaded LAN Generator",
                ),
            ),
            mcp: .init(
                enabled: true,
                path: "/assistant/mcp",
                serverName: "new-mcp-name",
                title: "New MCP Title",
            ),
            networkAudioReceiver: .init(
                enabled: true,
                serviceName: "Reloaded Receiver",
                port: 7447,
                sharedToken: "reloaded-token",
            ),
        ),
    )

    let hostState = await host.hostStateSnapshot()
    #expect(hostState.overview.service == "reloaded-service")
    #expect(hostState.overview.environment == "qa")
    #expect(hostState.overview.defaultVoiceProfileName == "default-femme")
    #expect(hostState.recentErrors.contains {
        $0.source == "config" &&
            $0.code == "reload_requires_restart" &&
            $0.message.contains("app.http.port") &&
            $0.message.contains("app.listeners.lan.enabled") &&
            $0.message.contains("app.mcp.path")
    })

    let snapshots = await host.jobSnapshots()
    #expect(snapshots.count == 1)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `host records rejected configuration reloads clearly`() async {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
@Test func `app managed default voice profile override survives configuration reload`() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(defaultVoiceProfileName: "configured-default")
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
        state: state,
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
                jobPruneIntervalSeconds: configuration.jobPruneIntervalSeconds,
            ),
            http: testHTTPConfig(configuration),
            mcp: .init(enabled: false, path: "/mcp", serverName: "speak-swiftly-mcp", title: "Speak Swiftly"),
            networkAudioReceiver: .init(
                enabled: false,
                serviceName: "SpeakSwiftly Audio Receiver",
                port: 0,
                sharedToken: nil,
            ),
        ),
    )

    #expect(await host.defaultVoiceProfileName() == "app-selected-default")
    let hostState = await host.hostStateSnapshot()
    #expect(hostState.overview.defaultVoiceProfileName == "app-selected-default")

    await host.shutdown()
}

@available(macOS 14, *)
private func waitForNetworkAudioReceiverPort(on host: ServerHost) async throws -> Int {
    try await waitUntil(timeout: .seconds(5), pollInterval: .milliseconds(25)) {
        let snapshot = await host.hostStateSnapshot()
        return snapshot.transports
            .first {
                $0.name == NetworkAudioReceiverConfig.transportName &&
                    $0.state == "listening" &&
                    ($0.port ?? 0) > 0
            }?.port
    }
}

@available(macOS 14, *)
private func waitForTransport(
    named name: String,
    state expectedState: String,
    requireBoundPort: Bool = true,
    on host: ServerHost,
) async throws -> TransportStatusSnapshot {
    try await waitUntil(timeout: .seconds(5), pollInterval: .milliseconds(25)) {
        let snapshot = await host.hostStateSnapshot()
        return snapshot.transports
            .first {
                $0.name == name &&
                    $0.state == expectedState &&
                    (!requireBoundPort || ($0.port ?? 0) > 0)
            }
    }
}

private func httpJSON(path: String, port: Int) async throws -> (statusCode: Int, json: [String: Any]) {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    let (data, response) = try await URLSession.shared.data(for: request)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    return try (statusCode, jsonObject(from: data))
}

private func httpPOSTJSON(path: String, port: Int) async throws -> (statusCode: Int, json: [String: Any]) {
    let url = try #require(URL(string: "http://127.0.0.1:\(port)\(path)"))
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    let (data, response) = try await URLSession.shared.data(for: request)
    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
    return try (statusCode, jsonObject(from: data))
}

@available(macOS 14, *)
private func waitForReceivedNetworkAudioChunks(
    _ probe: any ReceivedNetworkAudioChunkSnapshotting,
) async throws -> [SpeakSwiftly.GeneratedAudioChunk] {
    try await waitUntil(timeout: .seconds(5), pollInterval: .milliseconds(25)) {
        let chunks = await probe.snapshot()
        return chunks.contains(where: \.isFinal) ? chunks : nil
    }
}

private protocol ReceivedNetworkAudioChunkSnapshotting: Sendable {
    func snapshot() async -> [SpeakSwiftly.GeneratedAudioChunk]
}
