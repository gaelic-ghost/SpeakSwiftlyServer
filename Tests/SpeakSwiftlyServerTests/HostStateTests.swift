import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Host State Tests

@available(macOS 14, *)
@Test func `state completes queued speech jobs and prunes expired entries`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
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
    let state = await MainActor.run { ServerState() }
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
    let state = await MainActor.run { ServerState() }
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
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-mcp",
            title: "SpeakSwiftly",
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
    let state = await MainActor.run { ServerState() }
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
    let state = await MainActor.run { ServerState() }
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
@Test func `state projects cached voice profiles and forwards playback controls`() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
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

    let defaultVoiceProfileName = try await state.setDefaultVoiceProfileName("default")
    #expect(defaultVoiceProfileName == "default")
    let overviewAfterSet = await MainActor.run { state.overview }
    #expect(overviewAfterSet.defaultVoiceProfileName == "default")
    #expect(await host.defaultVoiceProfileName() == "default")
    #expect(await host.resolvedRequestedVoiceProfileName(nil) == "default")

    try await state.clearDefaultVoiceProfileName()
    let overviewAfterClear = await MainActor.run { state.overview }
    #expect(overviewAfterClear.defaultVoiceProfileName == nil)
    #expect(await host.defaultVoiceProfileName() == nil)
    #expect(await host.resolvedRequestedVoiceProfileName(nil) == nil)

    let switchedSnapshot = try await state.switchSpeechBackend(to: .marvis)
    #expect(switchedSnapshot.runtimeConfiguration.activeRuntimeSpeechBackend == "marvis")
    let runtimeConfigurationAfterSwitch = await MainActor.run { state.runtimeConfiguration }
    #expect(runtimeConfigurationAfterSwitch.activeRuntimeSpeechBackend == "marvis")

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
@Test func `clearing app managed default voice profile falls back to configured default`() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration(defaultVoiceProfileName: "configured-default")
    let state = await MainActor.run { ServerState() }
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
