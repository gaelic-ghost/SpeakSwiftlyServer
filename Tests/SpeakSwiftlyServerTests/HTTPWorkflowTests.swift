import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing
import TextForSpeech

// MARK: - HTTP Workflow Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `routes expose health profiles and queued speech job lifecycle`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration(defaultVoiceProfileName: "default")
        let state = await MainActor.run { EmbeddedServer() }
        let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("profiles", isDirectory: true)
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeConfigurationStore: .init(
                environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
                activeRuntimeSpeechBackend: .qwen3,
            ),
            state: state,
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

            let runtimeHostResponse = try await client.execute(uri: "/runtime/host", method: .get)
            let runtimeHostJSON = try jsonObject(from: runtimeHostResponse.body)
            #expect(runtimeHostJSON["default_voice_profile_name"] as? String == "default")
            let runtimeRefresh = try #require(runtimeHostJSON["runtime_refresh"] as? [String: Any])
            #expect((runtimeRefresh["sequence_id"] as? Int ?? 0) > 0)
            #expect(runtimeRefresh["source"] as? String == "runtime_overview")
            #expect((runtimeRefresh["started_at"] as? String)?.isEmpty == false)
            #expect((runtimeRefresh["generation_queue_refreshed_at"] as? String)?.isEmpty == false)
            #expect((runtimeRefresh["playback_queue_refreshed_at"] as? String)?.isEmpty == false)
            #expect((runtimeRefresh["playback_state_refreshed_at"] as? String)?.isEmpty == false)
            #expect((runtimeRefresh["completed_at"] as? String)?.isEmpty == false)

            let runtimeConfigResponse = try await client.execute(uri: "/runtime/configuration", method: .get)
            let runtimeConfigJSON = try jsonObject(from: runtimeConfigResponse.body)
            #expect(runtimeConfigResponse.status == .ok)
            #expect(runtimeConfigJSON["active_runtime_speech_backend"] as? String == "qwen3")
            #expect(runtimeConfigJSON["next_runtime_speech_backend"] as? String == "qwen3")
            #expect(runtimeConfigJSON["persisted_configuration_state"] as? String == "missing")

            let updateRuntimeConfigResponse = try await client.execute(
                uri: "/runtime/configuration",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"marvis"}"#),
            )
            let updateRuntimeConfigJSON = try jsonObject(from: updateRuntimeConfigResponse.body)
            #expect(updateRuntimeConfigResponse.status == .ok)
            #expect(updateRuntimeConfigJSON["active_runtime_speech_backend"] as? String == "qwen3")
            #expect(updateRuntimeConfigJSON["next_runtime_speech_backend"] as? String == "marvis")
            #expect(updateRuntimeConfigJSON["persisted_speech_backend"] as? String == "marvis")
            #expect(updateRuntimeConfigJSON["persisted_configuration_state"] as? String == "loaded")

            let updateChatterboxRuntimeConfigResponse = try await client.execute(
                uri: "/runtime/configuration",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"chatterbox_turbo"}"#),
            )
            let updateChatterboxRuntimeConfigJSON = try jsonObject(from: updateChatterboxRuntimeConfigResponse.body)
            #expect(updateChatterboxRuntimeConfigResponse.status == .ok)
            #expect(updateChatterboxRuntimeConfigJSON["next_runtime_speech_backend"] as? String == "chatterbox_turbo")
            #expect(updateChatterboxRuntimeConfigJSON["persisted_speech_backend"] as? String == "chatterbox_turbo")

            let updateLegacyQwenRuntimeConfigResponse = try await client.execute(
                uri: "/runtime/configuration",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"qwen3_custom_voice"}"#),
            )
            let updateLegacyQwenRuntimeConfigJSON = try jsonObject(from: updateLegacyQwenRuntimeConfigResponse.body)
            #expect(updateLegacyQwenRuntimeConfigResponse.status == .ok)
            #expect(updateLegacyQwenRuntimeConfigJSON["next_runtime_speech_backend"] as? String == "qwen3")
            #expect(updateLegacyQwenRuntimeConfigJSON["persisted_speech_backend"] as? String == "qwen3")

            let profilesResponse = try await client.execute(uri: "/voices", method: .get)
            let profilesJSON = try jsonObject(from: profilesResponse.body)
            let profiles = try #require(profilesJSON["profiles"] as? [[String: Any]])
            #expect(profiles.count == 1)
            #expect(profiles.first?["profile_name"] as? String == "default")

            let createTextProfileResponse = try await client.execute(
                uri: "/text-profiles/stored",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(
                    #"{"name":"Swift Docs","replacements":[{"id":"replace-1","text":"SPM","replacement":"Swift Package Manager","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["swift_source"],"priority":3}]}"#,
                ),
            )
            let createTextProfileJSON = try jsonObject(from: createTextProfileResponse.body)
            let createdTextProfile = try #require(createTextProfileJSON["profile"] as? [String: Any])
            #expect(createTextProfileResponse.status == .ok)
            #expect(createdTextProfile["profile_id"] as? String == "swift-docs")

            let textProfilesResponse = try await client.execute(uri: "/text-profiles", method: .get)
            let textProfilesJSON = try jsonObject(from: textProfilesResponse.body)
            let textProfiles = try #require(textProfilesJSON["text_profiles"] as? [String: Any])
            #expect(textProfiles["built_in_style"] as? String == "balanced")
            let storedTextProfiles = try #require(textProfiles["stored_profiles"] as? [[String: Any]])
            #expect(storedTextProfiles.contains { $0["profile_id"] as? String == "swift-docs" })

            let textProfileStyleResponse = try await client.execute(uri: "/text-profiles/style", method: .get)
            let textProfileStyleJSON = try jsonObject(from: textProfileStyleResponse.body)
            let textProfileStyle = try #require(textProfileStyleJSON["text_profile_style"] as? [String: Any])
            #expect(textProfileStyle["built_in_style"] as? String == "balanced")

            let loadTextProfilesResponse = try await client.execute(uri: "/text-profiles/load", method: .post)
            let loadTextProfilesJSON = try jsonObject(from: loadTextProfilesResponse.body)
            let loadedTextProfiles = try #require(loadTextProfilesJSON["text_profiles"] as? [String: Any])
            let loadedStoredProfiles = try #require(loadedTextProfiles["stored_profiles"] as? [[String: Any]])
            #expect(loadedStoredProfiles.contains { $0["profile_id"] as? String == "swift-docs" })

            let saveTextProfilesResponse = try await client.execute(uri: "/text-profiles/save", method: .post)
            let saveTextProfilesJSON = try jsonObject(from: saveTextProfilesResponse.body)
            let savedTextProfiles = try #require(saveTextProfilesJSON["text_profiles"] as? [String: Any])
            let savedStoredProfiles = try #require(savedTextProfiles["stored_profiles"] as? [[String: Any]])
            #expect(savedStoredProfiles.contains { $0["profile_id"] as? String == "swift-docs" })

            let compactTextProfileStyleResponse = try await client.execute(
                uri: "/text-profiles/style",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"built_in_style":"compact"}"#),
            )
            let compactTextProfileStyleJSON = try jsonObject(from: compactTextProfileStyleResponse.body)
            let compactTextProfiles = try #require(compactTextProfileStyleJSON["text_profiles"] as? [String: Any])
            #expect(compactTextProfiles["built_in_style"] as? String == "compact")

            let renameTextProfileResponse = try await client.execute(
                uri: "/text-profiles/stored/swift-docs/name",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"name":"Operator"}"#),
            )
            let renameTextProfileJSON = try jsonObject(from: renameTextProfileResponse.body)
            let renamedTextProfile = try #require(renameTextProfileJSON["profile"] as? [String: Any])
            #expect(renameTextProfileResponse.status == .ok)
            #expect(renamedTextProfile["profile_id"] as? String == "swift-docs")
            #expect(renamedTextProfile["name"] as? String == "Operator")

            let useTextProfileResponse = try await client.execute(
                uri: "/text-profiles/active",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"profile_id":"swift-docs"}"#),
            )
            let useTextProfileJSON = try jsonObject(from: useTextProfileResponse.body)
            let activeTextProfile = try #require(useTextProfileJSON["profile"] as? [String: Any])
            #expect(activeTextProfile["profile_id"] as? String == "swift-docs")
            #expect(activeTextProfile["name"] as? String == "Operator")

            let effectiveTextProfileResponse = try await client.execute(uri: "/text-profiles/effective/swift-docs", method: .get)
            let effectiveTextProfileJSON = try jsonObject(from: effectiveTextProfileResponse.body)
            let effectiveTextProfile = try #require(effectiveTextProfileJSON["profile"] as? [String: Any])
            let effectiveReplacements = try #require(effectiveTextProfile["replacements"] as? [[String: Any]])
            #expect(effectiveReplacements.contains { $0["id"] as? String == "replace-1" })

            let removeTextReplacementResponse = try await client.execute(
                uri: "/text-profiles/stored/swift-docs/replacements/replace-1",
                method: .delete,
            )
            let removeTextReplacementJSON = try jsonObject(from: removeTextReplacementResponse.body)
            let trimmedTextProfile = try #require(removeTextReplacementJSON["profile"] as? [String: Any])
            let trimmedReplacements = try #require(trimmedTextProfile["replacements"] as? [[String: Any]])
            #expect(trimmedReplacements.isEmpty)
            let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
            #expect(persistenceActionCounts.load == 1)
            #expect(persistenceActionCounts.save == 1)

            let cloneResponse = try await client.execute(
                uri: "/voices/from-audio",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(
                    #"{"profile_name":"clone-default","vibe":"femme","reference_audio_path":"./Fixtures/reference.wav","transcript":"Cloned route test transcript.","cwd":"/tmp/http-clone-cwd"}"#,
                ),
            )
            let cloneJSON = try jsonObject(from: cloneResponse.body)
            let cloneJobID = try #require(cloneJSON["request_id"] as? String)
            #expect(cloneResponse.status == .accepted)
            _ = try await waitForJobSnapshot(cloneJobID, on: host)

            let cloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
            #expect(cloneInvocation.profileName == "clone-default")
            #expect(cloneInvocation.referenceAudioPath == "./Fixtures/reference.wav")
            #expect(cloneInvocation.transcript == "Cloned route test transcript.")
            #expect(cloneInvocation.cwd == "/tmp/http-clone-cwd")

            let renameResponse = try await client.execute(
                uri: "/voices/clone-default/name",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"new_profile_name":"clone-renamed"}"#),
            )
            let renameJSON = try jsonObject(from: renameResponse.body)
            let renameJobID = try #require(renameJSON["request_id"] as? String)
            #expect(renameResponse.status == .accepted)
            _ = try await waitForJobSnapshot(renameJobID, on: host)

            let renameInvocation = try #require(await runtime.latestRenameProfileInvocation())
            #expect(renameInvocation.profileName == "clone-default")
            #expect(renameInvocation.newProfileName == "clone-renamed")

            let rerollResponse = try await client.execute(
                uri: "/voices/clone-renamed/reroll",
                method: .post,
            )
            let rerollJSON = try jsonObject(from: rerollResponse.body)
            let rerollJobID = try #require(rerollJSON["request_id"] as? String)
            #expect(rerollResponse.status == .accepted)
            _ = try await waitForJobSnapshot(rerollJobID, on: host)

            let rerollInvocation = try #require(await runtime.latestRerollProfileInvocation())
            #expect(rerollInvocation.profileName == "clone-renamed")

            let refreshedProfilesResponse = try await client.execute(uri: "/voices", method: .get)
            let refreshedProfilesJSON = try jsonObject(from: refreshedProfilesResponse.body)
            let refreshedProfiles = try #require(refreshedProfilesJSON["profiles"] as? [[String: Any]])
            #expect(refreshedProfiles.contains { $0["profile_name"] as? String == "clone-renamed" })
            #expect(refreshedProfiles.contains { $0["profile_name"] as? String == "clone-default" } == false)

            let speakResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Route test","text_profile_id":"swift-docs","request_context":{"source":"http","app":"SpeakSwiftlyServerTests","project":"SpeakSwiftlyServer","topic":"route-coverage","attributes":{"surface":"http"}},"cwd":"./Sources","repo_root":"../SpeakSwiftlyServer","text_format":"markdown","nested_source_format":"swift_source","source_format":"python_source"}"#),
            )
            let speakJSON = try jsonObject(from: speakResponse.body)
            let speakJobID = try #require(speakJSON["request_id"] as? String)
            #expect(speakResponse.status == .accepted)
            #expect((speakJSON["request_url"] as? String)?.contains(speakJobID) == true)
            #expect((speakJSON["events_url"] as? String)?.contains(speakJobID) == true)
            #expect((speakJSON["request_url"] as? String)?.hasPrefix("http://") == true)
            let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
            #expect(
                queuedSpeechInvocation.normalizationContext
                    == SpeechNormalizationContext(
                        cwd: "./Sources",
                        repoRoot: "../SpeakSwiftlyServer",
                        textFormat: .markdown,
                        nestedSourceFormat: .swift,
                    ),
            )
            #expect(queuedSpeechInvocation.textProfileID == "swift-docs")
            #expect(queuedSpeechInvocation.sourceFormat == .python)
            #expect(
                queuedSpeechInvocation.requestContext
                    == SpeakSwiftly.RequestContext(
                        source: "http",
                        app: "SpeakSwiftlyServerTests",
                        project: "SpeakSwiftlyServer",
                        topic: "route-coverage",
                        attributes: ["surface": "http"],
                    ),
            )
            #expect(queuedSpeechInvocation.profileName == "default")

            _ = try await waitForJobSnapshot(speakJobID, on: host)

            let jobsResponse = try await client.execute(uri: "/requests", method: .get)
            let jobsJSON = try jsonObject(from: jobsResponse.body)
            let jobs = try #require(jobsJSON["requests"] as? [[String: Any]])
            #expect(jobsResponse.status == .ok)
            #expect(jobs.contains { $0["request_id"] as? String == speakJobID })

            let foregroundJobResponse = try await client.execute(uri: "/requests/\(speakJobID)", method: .get)
            let foregroundJobJSON = try jsonObject(from: foregroundJobResponse.body)
            #expect(foregroundJobResponse.status == .ok)
            #expect(foregroundJobJSON["request_id"] as? String == speakJobID)
            #expect(foregroundJobJSON["status"] as? String == "completed")
            let foregroundHistory = try #require(foregroundJobJSON["history"] as? [[String: Any]])
            #expect(foregroundHistory.contains { $0["event"] as? String == "started" })
            #expect(foregroundHistory.filter { $0["ok"] as? Bool == true }.count == 2)
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `runtime backend switch is accepted and visible while waiting for active work`() async throws {
        let runtime = MockRuntime(speakBehavior: .holdOpen)
        let configuration = testConfiguration(defaultVoiceProfileName: "default")
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

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let speakResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Keep the active lane busy"}"#),
            )
            let speakJSON = try jsonObject(from: speakResponse.body)
            let speakJobID = try #require(speakJSON["request_id"] as? String)
            #expect(speakResponse.status == .accepted)

            let switchResponse = try await client.execute(
                uri: "/runtime/backend",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"marvis"}"#),
            )
            let switchJSON = try jsonObject(from: switchResponse.body)
            let switchJobID = try #require(switchJSON["request_id"] as? String)
            #expect(switchResponse.status == .accepted)
            #expect((switchJSON["request_url"] as? String)?.contains(switchJobID) == true)

            let queuedTransition: RuntimeBackendTransitionSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
                let transition = await host.statusSnapshot().runtimeBackendTransition
                guard transition.requestID == switchJobID, transition.state == "queued" else {
                    return nil
                }

                return transition
            }
            #expect(queuedTransition.activeSpeechBackend == "qwen3")
            #expect(queuedTransition.requestedSpeechBackend == "marvis")
            #expect(queuedTransition.operation == "switch_speech_backend")
            #expect(queuedTransition.waitingReason == "waiting_for_active_request")

            await runtime.finishHeldSpeak(id: speakJobID)
            _ = try await waitForJobSnapshot(switchJobID, on: host)

            let finalHostResponse = try await client.execute(uri: "/runtime/host", method: .get)
            let finalHostJSON = try jsonObject(from: finalHostResponse.body)
            let finalTransition = try #require(finalHostJSON["runtime_backend_transition"] as? [String: Any])
            #expect(finalTransition["state"] as? String == "idle")
            #expect(finalTransition["active_speech_backend"] as? String == "marvis")
            let finalConfig = try #require(finalHostJSON["runtime_configuration"] as? [String: Any])
            #expect(finalConfig["active_runtime_speech_backend"] as? String == "marvis")
            #expect(finalConfig["next_runtime_speech_backend"] as? String == "qwen3")
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `speak route rejects unsupported format arguments clearly`() async throws {
        let runtime = MockRuntime()
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

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(
                    #"{"text":"Bad format","profile_name":"default","text_format":"totally_invalid","source_format":"not_a_real_source"}"#,
                ),
            )
            let responseJSON = try jsonObject(from: response.body)
            let error = try #require(responseJSON["error"] as? [String: Any])
            let message = try #require(error["message"] as? String)

            #expect(response.status == .badRequest)
            #expect(message.contains("text_format"))
            #expect(message.contains("totally_invalid"))
            #expect(message.contains("plain"))
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `speak route rejects missing profile when no server default is configured`() async throws {
        let runtime = MockRuntime()
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

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let response = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Route test without a profile"}"#),
            )
            let body = string(from: response.body)
            #expect(response.status == .badRequest)
            #expect(body.contains("did not include 'profile_name'"))
            #expect(body.contains("app.defaultVoiceProfileName"))
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `runtime routes reject unsupported speech backend clearly`() async throws {
        let runtime = MockRuntime()
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

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let persistResponse = try await client.execute(
                uri: "/runtime/configuration",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"totally_invalid"}"#),
            )
            let persistJSON = try jsonObject(from: persistResponse.body)
            let persistError = try #require(persistJSON["error"] as? [String: Any])
            let persistMessage = try #require(persistError["message"] as? String)
            #expect(persistResponse.status == .badRequest)
            #expect(persistMessage.contains("speech_backend"))
            #expect(persistMessage.contains("totally_invalid"))
            #expect(persistMessage.contains("qwen3"))
            #expect(persistMessage.contains("chatterbox_turbo"))
            #expect(persistMessage.contains("marvis"))
            #expect(persistMessage.contains("qwen3_custom_voice"))

            let switchResponse = try await client.execute(
                uri: "/runtime/backend",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"speech_backend":"totally_invalid"}"#),
            )
            let switchJSON = try jsonObject(from: switchResponse.body)
            let switchError = try #require(switchJSON["error"] as? [String: Any])
            let switchMessage = try #require(switchError["message"] as? String)
            #expect(switchResponse.status == .badRequest)
            #expect(switchMessage.contains("speech_backend"))
            #expect(switchMessage.contains("totally_invalid"))
            #expect(switchMessage.contains("qwen3"))
            #expect(switchMessage.contains("chatterbox_turbo"))
            #expect(switchMessage.contains("marvis"))
            #expect(switchMessage.contains("qwen3_custom_voice"))
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `runtime routes reject missing speech backend field clearly`() async throws {
        let runtime = MockRuntime()
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

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let persistResponse = try await client.execute(
                uri: "/runtime/configuration",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{}"#),
            )
            let persistBody = string(from: persistResponse.body)
            #expect(persistResponse.status == .badRequest)
            #expect(persistBody.contains("speech_backend"))

            let switchResponse = try await client.execute(
                uri: "/runtime/backend",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{}"#),
            )
            let switchBody = string(from: switchResponse.body)
            #expect(switchResponse.status == .badRequest)
            #expect(switchBody.contains("speech_backend"))
        }

        await host.shutdown()
    }
}
