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

// MARK: - Route and MCP Tests

/// Keep these lifecycle-heavy route and MCP tests serialized so Swift Testing
/// does not interleave independent hosts, MCP surfaces, and held-open requests.
@Suite(.serialized)
struct SpeakSwiftlyServerTests {

@available(macOS 14, *)
@Test func routesExposeHealthProfilesAndQueuedSpeechJobLifecycle() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        runtimeConfigurationStore: .init(
            environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
            activeRuntimeSpeechBackend: .qwen3
        ),
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

        let runtimeHostResponse = try await client.execute(uri: "/runtime/host", method: .get)
        let runtimeHostJSON = try jsonObject(from: runtimeHostResponse.body)
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
            body: byteBuffer(#"{"speech_backend":"marvis"}"#)
        )
        let updateRuntimeConfigJSON = try jsonObject(from: updateRuntimeConfigResponse.body)
        #expect(updateRuntimeConfigResponse.status == .ok)
        #expect(updateRuntimeConfigJSON["active_runtime_speech_backend"] as? String == "qwen3")
        #expect(updateRuntimeConfigJSON["next_runtime_speech_backend"] as? String == "marvis")
        #expect(updateRuntimeConfigJSON["persisted_speech_backend"] as? String == "marvis")
        #expect(updateRuntimeConfigJSON["persisted_configuration_state"] as? String == "loaded")

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
                #"{"id":"swift-docs","name":"Swift Docs","replacements":[{"id":"replace-1","text":"SPM","replacement":"Swift Package Manager","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["swift_source"],"priority":3}]}"#
            )
        )
        let createTextProfileJSON = try jsonObject(from: createTextProfileResponse.body)
        let createdTextProfile = try #require(createTextProfileJSON["profile"] as? [String: Any])
        #expect(createTextProfileResponse.status == .ok)
        #expect(createdTextProfile["id"] as? String == "swift-docs")

        let textProfilesResponse = try await client.execute(uri: "/text-profiles", method: .get)
        let textProfilesJSON = try jsonObject(from: textProfilesResponse.body)
        let textProfiles = try #require(textProfilesJSON["text_profiles"] as? [String: Any])
        let storedTextProfiles = try #require(textProfiles["stored_profiles"] as? [[String: Any]])
        #expect(storedTextProfiles.contains { $0["id"] as? String == "swift-docs" })

        let loadTextProfilesResponse = try await client.execute(uri: "/text-profiles/load", method: .post)
        let loadTextProfilesJSON = try jsonObject(from: loadTextProfilesResponse.body)
        let loadedTextProfiles = try #require(loadTextProfilesJSON["text_profiles"] as? [String: Any])
        let loadedStoredProfiles = try #require(loadedTextProfiles["stored_profiles"] as? [[String: Any]])
        #expect(loadedStoredProfiles.contains { $0["id"] as? String == "swift-docs" })

        let saveTextProfilesResponse = try await client.execute(uri: "/text-profiles/save", method: .post)
        let saveTextProfilesJSON = try jsonObject(from: saveTextProfilesResponse.body)
        let savedTextProfiles = try #require(saveTextProfilesJSON["text_profiles"] as? [String: Any])
        let savedStoredProfiles = try #require(savedTextProfiles["stored_profiles"] as? [[String: Any]])
        #expect(savedStoredProfiles.contains { $0["id"] as? String == "swift-docs" })

        let useTextProfileResponse = try await client.execute(
            uri: "/text-profiles/active",
            method: .put,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"profile":{"id":"operator","name":"Operator","replacements":[{"id":"replace-2","text":"MCP","replacement":"Model Context Protocol","match":"exact_phrase","phase":"after_built_ins","is_case_sensitive":false,"formats":[],"priority":2}]}}"#
            )
        )
        let useTextProfileJSON = try jsonObject(from: useTextProfileResponse.body)
        let activeTextProfile = try #require(useTextProfileJSON["profile"] as? [String: Any])
        #expect(activeTextProfile["id"] as? String == "operator")

        let effectiveTextProfileResponse = try await client.execute(uri: "/text-profiles/effective/swift-docs", method: .get)
        let effectiveTextProfileJSON = try jsonObject(from: effectiveTextProfileResponse.body)
        let effectiveTextProfile = try #require(effectiveTextProfileJSON["profile"] as? [String: Any])
        let effectiveReplacements = try #require(effectiveTextProfile["replacements"] as? [[String: Any]])
        #expect(effectiveReplacements.contains { $0["id"] as? String == "replace-1" })

        let removeTextReplacementResponse = try await client.execute(
            uri: "/text-profiles/stored/swift-docs/replacements/replace-1",
            method: .delete
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
                #"{"profile_name":"clone-default","vibe":"femme","reference_audio_path":"./Fixtures/reference.wav","transcript":"Cloned route test transcript.","cwd":"/tmp/http-clone-cwd"}"#
            )
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

        let speakResponse = try await client.execute(
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Route test","profile_name":"default","text_profile_name":"swift-docs","cwd":"./Sources","repo_root":"../SpeakSwiftlyServer","text_format":"markdown","nested_source_format":"swift_source","source_format":"python_source"}"#)
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
                    nestedSourceFormat: .swift
                )
        )
        #expect(queuedSpeechInvocation.textProfileName == "swift-docs")
        #expect(queuedSpeechInvocation.sourceFormat == .python)

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

