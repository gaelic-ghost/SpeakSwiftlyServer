import Foundation
import SpeakSwiftly
import Testing
@testable import SpeakSwiftlyServer

// MARK: - HTTP Failure Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func runtimeDegradationWhileSpeechJobsAreInFlightMarksJobsDegradedAndRejectsNewWork() async throws {
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

        let degradedHostState = await host.hostStateSnapshot()
        #expect(degradedHostState.playback.state == "idle")
        #expect(degradedHostState.playbackQueue.activeRequest == nil)
        #expect(degradedHostState.runtimeRefresh?.source == "cached_worker_not_ready")

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
            runtimeConfigurationStore: testRuntimeConfigurationStore(),
            state: state
        )

        await host.start()
        await runtime.publishStatus(.residentModelReady)
        try await waitUntilReady(host)

        let jobID = try await host.submitCreateProfile(
            profileName: "bright-guide",
            vibe: .femme,
            text: "Hello there",
            voiceDescription: "Warm and bright",
            outputPath: nil,
            cwd: nil
        )
        let snapshot = try await waitForJobSnapshot(jobID, on: host)

        switch snapshot.terminalEvent {
        case .failed(let failure):
            #expect(failure.code == "profile_refresh_mismatch")
            #expect(failure.message.contains("could not confirm the profile list"))
        default:
            Issue.record("Expected create_voice_profile_from_description reconciliation failure to produce a failed terminal event.")
        }

        let status = await host.statusSnapshot()
        #expect(status.profileCacheState == "stale")
        #expect(status.profileCacheWarning?.contains("could not confirm the refreshed profile list") == true)

        await host.shutdown()
    }
}
