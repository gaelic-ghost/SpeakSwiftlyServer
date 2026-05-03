import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Host State Tests

@Test func `shared playback and queue snapshots keep transport response field names`() throws {
    let activeRequest = ActiveRequestSnapshot(id: "request-1", op: "generate_speech", profileName: "default")
    let queuedRequest = QueuedRequestSnapshot(
        id: "request-2",
        op: "generate_speech",
        profileName: "default",
        queuePosition: 1,
    )
    let playback = PlaybackStatusSnapshot(
        state: "playing",
        activeRequest: activeRequest,
        isStableForConcurrentGeneration: true,
        isRebuffering: false,
        stableBufferedAudioMS: 300,
        stableBufferTargetMS: 250,
    )
    let queue = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 1,
        queuedCount: 1,
        activeRequest: activeRequest,
        activeRequests: [activeRequest],
        queuedRequests: [queuedRequest],
    )

    let playbackJSON = try jsonObject(from: JSONEncoder().encode(PlaybackStateResponse(playback: playback)))
    let playbackBody = try #require(playbackJSON["playback"] as? [String: Any])
    #expect(playbackBody["state"] as? String == "playing")
    #expect((playbackBody["active_request"] as? [String: Any])?["id"] as? String == "request-1")
    #expect(playbackBody["is_stable_for_concurrent_generation"] as? Bool == true)
    #expect(playbackBody["is_rebuffering"] as? Bool == false)
    #expect(playbackBody["stable_buffered_audio_ms"] as? Int == 300)
    #expect(playbackBody["stable_buffer_target_ms"] as? Int == 250)

    let hostStateJSON = try jsonObject(
        from: JSONEncoder().encode(
            HostStateSnapshot(
                overview: .init(
                    service: "speak-swiftly-server",
                    environment: "test",
                    defaultVoiceProfileName: "default",
                    serverMode: "ready",
                    workerMode: "ready",
                    workerStage: "resident_model_ready",
                    workerReady: true,
                    startupError: nil,
                    profileCacheState: "fresh",
                    profileCacheWarning: nil,
                    profileCount: 1,
                    lastProfileRefreshAt: nil,
                ),
                runtimeRefresh: nil,
                generationQueue: queue,
                playbackQueue: queue,
                playback: playback,
                runtimeBackendTransition: .init(
                    state: "idle",
                    activeSpeechBackend: "qwen3",
                    requestedSpeechBackend: nil,
                    requestID: nil,
                    operation: nil,
                    waitingReason: nil,
                    submittedAt: nil,
                    startedAt: nil,
                ),
                currentGenerationJobs: [],
                runtimeConfiguration: .init(
                    activeRuntimeSpeechBackend: "qwen3",
                    nextRuntimeSpeechBackend: "qwen3",
                    activeQwenResidentModel: "base_0_6b_8bit",
                    nextQwenResidentModel: "base_0_6b_8bit",
                    activeMarvisResidentPolicy: "dual_resident_serialized",
                    nextMarvisResidentPolicy: "dual_resident_serialized",
                    activeDefaultVoiceProfileName: "default",
                    nextDefaultVoiceProfileName: "default",
                    environmentSpeechBackendOverride: nil,
                    environmentQwenResidentModelOverride: nil,
                    persistedSpeechBackend: nil,
                    persistedQwenResidentModel: nil,
                    persistedMarvisResidentPolicy: nil,
                    persistedDefaultVoiceProfileName: nil,
                    profileRootPath: "/tmp/profiles",
                    persistedConfigurationPath: "/tmp/profiles/configuration.json",
                    persistedConfigurationExists: false,
                    persistedConfigurationState: "missing",
                    persistedConfigurationError: nil,
                    persistedConfigurationAppliesOnRestart: true,
                    activeRuntimeMatchesNextRuntime: true,
                    persistedConfigurationWillAffectNextRuntimeStart: true,
                ),
                transports: [],
                recentErrors: [],
            ),
        ),
    )
    let hostPlayback = try #require(hostStateJSON["playback"] as? [String: Any])
    #expect(hostPlayback["state"] as? String == playbackBody["state"] as? String)
    #expect((hostPlayback["active_request"] as? [String: Any])?["id"] as? String == "request-1")
    #expect(hostPlayback["stable_buffered_audio_ms"] as? Int == playbackBody["stable_buffered_audio_ms"] as? Int)

    let queueJSON = try jsonObject(from: JSONEncoder().encode(QueueSnapshotResponse(snapshot: queue)))
    #expect(queueJSON["queue_type"] as? String == "playback")
    #expect((queueJSON["active_request"] as? [String: Any])?["id"] as? String == "request-1")
    #expect((queueJSON["active_requests"] as? [[String: Any]])?.count == 1)
    #expect((queueJSON["queue"] as? [[String: Any]])?.first?["id"] as? String == "request-2")
    #expect(queueJSON["queued_requests"] == nil)
}

