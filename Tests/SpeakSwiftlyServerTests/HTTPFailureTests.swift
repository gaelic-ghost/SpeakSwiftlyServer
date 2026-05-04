import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - HTTP Failure Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `runtime degradation while speech jobs are in flight marks jobs degraded and rejects new work`() async throws {
        let runtime = MockRuntime(speakBehavior: .holdOpen)
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
        #expect(degradedHostState.generationQueue.activeRequest == nil)
        #expect(degradedHostState.generationQueue.activeRequests.isEmpty)
        #expect(degradedHostState.generationQueue.queuedRequests.isEmpty)
        #expect(degradedHostState.generationQueue.activeCount == 0)
        #expect(degradedHostState.generationQueue.queuedCount == 0)
        #expect(degradedHostState.runtimeRefresh?.source == "cached_worker_not_ready")

        let activeSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let snapshot = try await host.jobSnapshot(id: activeJobID)
            return snapshot.history.contains {
                guard case let .workerStatus(event) = $0 else { return false }

                return event.workerMode == "failed" && event.stage == "resident_model_failed"
            } ? snapshot : nil
        }
        #expect(activeSnapshot.terminalEvent == nil)

        let queuedSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            let snapshot = try await host.jobSnapshot(id: queuedJobID)
            return snapshot.history.contains {
                guard case let .workerStatus(event) = $0 else { return false }

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
    @Test func `profile mutation failure marks cache stale and fails job`() async throws {
        let runtime = MockRuntime(mutationRefreshBehavior: .leaveProfilesUnchanged)
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

        let jobID = try await host.submitCreateProfile(
            profileName: "bright-guide",
            vibe: .femme,
            text: "Hello there",
            voiceDescription: "Warm and bright",
            outputPath: nil,
            cwd: nil,
        )
        let snapshot = try await waitForJobSnapshot(jobID, on: host)

        switch snapshot.terminalEvent {
            case let .failed(failure):
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

    @available(macOS 14, *)
    @Test func `profile creation reconciliation rejects unrelated refresh-only changes`() async throws {
        let originalCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let runtime = MockRuntime(
            profiles: [
                SpeakSwiftly.ProfileSummary(
                    profileName: "bright-guide",
                    vibe: .femme,
                    createdAt: originalCreatedAt,
                    voiceDescription: "Existing voice",
                    sourceText: "Existing text",
                    transcriptSource: nil,
                    transcriptResolvedAt: nil,
                    transcriptionModelRepo: nil,
                ),
            ],
            mutationRefreshBehavior: .leaveProfilesUnchanged,
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
                    profileName: "bright-guide",
                    vibe: .femme,
                    createdAt: originalCreatedAt,
                    voiceDescription: "Existing voice",
                    sourceText: "Existing text",
                    transcriptSource: nil,
                    transcriptResolvedAt: nil,
                    transcriptionModelRepo: nil,
                ),
                SpeakSwiftly.ProfileSummary(
                    profileName: "external-addition",
                    vibe: .femme,
                    createdAt: originalCreatedAt.addingTimeInterval(30),
                    voiceDescription: "Unrelated external voice",
                    sourceText: "External text",
                    transcriptSource: nil,
                    transcriptResolvedAt: nil,
                    transcriptionModelRepo: nil,
                ),
            ]],
        )

        let jobID = try await host.submitCreateProfile(
            profileName: "bright-guide",
            vibe: .femme,
            text: "Hello there",
            voiceDescription: "Warm and bright",
            outputPath: nil,
            cwd: nil,
        )
        let snapshot = try await waitForJobSnapshot(jobID, on: host)

        switch snapshot.terminalEvent {
            case let .failed(failure):
                #expect(failure.code == "profile_refresh_mismatch")
            default:
                Issue.record("Expected create_voice_profile_from_description reconciliation to reject unrelated refresh-only changes when the target profile snapshot stayed unchanged.")
        }

        let status = await host.statusSnapshot()
        #expect(status.profileCacheState == "stale")

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `text profile routes surface transport failures as typed server errors`() async throws {
        let runtime = MockRuntime(
            textProfileTransportError: SpeakSwiftly.Error(
                code: .internalError,
                message: "Configured text-profile transport failure for tests.",
            ),
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

        let app = assembleHBApp(configuration: testHTTPConfig(testConfiguration()), host: host)
        try await app.test(.router) { client in
            let response = try await client.execute(uri: "/text-profiles", method: .get)
            let responseJSON = try jsonObject(from: response.body)
            let error = try #require(responseJSON["error"] as? [String: Any])
            let message = try #require(error["message"] as? String)

            #expect(response.status == .internalServerError)
            #expect(message.contains("Configured text-profile transport failure for tests"))
        }

        await host.shutdown()
    }
}