// MARK: - MCP Tests

@available(macOS 14, *)
@Test func embeddedMCPRoutesListToolsAndReadSharedHostResources() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
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
        runtimeConfigurationStore: .init(
            environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
            activeRuntimeSpeechBackend: .qwen3
        ),
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
    let toolNames = Set(tools.compactMap { $0["name"] as? String })
    #expect(toolNames == Set(MCPToolCatalog.definitions.map(\.name)))
    #expect(tools.contains { $0["name"] as? String == "queue_speech_live" })
    #expect(tools.contains { $0["name"] as? String == "create_voice_profile_from_audio" })
    #expect(tools.contains { $0["name"] as? String == "get_runtime_configuration" })
    #expect(tools.contains { $0["name"] as? String == "set_runtime_configuration" })
    #expect(tools.contains { $0["name"] as? String == "get_runtime_overview" })

    let queueSpeechToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "queue_speech_live",
                    arguments: [
                        "text": "Inspect MCP resources",
                        "profile_name": "default",
                        "text_profile_name": "mcp-text",
                        "cwd": "./Tests",
                        "repo_root": "../SpeakSwiftlyServer",
                        "text_format": "cli_output",
                        "nested_source_format": "rust_source",
                        "source_format": "source_code",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let queueSpeechToolPayload = try mcpToolPayload(from: queueSpeechToolEnvelope)
    let requestID = try #require(queueSpeechToolPayload["request_id"] as? String)
    #expect(queueSpeechToolPayload["status_resource_uri"] as? String == "speak://runtime/overview")
    #expect(queueSpeechToolPayload["request_resource_uri"] as? String == "speak://requests/\(requestID)")
    let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
    #expect(
        queuedSpeechInvocation.normalizationContext
            == SpeechNormalizationContext(
                cwd: "./Tests",
                repoRoot: "../SpeakSwiftlyServer",
                textFormat: .cli,
                nestedSourceFormat: .rust
            )
    )
    #expect(queuedSpeechInvocation.textProfileName == "mcp-text")
    #expect(queuedSpeechInvocation.sourceFormat == .generic)

    let createCloneToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "create_voice_profile_from_audio",
                    arguments: [
                        "profile_name": "clone-from-mcp",
                        "vibe": "androgenous",
                        "reference_audio_path": "./Fixtures/mcp-reference.wav",
                        "transcript": "Imported from MCP",
                        "cwd": "/tmp/mcp-clone-cwd",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let createCloneToolPayload = try mcpToolPayload(from: createCloneToolEnvelope)
    let createCloneRequestID = try #require(createCloneToolPayload["request_id"] as? String)
    #expect(createCloneToolPayload["request_resource_uri"] as? String == "speak://requests/\(createCloneRequestID)")
    let createCloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
    #expect(createCloneInvocation.profileName == "clone-from-mcp")
    #expect(createCloneInvocation.vibe == .androgenous)
    #expect(createCloneInvocation.referenceAudioPath == "./Fixtures/mcp-reference.wav")
    #expect(createCloneInvocation.transcript == "Imported from MCP")
    #expect(createCloneInvocation.cwd == "/tmp/mcp-clone-cwd")

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
    let resourceURIs = Set(resources.compactMap { $0["uri"] as? String })
    #expect(resourceURIs == Set(MCPResourceCatalog.resources.map(\.uri)))
    #expect(resources.contains { $0["uri"] as? String == "speak://runtime/overview" })
    #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles" })
    #expect(resources.contains { $0["uri"] as? String == "speak://voices/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://playback/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://requests" })
    #expect(resources.contains { $0["uri"] as? String == "speak://runtime/configuration" })
    #expect(resources.contains { $0["uri"] as? String == "speak://runtime/status" })

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
    let templateURIs = Set(templates.compactMap { $0["uriTemplate"] as? String })
    #expect(templateURIs == Set(MCPResourceCatalog.templates.map(\.uriTemplate)))
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://voices/{profile_name}" })
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://text-profiles/stored/{profile_id}" })
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://requests/{request_id}" })

    let createTextProfileEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"id":"mcp-text","name":"MCP Text","replacements":[{"id":"mcp-replacement","text":"CLI","replacement":"command line interface","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["cli_output"],"priority":1}]}}}"#,
                sessionID: initializeSessionID
            )
        )
    )
    let createTextProfilePayload = try mcpToolPayload(from: createTextProfileEnvelope)
    #expect(createTextProfilePayload["id"] as? String == "mcp-text")

    let listTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "get_text_profiles_state",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let listTextProfilesPayload = try mcpToolPayload(from: listTextProfilesEnvelope)
    let listTextStoredProfiles = try #require(listTextProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(listTextStoredProfiles.contains { $0["id"] as? String == "mcp-text" })

    let loadTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "load_text_profiles",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let loadTextProfilesPayload = try mcpToolPayload(from: loadTextProfilesEnvelope)
    let loadedStoredProfiles = try #require(loadTextProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(loadedStoredProfiles.contains { $0["id"] as? String == "mcp-text" })

    let saveTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "save_text_profiles",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let saveTextProfilesPayload = try mcpToolPayload(from: saveTextProfilesEnvelope)
    let savedStoredProfiles = try #require(saveTextProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(savedStoredProfiles.contains { $0["id"] as? String == "mcp-text" })
    let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
    #expect(persistenceActionCounts.load == 1)
    #expect(persistenceActionCounts.save == 1)

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
    let promptNames = Set(prompts.compactMap { $0["name"] as? String })
    #expect(promptNames == Set(MCPPromptCatalog.prompts.map(\.name)))
    #expect(prompts.contains { $0["name"] as? String == "draft_profile_voice_description" })
    #expect(prompts.contains { $0["name"] as? String == "draft_text_profile" })
    #expect(prompts.contains { $0["name"] as? String == "draft_text_replacement" })
    #expect(prompts.contains { $0["name"] as? String == "draft_queue_playback_notice" })
    #expect(prompts.contains { $0["name"] as? String == "choose_surface_action" })

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

    let textProfilePromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "draft_text_profile",
                    arguments: [
                        "user_goal": "expand acronyms in technical speech",
                        "profile_scope": "swift package walkthroughs",
                        "format_focus": "swift_source",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilePromptResult = try #require(mcpResultPayload(from: textProfilePromptEnvelope))
    let textProfilePromptMessages = try #require(textProfilePromptResult["messages"] as? [[String: Any]])
    let textProfilePromptContent = try #require(textProfilePromptMessages.first?["content"] as? [String: Any])
    #expect((textProfilePromptContent["text"] as? String)?.contains("expand acronyms in technical speech") == true)

    let statusToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(name: "get_runtime_overview", arguments: [:]),
                sessionID: initializeSessionID
            )
        )
    )
    let statusToolPayload = try mcpToolPayload(from: statusToolEnvelope)
    #expect(statusToolPayload["worker_mode"] as? String == "ready")
    let statusRuntimeConfiguration = try #require(statusToolPayload["runtime_configuration"] as? [String: Any])
    #expect(statusRuntimeConfiguration["active_runtime_speech_backend"] as? String == "qwen3")
    let transports = try #require(statusToolPayload["transports"] as? [[String: Any]])
    #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })

    let getRuntimeConfigEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(name: "get_runtime_configuration", arguments: [:]),
                sessionID: initializeSessionID
            )
        )
    )
    let getRuntimeConfigPayload = try mcpToolPayload(from: getRuntimeConfigEnvelope)
    #expect(getRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3")
    #expect(getRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "qwen3")

    let setRuntimeConfigEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "set_runtime_configuration",
                    arguments: ["speech_backend": "marvis"]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let setRuntimeConfigPayload = try mcpToolPayload(from: setRuntimeConfigEnvelope)
    #expect(setRuntimeConfigPayload["active_runtime_speech_backend"] as? String == "qwen3")
    #expect(setRuntimeConfigPayload["next_runtime_speech_backend"] as? String == "marvis")
    #expect(setRuntimeConfigPayload["persisted_speech_backend"] as? String == "marvis")

    let runtimeResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://runtime/overview"),
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
    let runtimeRefresh = try #require(runtimePayload["runtime_refresh"] as? [String: Any])
    #expect((runtimeRefresh["sequence_id"] as? Int ?? 0) > 0)
    #expect(runtimeRefresh["source"] as? String == "runtime_overview")
    let runtimeConfiguration = try #require(runtimePayload["runtime_configuration"] as? [String: Any])
    #expect(runtimeConfiguration["next_runtime_speech_backend"] as? String == "marvis")

    let runtimeStatusResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://runtime/status"),
                sessionID: initializeSessionID
            )
        )
    )
    let runtimeStatusResourceResult = try #require(mcpResultPayload(from: runtimeStatusResourceEnvelope))
    let runtimeStatusContents = try #require(runtimeStatusResourceResult["contents"] as? [[String: Any]])
    let runtimeStatusText = try #require(runtimeStatusContents.first?["text"] as? String)
    let runtimeStatusPayload = try jsonObject(from: Data(runtimeStatusText.utf8))
    let runtimeStatus = try #require(runtimeStatusPayload["status"] as? [String: Any])
    #expect(runtimeStatus["speech_backend"] as? String == "qwen3")

    let runtimeConfigResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://runtime/configuration"),
                sessionID: initializeSessionID
            )
        )
    )
    let runtimeConfigResourceResult = try #require(mcpResultPayload(from: runtimeConfigResourceEnvelope))
    let runtimeConfigContents = try #require(runtimeConfigResourceResult["contents"] as? [[String: Any]])
    let runtimeConfigText = try #require(runtimeConfigContents.first?["text"] as? String)
    let runtimeConfigPayload = try jsonObject(from: Data(runtimeConfigText.utf8))
    #expect(runtimeConfigPayload["next_runtime_speech_backend"] as? String == "marvis")

    let jobsResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://requests"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobsResourceResult = try #require(mcpResultPayload(from: jobsResourceEnvelope))
    let jobsContents = try #require(jobsResourceResult["contents"] as? [[String: Any]])
    let jobsText = try #require(jobsContents.first?["text"] as? String)
    let jobsPayload = try #require(try JSONSerialization.jsonObject(with: Data(jobsText.utf8)) as? [[String: Any]])
    #expect(jobsPayload.contains { $0["request_id"] as? String == requestID })

    let profileDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://voices/default"),
                sessionID: initializeSessionID
            )
        )
    )
    let profileDetailResult = try #require(mcpResultPayload(from: profileDetailEnvelope))
    let profileDetailContents = try #require(profileDetailResult["contents"] as? [[String: Any]])
    let profileDetailText = try #require(profileDetailContents.first?["text"] as? String)
    let profileDetailPayload = try jsonObject(from: Data(profileDetailText.utf8))
    #expect(profileDetailPayload["profile_name"] as? String == "default")

    let textProfilesResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles"),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilesResourceResult = try #require(mcpResultPayload(from: textProfilesResourceEnvelope))
    let textProfilesContents = try #require(textProfilesResourceResult["contents"] as? [[String: Any]])
    let textProfilesText = try #require(textProfilesContents.first?["text"] as? String)
    let textProfilesPayload = try jsonObject(from: Data(textProfilesText.utf8))
    let storedProfilesPayload = try #require(textProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(storedProfilesPayload.contains { $0["id"] as? String == "mcp-text" })

    let textProfilesGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilesGuideResult = try #require(mcpResultPayload(from: textProfilesGuideEnvelope))
    let textProfilesGuideContents = try #require(textProfilesGuideResult["contents"] as? [[String: Any]])
    let textProfilesGuideText = try #require(textProfilesGuideContents.first?["text"] as? String)
    #expect(textProfilesGuideText.contains("text_profile_name"))

    let voiceProfilesGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://voices/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let voiceProfilesGuideResult = try #require(mcpResultPayload(from: voiceProfilesGuideEnvelope))
    let voiceProfilesGuideContents = try #require(voiceProfilesGuideResult["contents"] as? [[String: Any]])
    let voiceProfilesGuideText = try #require(voiceProfilesGuideContents.first?["text"] as? String)
    #expect(voiceProfilesGuideText.contains("create_voice_profile_from_audio"))
    #expect(voiceProfilesGuideText.contains("queue_speech_live"))

    let playbackGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://playback/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let playbackGuideResult = try #require(mcpResultPayload(from: playbackGuideEnvelope))
    let playbackGuideContents = try #require(playbackGuideResult["contents"] as? [[String: Any]])
    let playbackGuideText = try #require(playbackGuideContents.first?["text"] as? String)
    #expect(playbackGuideText.contains("cancel_request"))
    #expect(playbackGuideText.contains("clear_playback_queue"))

    let chooseActionPromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "choose_surface_action",
                    arguments: [
                        "user_goal": "Help the user decide whether to clone a voice or create a synthetic profile.",
                        "current_context": "The user has not provided reference audio yet.",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let chooseActionPromptResult = try #require(mcpResultPayload(from: chooseActionPromptEnvelope))
    let chooseActionPromptMessages = try #require(chooseActionPromptResult["messages"] as? [[String: Any]])
    let chooseActionPromptContent = try #require(chooseActionPromptMessages.first?["content"] as? [String: Any])
    let chooseActionPromptText = try #require(chooseActionPromptContent["text"] as? String)
    #expect(chooseActionPromptText.contains("action_type"))
    #expect(chooseActionPromptText.contains("create_voice_profile_from_description"))

    let storedTextProfileEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/stored/mcp-text"),
                sessionID: initializeSessionID
            )
        )
    )
    let storedTextProfileResult = try #require(mcpResultPayload(from: storedTextProfileEnvelope))
    let storedTextProfileContents = try #require(storedTextProfileResult["contents"] as? [[String: Any]])
    let storedTextProfileText = try #require(storedTextProfileContents.first?["text"] as? String)
    let storedTextProfilePayload = try jsonObject(from: Data(storedTextProfileText.utf8))
    #expect(storedTextProfilePayload["id"] as? String == "mcp-text")

    let jobDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://requests/\(requestID)"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobDetailResult = try #require(mcpResultPayload(from: jobDetailEnvelope))
    let jobDetailContents = try #require(jobDetailResult["contents"] as? [[String: Any]])
    let jobDetailText = try #require(jobDetailContents.first?["text"] as? String)
    let jobDetailPayload = try jsonObject(from: Data(jobDetailText.utf8))
    #expect(jobDetailPayload["request_id"] as? String == requestID)

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

    await runtime.finishHeldSpeak(id: requestID)
    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedMCPSupportsMultipleIndependentSessions() async throws {
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

    let firstInitializeResponse = await mcpSurface.handle(
        mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-first"))
    )
    let firstSessionID = try #require(mcpSessionID(from: firstInitializeResponse))
    try await drainMCPResponse(firstInitializeResponse)

    let secondInitializeResponse = await mcpSurface.handle(
        mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-second"))
    )
    let secondSessionID = try #require(mcpSessionID(from: secondInitializeResponse))
    try await drainMCPResponse(secondInitializeResponse)

    #expect(firstSessionID != secondSessionID)

    let firstInitializedNotification = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: firstSessionID
        )
    )
    #expect(mcpStatusCode(from: firstInitializedNotification) == 202)

    let secondInitializedNotification = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: secondSessionID
        )
    )
    #expect(mcpStatusCode(from: secondInitializedNotification) == 202)

    let firstStatusEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpRuntimeOverviewToolRequestJSON(),
                sessionID: firstSessionID
            )
        )
    )
    let firstStatusPayload = try mcpToolPayload(from: firstStatusEnvelope)
    #expect(firstStatusPayload["worker_mode"] as? String == "ready")

    let secondToolsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListToolsRequestJSON(),
                sessionID: secondSessionID
            )
        )
    )
    let secondToolsResult = try #require(mcpResultPayload(from: secondToolsEnvelope))
    let secondTools = try #require(secondToolsResult["tools"] as? [[String: Any]])
    #expect(secondTools.contains { $0["name"] as? String == "get_runtime_overview" })

    let deleteFirstSessionResponse = await mcpSurface.handle(
        mcpDELETERequest(sessionID: firstSessionID)
    )
    #expect(mcpStatusCode(from: deleteFirstSessionResponse) == 200)

    let deletedSessionResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpRuntimeOverviewToolRequestJSON(),
            sessionID: firstSessionID
        )
    )
    #expect(mcpStatusCode(from: deletedSessionResponse) == 404)

    let survivingSessionEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpRuntimeOverviewToolRequestJSON(),
                sessionID: secondSessionID
            )
        )
    )
    let survivingSessionPayload = try mcpToolPayload(from: survivingSessionEnvelope)
    #expect(survivingSessionPayload["worker_mode"] as? String == "ready")

    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func speakRouteRejectsUnsupportedFormatArgumentsClearly() async throws {
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
        let response = try await client.execute(
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"text":"Bad format","profile_name":"default","text_format":"totally_invalid","source_format":"not_a_real_source"}"#
            )
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
@Test func embeddedMCPRejectsUnsupportedFormatArgumentsClearly() async throws {
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

    let errorEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "queue_speech_live",
                    arguments: [
                        "text": "Bad format",
                        "profile_name": "default",
                        "text_format": "totally_invalid",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let error = try #require(errorEnvelope["error"] as? [String: Any])
    let message = try #require(error["message"] as? String)
    #expect(message.contains("text_format"))
    #expect(message.contains("totally_invalid"))
    #expect(message.contains("plain"))

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
                body: mcpSubscribeResourceRequestJSON(uri: "speak://runtime/overview"),
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
    #expect(notificationParams["uri"] as? String == "speak://runtime/overview")

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
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Hold the line","profile_name":"default"}"#)
        )
        let activeJobID = try #require(try jsonObject(from: activeResponse.body)["request_id"] as? String)

        let queuedResponse = try await client.execute(
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue this request","profile_name":"default"}"#)
        )
        let queuedJobID = try #require(try jsonObject(from: queuedResponse.body)["request_id"] as? String)

        let queueResponse = try await client.execute(uri: "/generation/queue", method: .get)
        let queueJSON = try jsonObject(from: queueResponse.body)
        #expect(queueResponse.status == .ok)
        #expect(queueJSON["queue_type"] as? String == "generation")
        let activeRequest = try #require(queueJSON["active_request"] as? [String: Any])
        #expect(activeRequest["id"] as? String == activeJobID)
        let activeRequests = try #require(queueJSON["active_requests"] as? [[String: Any]])
        #expect(activeRequests.count == 1)
        #expect(activeRequests.first?["id"] as? String == activeJobID)
        let queuedRequests = try #require(queueJSON["queue"] as? [[String: Any]])
        #expect(queuedRequests.count == 1)
        #expect(queuedRequests.first?["id"] as? String == queuedJobID)
        #expect(queuedRequests.first?["queue_position"] as? Int == 1)

        let playbackStateResponse = try await client.execute(uri: "/playback/state", method: .get)
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

        let playbackQueueResponse = try await client.execute(uri: "/playback/queue", method: .get)
        let playbackQueueJSON = try jsonObject(from: playbackQueueResponse.body)
        #expect(playbackQueueResponse.status == .ok)
        #expect(playbackQueueJSON["queue_type"] as? String == "playback")
        #expect((playbackQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
        #expect((playbackQueueJSON["active_requests"] as? [[String: Any]])?.first?["id"] as? String == activeJobID)
        #expect((playbackQueueJSON["queue"] as? [[String: Any]])?.isEmpty == true)

        let cancelResponse = try await client.execute(uri: "/playback/requests/\(queuedJobID)", method: .delete)
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
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue another request","profile_name":"default"}"#)
        )
        let anotherQueuedJobID = try #require(try jsonObject(from: anotherQueuedResponse.body)["request_id"] as? String)

        let clearResponse = try await client.execute(uri: "/playback/queue", method: .delete)
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

        let emptyQueueResponse = try await client.execute(uri: "/generation/queue", method: .get)
        let emptyQueueJSON = try jsonObject(from: emptyQueueResponse.body)
        let remainingQueue = try #require(emptyQueueJSON["queue"] as? [[String: Any]])
        #expect(remainingQueue.isEmpty)
        #expect((emptyQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
        #expect((emptyQueueJSON["active_requests"] as? [[String: Any]])?.first?["id"] as? String == activeJobID)
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
            uri: "/speech/live",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Too soon","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        #expect(speakResponse.status == .serviceUnavailable)
        let speakError = try #require(speakJSON["error"] as? [String: Any])
        #expect((speakError["message"] as? String)?.contains("cannot accept new work") == true)

        let missingJob = try await client.execute(uri: "/requests/missing-job", method: .get)
        let missingJSON = try jsonObject(from: missingJob.body)
        #expect(missingJob.status == .notFound)
        let missingJobError = try #require(missingJSON["error"] as? [String: Any])
        #expect((missingJobError["message"] as? String)?.contains("expired from in-memory retention") == true)

        let missingEvents = try await client.execute(uri: "/requests/missing-job/events", method: .get)
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

        let statusResponse = try await client.execute(uri: "/runtime/host", method: .get)
        let statusJSON = try jsonObject(from: statusResponse.body)
        #expect(statusResponse.status == .ok)
        #expect(statusJSON["worker_mode"] as? String == "failed")
        #expect(statusJSON["worker_stage"] as? String == "resident_model_failed")
        #expect((statusJSON["worker_failure_summary"] as? String)?.contains("startup failure") == true)

        let speakResponse = try await client.execute(
            uri: "/speech/live",
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