@available(macOS 14, *)
@Test func `state completes queued speech jobs and prunes expired entries`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(completedJobTTLSeconds: 0.05, jobPruneIntervalSeconds: 0.02),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
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
@Test func `state prunes oldest completed jobs when max count is exceeded`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(completedJobTTLSeconds: 60, completedJobMaxCount: 2),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
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
@Test func `sse replay includes worker status history and heartbeat`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(sseHeartbeatSeconds: 0.02),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitSpeak(text: "Keep speaking", profileName: "default")
    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10),
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
@Test func `host publishes shared state for ui and server consumers`() async throws {
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
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
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

        if snapshot.currentGenerationJobs.contains(where: { $0.jobID == jobID }),
           snapshot.generationQueue.activeCount == 1 {
            publishedState = snapshot
            break
        }
    }
    let liveState = try #require(publishedState)

    let runtimeRefresh = try #require(liveState.runtimeRefresh)
    #expect(liveState.playback.state == "playing")
    #expect(runtimeRefresh.sequenceID > 0)
    #expect(runtimeRefresh.source == "runtime_overview")
    #expect(runtimeRefresh.startedAt.isEmpty == false)
    #expect(runtimeRefresh.completedAt.isEmpty == false)
    #expect(liveState.transports.contains { $0.name == "http" && $0.advertisedAddress == "http://127.0.0.1:7337" })
    #expect(liveState.transports.contains { $0.name == "mcp" && $0.advertisedAddress == "http://127.0.0.1:7337/mcp" })

    let uiOverview = await MainActor.run { state.overview }
    let uiRuntimeRefresh = await MainActor.run { state.runtimeRefresh }
    let uiCurrentJobs = await MainActor.run { state.currentGenerationJobs }
    let uiPlayback = await MainActor.run { state.playback }
    let uiVoiceProfiles = await MainActor.run { state.voiceProfiles }
    #expect(uiOverview.workerReady == true)
    #expect(uiRuntimeRefresh == runtimeRefresh)
    #expect(uiCurrentJobs.contains { $0.jobID == jobID })
    #expect(uiPlayback.state == "playing")
    #expect(uiVoiceProfiles.contains { $0.profileName == "default" })

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func `host uses runtime snapshots for queued live speech jobs`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
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
        pollInterval: .milliseconds(10),
    ) {
        let snapshot = await host.hostStateSnapshot()
        guard
            snapshot.runtimeRefresh?.source == "runtime_overview",
            snapshot.playback.activeRequest?.id == firstJobID,
            snapshot.playbackQueue.activeRequest?.id == firstJobID,
            snapshot.generationQueue.queuedCount == 1,
            snapshot.currentGenerationJobs.contains(where: { $0.jobID == firstJobID })
        else {
            return nil
        }

        return snapshot
    }

    let countsAfterQueuedLiveRequests = await runtime.runtimeRefreshActionCounts()
    #expect(countsAfterQueuedLiveRequests.generationQueue > baselineRefreshCounts.generationQueue)
    #expect(countsAfterQueuedLiveRequests.playbackQueue > baselineRefreshCounts.playbackQueue)
    #expect(countsAfterQueuedLiveRequests.playbackState > baselineRefreshCounts.playbackState)
    #expect(snapshot.currentGenerationJobs.contains { $0.jobID == firstJobID })

    let secondJobSnapshot = try await host.jobSnapshot(id: secondJobID)
    #expect(secondJobSnapshot.history.contains {
        guard case let .queued(event) = $0 else { return false }

        return event.reason == "waiting_for_active_request"
    })

    await runtime.finishHeldSpeak(id: firstJobID)
    await runtime.finishHeldSpeak(id: secondJobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func `host refreshes runtime snapshots for held live progress events`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitSpeak(text: "Hold steady", profileName: "default")
    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10),
    ) {
        let snapshot = try await host.jobSnapshot(id: jobID)
        return snapshot.history.count >= 2 ? snapshot : nil
    }

    try await Task.sleep(for: .milliseconds(50))
    let baselineRefreshCounts = await runtime.runtimeRefreshActionCounts()

    await runtime.publishHeldSpeakProgress(id: jobID, stage: .bufferingAudio)

    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10),
    ) {
        let snapshot = try await host.jobSnapshot(id: jobID)
        return snapshot.history.contains {
            guard case let .progress(event) = $0 else { return false }

            return event.stage == "buffering_audio"
        } ? snapshot : nil
    }

    let _: Bool = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10),
    ) {
        let counts = await runtime.runtimeRefreshActionCounts()
        guard
            counts.generationQueue > baselineRefreshCounts.generationQueue,
            counts.playbackQueue > baselineRefreshCounts.playbackQueue,
            counts.playbackState > baselineRefreshCounts.playbackState
        else {
            return nil
        }

        return true
    }
    let countsAfterProgress = await runtime.runtimeRefreshActionCounts()
    #expect(countsAfterProgress.generationQueue > baselineRefreshCounts.generationQueue)
    #expect(countsAfterProgress.playbackQueue > baselineRefreshCounts.playbackQueue)
    #expect(countsAfterProgress.playbackState > baselineRefreshCounts.playbackState)

    await runtime.finishHeldSpeak(id: jobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func `startup readiness waits for default voice install to finish`() async throws {
    let runtime = MockRuntime(profiles: [])
    await runtime.holdNextVoiceProfileRefresh()
    let host = await ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: MainActor.run { EmbeddedServer() },
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    await runtime.waitUntilVoiceProfileRefreshIsHeld()
    await host.handle(status: workerStatus(.residentModelReady))

    let readinessWhileInstalling = await host.readinessSnapshot()
    #expect(readinessWhileInstalling.0 == false)
    await #expect(throws: Error.self) {
        try await host.submitSpeak(text: "Too soon", profileName: "swift-signal")
    }

    await runtime.releaseHeldVoiceProfileRefresh()
    try await waitUntilReady(host)

    let status = await host.statusSnapshot()
    #expect(status.cachedProfiles.contains { $0.profileName == "swift-signal" })
    #expect(status.cachedProfiles.contains { $0.profileName == "swift-anchor" })

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `stale startup readiness does not overwrite newer worker status`() async {
    let runtime = MockRuntime(profiles: [])
    await runtime.holdNextVoiceProfileRefresh()
    let host = await ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: MainActor.run { EmbeddedServer() },
    )

    let readyTask = Task {
        await host.handle(status: workerStatus(.residentModelReady))
    }
    await runtime.waitUntilVoiceProfileRefreshIsHeld()

    await host.handle(status: workerStatus(.residentModelFailed))
    let failedStatus = await host.statusSnapshot()
    #expect(failedStatus.workerMode == "failed")

    await runtime.releaseHeldVoiceProfileRefresh()
    await readyTask.value

    let finalStatus = await host.statusSnapshot()
    #expect(finalStatus.workerMode == "failed")
    #expect(finalStatus.workerStage == SpeakSwiftly.StatusStage.residentModelFailed.rawValue)
}

@available(macOS 14, *)
@Test func `startup default voice install retries after transient refresh failure`() async {
    let runtime = MockRuntime(profiles: [])
    await runtime.failNextVoiceProfileRefresh(message: "temporary profile list transport failure")
    let host = await ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: MainActor.run { EmbeddedServer() },
    )

    await host.handle(status: workerStatus(.residentModelReady))
    let degradedStatus = await host.statusSnapshot()
    #expect(degradedStatus.profileCacheState == "stale")
    #expect(degradedStatus.cachedProfiles.isEmpty)

    await host.handle(status: workerStatus(.residentModelReady))

    let recoveredStatus = await host.statusSnapshot()
    #expect(recoveredStatus.profileCacheState == "fresh")
    #expect(recoveredStatus.cachedProfiles.contains { $0.profileName == "swift-signal" })
    #expect(recoveredStatus.cachedProfiles.contains { $0.profileName == "swift-anchor" })
}

@available(macOS 14, *)
@Test func `state projects cached voice profiles and forwards playback controls`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await MainActor.run {
        state.configureActions(
            .init(
                refreshVoiceProfiles: {
                    try await host.refreshVoiceProfiles()
                },
                queueLiveSpeech: { text, profileName, textProfileID, normalizationContext, sourceFormat, requestContext, qwenPreModelTextChunking in
                    guard let resolvedProfileName = await host.resolvedRequestedVoiceProfileName(profileName) else {
                        let errorMessage = await host.missingVoiceProfileNameMessage(for: "the live speech request")
                        throw ServerConfigurationError(errorMessage)
                    }

                    return try await host.queueSpeechLive(
                        text: text,
                        profileName: resolvedProfileName,
                        textProfileID: textProfileID,
                        normalizationContext: normalizationContext,
                        sourceFormat: sourceFormat,
                        requestContext: requestContext,
                        qwenPreModelTextChunking: qwenPreModelTextChunking,
                    )
                },
                setDefaultVoiceProfileName: { profileName in
                    try await host.setDefaultVoiceProfileName(profileName)
                },
                clearDefaultVoiceProfileName: {
                    try await host.clearDefaultVoiceProfileName()
                },
                switchSpeechBackend: { speechBackend in
                    _ = try await host.switchSpeechBackend(to: speechBackend)
                    return await host.hostStateSnapshot()
                },
                reloadModels: {
                    _ = try await host.reloadModels()
                    return await host.hostStateSnapshot()
                },
                unloadModels: {
                    _ = try await host.unloadModels()
                    return await host.hostStateSnapshot()
                },
                pausePlayback: {
                    let response = try await host.pausePlayback()
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                resumePlayback: {
                    let response = try await host.resumePlayback()
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                clearPlaybackQueue: {
                    let response = try await host.clearQueue()
                    return response.clearedCount
                },
                cancelPlaybackRequest: { requestID in
                    let response = try await host.cancelQueuedOrActiveRequest(requestID: requestID)
                    return response.cancelledRequestID
                },
            ),
        )
    }

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let initialVoiceProfiles = await state.listVoiceProfiles()
    #expect(initialVoiceProfiles.contains { $0.profileName == "default" })

    let refreshCountBeforeManualRefresh = await runtime.voiceProfileRefreshCount()
    let refreshedProfiles = try await state.refreshVoiceProfiles()
    let refreshCountAfterManualRefresh = await runtime.voiceProfileRefreshCount()
    #expect(refreshedProfiles.contains { $0.profileName == "default" })
    #expect(refreshCountAfterManualRefresh == refreshCountBeforeManualRefresh + 1)

    let firstQueuedRequestID = try await state.queueLiveSpeech(
        text: "Read this aloud",
        profileName: "default",
        textProfileID: "swift-docs",
        normalizationContext: .init(
            cwd: "./Sources",
            repoRoot: ".",
            textFormat: .markdown,
            nestedSourceFormat: .swift,
        ),
        sourceFormat: .python,
        requestContext: .init(
            source: "embedded-session",
            app: "SpeakSwiftlyServerTests",
            project: "SpeakSwiftlyServer",
            topic: "state-actions",
            attributes: ["surface": "embedded"],
        ),
    )
    let firstQueuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
    #expect(firstQueuedRequestID.isEmpty == false)
    #expect(firstQueuedSpeechInvocation.text == "Read this aloud")
    #expect(firstQueuedSpeechInvocation.profileName == "default")
    #expect(firstQueuedSpeechInvocation.textProfileID == "swift-docs")
    let expectedNormalizationContext = SpeechNormalizationContext(
        cwd: "./Sources",
        repoRoot: ".",
        textFormat: .markdown,
        nestedSourceFormat: .swift,
    )
    #expect(firstQueuedSpeechInvocation.normalizationContext == expectedNormalizationContext)
    #expect(firstQueuedSpeechInvocation.sourceFormat == .python)
    #expect(
        firstQueuedSpeechInvocation.requestContext
            == SpeakSwiftly.RequestContext(
                source: "embedded-session",
                app: "SpeakSwiftlyServerTests",
                project: "SpeakSwiftlyServer",
                topic: "state-actions",
                attributes: ["surface": "embedded"],
            ),
    )
    await runtime.finishHeldSpeak(id: firstQueuedRequestID)

    let defaultVoiceProfileName = try await state.setDefaultVoiceProfileName("default")
    #expect(defaultVoiceProfileName == "default")
    let overviewAfterSet = await MainActor.run { state.overview }
    #expect(overviewAfterSet.defaultVoiceProfileName == "default")
    #expect(await host.defaultVoiceProfileName() == "default")
    #expect(await host.resolvedRequestedVoiceProfileName(nil) == "default")

    let secondQueuedRequestID = try await state.queueLiveSpeech(text: "Use the app default")
    let secondQueuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
    #expect(secondQueuedSpeechInvocation.profileName == "default")
    await runtime.finishHeldSpeak(id: secondQueuedRequestID)

    try await state.clearDefaultVoiceProfileName()
    let overviewAfterClear = await MainActor.run { state.overview }
    #expect(overviewAfterClear.defaultVoiceProfileName == nil)
    #expect(await host.defaultVoiceProfileName() == nil)
    #expect(await host.resolvedRequestedVoiceProfileName(nil) == nil)

    do {
        _ = try await state.queueLiveSpeech(text: "This should fail without a default")
        Issue.record("Expected live speech submission to fail when neither profileName nor app.defaultVoiceProfileName is available.")
    } catch {
        let message = String(describing: error)
        #expect(message.contains("app.defaultVoiceProfileName"))
    }

    let switchedSnapshot = try await state.switchSpeechBackend(to: .chatterboxTurbo)
    #expect(switchedSnapshot.runtimeConfiguration.activeRuntimeSpeechBackend == "chatterbox_turbo")
    let runtimeConfigurationAfterSwitch = await MainActor.run { state.runtimeConfiguration }
    #expect(runtimeConfigurationAfterSwitch.activeRuntimeSpeechBackend == "chatterbox_turbo")

    let reloadedSnapshot = try await state.reloadModels()
    #expect(reloadedSnapshot.overview.workerStage == "resident_model_ready")
    let overviewAfterReload = await MainActor.run { state.overview }
    #expect(overviewAfterReload.workerStage == "resident_model_ready")

    let unloadedSnapshot = try await state.unloadModels()
    #expect(unloadedSnapshot.overview.workerStage == "resident_models_unloaded")
    let overviewAfterUnload = await MainActor.run { state.overview }
    #expect(overviewAfterUnload.workerStage == "resident_models_unloaded")

    let readySnapshotBeforePlayback = try await state.reloadModels()
    #expect(readySnapshotBeforePlayback.overview.workerStage == "resident_model_ready")

    let firstJobID = try await host.submitSpeak(text: "Hold this line", profileName: "default")
    let secondJobID = try await host.submitSpeak(text: "Cancel me next", profileName: "default")

    _ = try await waitUntil(
        timeout: .seconds(1),
        pollInterval: .milliseconds(10),
    ) {
        let playback = await MainActor.run { state.playback }
        return playback.state == "playing" ? playback : nil
    }

    let pausedPlayback = try await state.pausePlayback()
    #expect(pausedPlayback.state == "paused")

    let resumedPlayback = try await state.resumePlayback()
    #expect(resumedPlayback.state == "playing")

    let cancelledRequestID = try await state.cancelPlaybackRequest(secondJobID)
    #expect(cancelledRequestID == secondJobID)

    let clearedCount = try await state.clearPlaybackQueue()
    #expect(clearedCount == 0)

    await runtime.finishHeldSpeak(id: firstJobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func `startup installs bundled default voice seeds when profiles are missing`() async throws {
    let runtime = MockRuntime(profiles: [])
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)

    let status = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let status = await host.statusSnapshot()
        return status.cachedProfiles.contains { $0.profileName == "swift-signal" }
            && status.cachedProfiles.contains { $0.profileName == "swift-anchor" }
            ? status
            : nil
    }
    let invocationNames = await runtime.createProfileInvocationNames()
    let latestInvocation = try #require(await runtime.latestCreateProfileInvocation())
    #expect(invocationNames == ["swift-signal", "swift-anchor"])
    #expect(latestInvocation.author == .system)
    #expect(latestInvocation.seedID == "swift.anchor")
    #expect(latestInvocation.seedVersion == "1")
    #expect(status.cachedProfiles.map(\.profileName).sorted() == ["swift-anchor", "swift-signal"])
    #expect(status.cachedProfiles.allSatisfy { $0.isSystemAuthored })
    #expect(status.recentErrors.isEmpty)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `startup installs bundled default voice seed with fallback name when preferred name is occupied`() async throws {
    let runtime = MockRuntime(
        profiles: [
            SpeakSwiftly.ProfileSummary(
                profileName: "swift-signal",
                vibe: .femme,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                voiceDescription: "User-owned signal voice",
                sourceText: "This is a user-owned profile occupying the preferred built-in name.",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ],
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)

    let status = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let status = await host.statusSnapshot()
        return status.cachedProfiles.contains { $0.profileName == "swift-signal-builtin" }
            && status.cachedProfiles.contains { $0.profileName == "swift-anchor" }
            ? status
            : nil
    }
    let invocationNames = await runtime.createProfileInvocationNames()
    #expect(invocationNames == ["swift-signal-builtin", "swift-anchor"])
    #expect(status.cachedProfiles.contains { $0.profileName == "swift-signal" })
    #expect(status.recentErrors.isEmpty)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `startup reuses existing fallback default voice when preferred name becomes free`() async throws {
    let signalSeed = try #require(DefaultVoiceCatalog.load().first { $0.profileName == "swift-signal" })
    let runtime = MockRuntime(
        profiles: [
            SpeakSwiftly.ProfileSummary(
                profileName: "swift-signal-builtin",
                vibe: signalSeed.vibe,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                voiceDescription: signalSeed.voiceDescription,
                sourceText: signalSeed.sourceText,
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ],
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)

    let status = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let status = await host.statusSnapshot()
        return status.cachedProfiles.contains { $0.profileName == "swift-anchor" }
            ? status
            : nil
    }
    let invocationNames = await runtime.createProfileInvocationNames()
    #expect(invocationNames == ["swift-anchor"])
    #expect(status.cachedProfiles.contains { $0.profileName == "swift-signal-builtin" })
    #expect(status.cachedProfiles.contains { $0.profileName == "swift-signal" } == false)
    #expect(status.recentErrors.isEmpty)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `startup installs fallback default voice when unrelated profile matches seed metadata`() async throws {
    let signalSeed = try #require(DefaultVoiceCatalog.load().first { $0.profileName == "swift-signal" })
    let runtime = MockRuntime(
        profiles: [
            SpeakSwiftly.ProfileSummary(
                profileName: "swift-signal",
                vibe: .femme,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                voiceDescription: "User-owned signal voice",
                sourceText: "This is a user-owned profile occupying the preferred built-in name.",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
            SpeakSwiftly.ProfileSummary(
                profileName: "renamed-signal-copy",
                vibe: signalSeed.vibe,
                createdAt: Date(timeIntervalSince1970: 1_700_000_100),
                voiceDescription: signalSeed.voiceDescription,
                sourceText: signalSeed.sourceText,
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ],
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)

    let status = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let status = await host.statusSnapshot()
        return status.cachedProfiles.contains { $0.profileName == "swift-signal-builtin" }
            && status.cachedProfiles.contains { $0.profileName == "swift-anchor" }
            ? status
            : nil
    }
    let invocationNames = await runtime.createProfileInvocationNames()
    #expect(invocationNames == ["swift-signal-builtin", "swift-anchor"])
    #expect(status.cachedProfiles.contains { $0.profileName == "renamed-signal-copy" })
    #expect(status.recentErrors.isEmpty)

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `rerolling a voice profile refreshes cached profile metadata`() async throws {
    let originalCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let runtime = MockRuntime(
        profiles: [
            SpeakSwiftly.ProfileSummary(
                profileName: "default",
                vibe: .femme,
                createdAt: originalCreatedAt,
                voiceDescription: "Warm guide voice",
                sourceText: "Original training text",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ],
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let baselineRefreshCount = await runtime.voiceProfileRefreshCount()
    let baselineStatus = await host.statusSnapshot()
    let baselineProfile = try #require(baselineStatus.cachedProfiles.first(where: { $0.profileName == "default" }))
    #expect(baselineProfile.createdAt == TimestampFormatter.string(from: originalCreatedAt))
    #expect(baselineProfile.voiceDescription == "Warm guide voice")
    #expect(baselineProfile.sourceText == "Original training text")

    let rerollJobID = try await host.submitRerollProfile(profileName: "default")
    let rerollSnapshot = try await waitForJobSnapshot(rerollJobID, on: host)
    #expect(rerollSnapshot.status == "completed")

    let refreshedStatus = await host.statusSnapshot()
    let refreshedProfile = try #require(refreshedStatus.cachedProfiles.first(where: { $0.profileName == "default" }))
    let refreshedCount = await runtime.voiceProfileRefreshCount()
    #expect(refreshedCount == baselineRefreshCount + 1)
    #expect(refreshedProfile.createdAt == TimestampFormatter.string(from: originalCreatedAt.addingTimeInterval(60)))
    #expect(refreshedProfile.voiceDescription == "Warm guide voice (rerolled)")
    #expect(refreshedProfile.sourceText == "Original training text (rerolled)")

    await host.shutdown()
}

@available(macOS 14, *)
@Test func `renaming a voice profile tolerates unrelated profile refresh changes`() async throws {
    let runtime = MockRuntime(
        profiles: [
            SpeakSwiftly.ProfileSummary(
                profileName: "default",
                vibe: .femme,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                voiceDescription: "Default voice",
                sourceText: "Default text",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ],
    )
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    await runtime.setScriptedProfileRefreshSnapshots(
        [[
            SpeakSwiftly.ProfileSummary(
                profileName: "renamed-default",
                vibe: .femme,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                voiceDescription: "Default voice",
                sourceText: "Default text",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
            SpeakSwiftly.ProfileSummary(
                profileName: "external-addition",
                vibe: .femme,
                createdAt: Date(timeIntervalSince1970: 1_700_000_120),
                voiceDescription: "Added outside the host cache",
                sourceText: "External text",
                transcriptSource: nil,
                transcriptResolvedAt: nil,
                transcriptionModelRepo: nil,
            ),
        ]],
    )

    let jobID = try await host.submitRenameProfile(profileName: "default", newProfileName: "renamed-default")
    let snapshot = try await waitForJobSnapshot(jobID, on: host)
    #expect(snapshot.status == "completed")
    #expect(snapshot.terminalEvent != nil)

    let status = await host.statusSnapshot()
    #expect(status.profileCacheState == "fresh")
    #expect(status.cachedProfiles.contains { $0.profileName == "renamed-default" })
    #expect(status.cachedProfiles.contains { $0.profileName == "external-addition" })
    #expect(status.cachedProfiles.contains { $0.profileName == "default" } == false)

    await host.shutdown()
}

@Test func `runtime adapter path resolution normalizes relative and whitespace padded cwd values`() {
    let temporaryRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("speakswiftly-tests", isDirectory: true)
    let currentDirectoryPath = temporaryRootURL
        .appendingPathComponent("workspace", isDirectory: true)
        .path
    let projectPath = temporaryRootURL
        .appendingPathComponent("project", isDirectory: true)
        .path

    #expect(
        resolvedAbsoluteFilesystemPath(
            "./Artifacts/output.wav",
            cwd: "  \(projectPath)  ",
            currentDirectoryPath: currentDirectoryPath,
        ) == URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent("Artifacts/output.wav", isDirectory: false)
            .path,
    )

    #expect(
        resolvedAbsoluteFilesystemPath(
            "../Fixtures/reference.wav",
            cwd: "  ./Runs/Session  ",
            currentDirectoryPath: currentDirectoryPath,
        ) == URL(fileURLWithPath: currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Runs/Fixtures/reference.wav", isDirectory: false)
            .path,
    )

    let finalPath = temporaryRootURL
        .appendingPathComponent("nested/../final.wav", isDirectory: false)
        .path
    #expect(
        resolvedAbsoluteFilesystemPath(
            finalPath,
            cwd: "./ignored",
            currentDirectoryPath: currentDirectoryPath,
        ) == temporaryRootURL.appendingPathComponent("final.wav", isDirectory: false).path,
    )

    #expect(
        resolvedAbsoluteFilesystemPath(
            "   ",
            cwd: projectPath,
            currentDirectoryPath: currentDirectoryPath,
        ) == nil,
    )
}

@available(macOS 14, *)
@Test func `clearing app managed default voice profile falls back to configured default`() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(defaultVoiceProfileName: "configured-default")
    let state = await MainActor.run { EmbeddedServer() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: testRuntimeConfigurationStore(),
        state: state,
    )

    await MainActor.run {
        state.configureActions(
            .init(
                refreshVoiceProfiles: {
                    try await host.refreshVoiceProfiles()
                },
                queueLiveSpeech: { text, profileName, textProfileID, normalizationContext, sourceFormat, requestContext, qwenPreModelTextChunking in
                    guard let resolvedProfileName = await host.resolvedRequestedVoiceProfileName(profileName) else {
                        let errorMessage = await host.missingVoiceProfileNameMessage(for: "the live speech request")
                        throw ServerConfigurationError(errorMessage)
                    }

                    return try await host.queueSpeechLive(
                        text: text,
                        profileName: resolvedProfileName,
                        textProfileID: textProfileID,
                        normalizationContext: normalizationContext,
                        sourceFormat: sourceFormat,
                        requestContext: requestContext,
                        qwenPreModelTextChunking: qwenPreModelTextChunking,
                    )
                },
                setDefaultVoiceProfileName: { profileName in
                    try await host.setDefaultVoiceProfileName(profileName)
                },
                clearDefaultVoiceProfileName: {
                    try await host.clearDefaultVoiceProfileName()
                },
                switchSpeechBackend: { speechBackend in
                    _ = try await host.switchSpeechBackend(to: speechBackend)
                    return await host.hostStateSnapshot()
                },
                reloadModels: {
                    _ = try await host.reloadModels()
                    return await host.hostStateSnapshot()
                },
                unloadModels: {
                    _ = try await host.unloadModels()
                    return await host.hostStateSnapshot()
                },
                pausePlayback: {
                    let response = try await host.pausePlayback()
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                resumePlayback: {
                    let response = try await host.resumePlayback()
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                clearPlaybackQueue: {
                    let response = try await host.clearQueue()
                    return response.clearedCount
                },
                cancelPlaybackRequest: { requestID in
                    let response = try await host.cancelQueuedOrActiveRequest(requestID: requestID)
                    return response.cancelledRequestID
                },
            ),
        )
    }

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    _ = try await state.setDefaultVoiceProfileName("app-selected-default")
    #expect(await host.defaultVoiceProfileName() == "app-selected-default")

    try await state.clearDefaultVoiceProfileName()
    let overviewAfterClear = await MainActor.run { state.overview }
    #expect(overviewAfterClear.defaultVoiceProfileName == "configured-default")
    #expect(await host.defaultVoiceProfileName() == "configured-default")
    #expect(await host.resolvedRequestedVoiceProfileName(nil) == "configured-default")

    await host.shutdown()
}
