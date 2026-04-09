import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - End-to-End Tests

/// Keep the suite type name stable so Xcode test plans can target it directly.
@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1",
        "Set SPEAKSWIFTLYSERVER_E2E=1 to run live end-to-end coverage."
    )
)
struct SpeakSwiftlyServerE2ETests {
    // MARK: Test Fixtures

    private static let testingProfileText = "Hello there from SpeakSwiftlyServer end-to-end coverage."
    private static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."
    static let testingCloneSourceText = """
    This imported reference audio should let SpeakSwiftlyServer build a clone profile for end to end coverage with a clean transcript and steady speech.
    """
    private static let testingPlaybackText = """
    Hello from the real resident SpeakSwiftlyServer playback path. This end to end test uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
    """

    // MARK: Sequential End-to-End Workflows

    @Test func httpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runVoiceDesignLane(using: .http)
    }

    @Test func httpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .http, transcriptMode: .provided)
    }

    @Test func httpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .http, transcriptMode: .inferred)
    }

    @Test func mcpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runVoiceDesignLane(using: .mcp)
    }

    @Test func mcpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .mcp, transcriptMode: .provided)
    }

    @Test func mcpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await Self.runCloneLane(using: .mcp, transcriptMode: .inferred)
    }

    @Test func httpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await Self.runMarvisTripletLane(using: .http)
    }

    @Test func mcpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await Self.runMarvisTripletLane(using: .mcp)
    }

    @Test func httpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await Self.runQueuedMarvisTripletLane(using: .http)
    }

    @Test func mcpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await Self.runQueuedMarvisTripletLane(using: .mcp)
    }

    @Test func httpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await Self.runRelativePathProfileAndCloneLane(using: .http)
    }

    @Test func mcpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await Self.runRelativePathProfileAndCloneLane(using: .mcp)
    }

    @Test func httpOperatorControlSurfaceCoversReadQueuePlaybackAndRemovalFlows() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59_600..<59_700),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            mcpEnabled: false
        )
        try server.start()
        defer { server.stop() }

        let client = E2EHTTPClient(baseURL: server.baseURL)
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let health = try decode(
            E2EHealthSnapshot.self,
            from: try await client.request(path: "/healthz", method: "GET").data
        )
        #expect(health.status == "ok")
        #expect(health.workerMode == "ready")
        #expect(health.workerReady)

        let readiness = try decode(
            E2EReadinessSnapshot.self,
            from: try await client.request(path: "/readyz", method: "GET").data
        )
        #expect(readiness.workerReady)

        let profileName = "http-operator-control-profile"
        try await Self.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            text: Self.testingProfileText,
            voiceDescription: Self.testingProfileVoiceDescription
        )

        let status = try decode(
            E2EStatusSnapshot.self,
            from: try await client.request(path: "/runtime/host", method: "GET").data
        )
        #expect(status.workerMode == "ready")
        #expect(status.cachedProfiles.contains { $0.profileName == profileName })
        #expect(status.transports.contains { $0.name == "http" && $0.state == "listening" })

        let longPlaybackText = String(repeating: Self.testingPlaybackText + " ", count: 12)
        let firstJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName
        )

        let playingState = try await Self.waitForPlaybackState(
            using: client,
            timeout: .seconds(180),
            matching: { $0.state == "playing" && $0.activeRequest?.id == firstJobID }
        )
        #expect(playingState.activeRequest?.op == "queue_speech_live")

        let paused = try decode(
            E2EPlaybackStateResponse.self,
            from: try await client.request(path: "/playback/pause", method: "POST").data
        )
        #expect(paused.playback.state == "paused")
        #expect(paused.playback.activeRequest?.id == firstJobID)

        let resumed = try decode(
            E2EPlaybackStateResponse.self,
            from: try await client.request(path: "/playback/resume", method: "POST").data
        )
        #expect(resumed.playback.state == "playing")
        #expect(resumed.playback.activeRequest?.id == firstJobID)

        let secondJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName
        )
        let queuedSecond = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                queue.queue.contains { $0.id == secondJobID }
            }
        )
        #expect(queuedSecond.queueType == "generation")
        #expect(queuedSecond.queue.contains { $0.id == secondJobID })

        let cancelled = try decode(
            E2EQueueCancellationResponse.self,
            from: try await client.request(path: "/queue/\(secondJobID)", method: "DELETE").data
        )
        #expect(cancelled.cancelledRequestID == secondJobID)

        let secondTerminal = try await waitForTerminalJob(
            id: secondJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        #expect(secondTerminal.terminalEvent?.cancelledRequestID == secondJobID)

        let thirdJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName
        )
        let fourthJobID = try await Self.submitSpeechJob(
            using: client,
            text: longPlaybackText,
            profileName: profileName
        )
        _ = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                let ids = Set(queue.queue.map(\.id))
                return ids.contains(thirdJobID) && ids.contains(fourthJobID)
            }
        )

        let cleared = try decode(
            E2EQueueClearedResponse.self,
            from: try await client.request(path: "/queue", method: "DELETE").data
        )
        #expect(cleared.clearedCount >= 2)

        _ = try await Self.waitForGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { $0.queue.isEmpty }
        )

        let thirdTerminal = try await waitForTerminalJob(
            id: thirdJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        let fourthTerminal = try await waitForTerminalJob(
            id: fourthJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        #expect(thirdTerminal.terminalEvent?.cancelledRequestID == thirdJobID)
        #expect(fourthTerminal.terminalEvent?.cancelledRequestID == fourthJobID)

        _ = try await waitForTerminalJob(
            id: firstJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )

        let removeResponse = try await client.request(path: "/voices/\(profileName)", method: "DELETE")
        #expect(removeResponse.statusCode == 202)
        let removeJobID = try decode(E2EJobCreatedResponse.self, from: removeResponse.data).jobID
        let removeSnapshot = try await waitForTerminalJob(
            id: removeJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        #expect(removeSnapshot.status == "completed")
        try await Self.assertProfileIsNotVisible(using: client, profileName: profileName)
    }

    @Test func httpTextProfileLifecycleCoversStoredActiveEffectiveAndPersistenceFlows() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59_700..<59_800),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: false
        )
        try server.start()
        defer { server.stop() }

        let client = E2EHTTPClient(baseURL: server.baseURL)
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let initialTextProfiles = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles", method: "GET").data
        ).textProfiles
        #expect(initialTextProfiles.baseProfile.id.isEmpty == false)
        #expect(initialTextProfiles.activeProfile.id.isEmpty == false)

        let createdStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored",
                method: "POST",
                jsonBody: [
                    "id": "http-text-profile",
                    "name": "HTTP Text Profile",
                    "replacements": [
                        Self.replacementJSON(
                            id: "expand-swift",
                            text: "SPM",
                            replacement: "Swift Package Manager",
                            formats: ["swift_source"]
                        ),
                    ],
                ]
            ).data
        ).profile
        #expect(createdStored.id == "http-text-profile")
        #expect(createdStored.replacements.count == 1)

        let storedRoute = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/stored/http-text-profile", method: "GET").data
        ).profile
        #expect(storedRoute.id == "http-text-profile")

        let replacedStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile",
                method: "PUT",
                jsonBody: [
                    "profile": [
                        "id": "http-text-profile",
                        "name": "HTTP Text Profile Updated",
                        "replacements": [
                            Self.replacementJSON(
                                id: "expand-swift",
                                text: "SPM",
                                replacement: "Swift Package Manager",
                                formats: ["swift_source"]
                            ),
                            Self.replacementJSON(
                                id: "expand-mcp",
                                text: "MCP",
                                replacement: "Model Context Protocol"
                            ),
                        ],
                    ],
                ]
            ).data
        ).profile
        #expect(replacedStored.name == "HTTP Text Profile Updated")
        #expect(replacedStored.replacements.count == 2)

        let storedWithAddedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements",
                method: "POST",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-tts",
                        text: "TTS",
                        replacement: "text to speech"
                    ),
                ]
            ).data
        ).profile
        #expect(storedWithAddedReplacement.replacements.contains { $0.id == "expand-tts" })

        let storedWithReplacedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements/expand-tts",
                method: "PUT",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-tts",
                        text: "TTS",
                        replacement: "text-to-speech",
                        phase: "after_built_ins"
                    ),
                ]
            ).data
        ).profile
        let replacedTTSRule = storedWithReplacedReplacement.replacements.first { $0.id == "expand-tts" }
        #expect(replacedTTSRule?.replacement == "text-to-speech")
        #expect(replacedTTSRule?.phase == "after_built_ins")

        let activeProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active",
                method: "PUT",
                jsonBody: [
                    "profile": [
                        "id": "http-session-profile",
                        "name": "HTTP Session Profile",
                        "replacements": [
                            Self.replacementJSON(
                                id: "expand-cwd",
                                text: "cwd",
                                replacement: "current working directory",
                                match: "whole_token"
                            ),
                        ],
                    ],
                ]
            ).data
        ).profile
        #expect(activeProfile.id == "http-session-profile")

        let activeWithAddedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements",
                method: "POST",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-repo",
                        text: "repo",
                        replacement: "repository"
                    ),
                ]
            ).data
        ).profile
        #expect(activeWithAddedReplacement.replacements.contains { $0.id == "expand-repo" })

        let activeWithReplacedReplacement = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements/expand-repo",
                method: "PUT",
                jsonBody: [
                    "replacement": Self.replacementJSON(
                        id: "expand-repo",
                        text: "repo",
                        replacement: "source repository",
                        formats: ["markdown"]
                    ),
                ]
            ).data
        ).profile
        #expect(activeWithReplacedReplacement.replacements.contains {
            $0.id == "expand-repo" && $0.replacement == "source repository"
        })

        let activeAfterRemoval = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/active/replacements/expand-repo",
                method: "DELETE"
            ).data
        ).profile
        #expect(activeAfterRemoval.replacements.contains { $0.id == "expand-repo" } == false)

        let effectiveDefault = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/effective", method: "GET").data
        ).profile
        #expect(effectiveDefault.id == "http-session-profile")

        let effectiveStored = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/effective/http-text-profile", method: "GET").data
        ).profile
        #expect(effectiveStored.id == "http-text-profile")

        let baseProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/base", method: "GET").data
        ).profile
        #expect(baseProfile.id.isEmpty == false)

        let savedSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/save", method: "POST").data
        ).textProfiles
        #expect(savedSnapshot.storedProfiles.contains { $0.id == "http-text-profile" })

        let loadedSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/load", method: "POST").data
        ).textProfiles
        #expect(loadedSnapshot.storedProfiles.contains { $0.id == "http-text-profile" })

        let resetProfile = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(path: "/text-profiles/active/reset", method: "POST").data
        ).profile
        #expect(resetProfile.id == initialTextProfiles.activeProfile.id)

        let storedAfterStoredRemoval = try decode(
            E2ETextProfileResponse.self,
            from: try await client.request(
                path: "/text-profiles/stored/http-text-profile/replacements/expand-tts",
                method: "DELETE"
            ).data
        ).profile
        #expect(storedAfterStoredRemoval.replacements.contains { $0.id == "expand-tts" } == false)

        let finalSnapshot = try decode(
            E2ETextProfileListResponse.self,
            from: try await client.request(path: "/text-profiles/stored/http-text-profile", method: "DELETE").data
        ).textProfiles
        #expect(finalSnapshot.storedProfiles.contains { $0.id == "http-text-profile" } == false)
    }

    @Test func mcpCatalogControlResourcesPromptsAndSubscriptionsStayLiveAndAccurate() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59_800..<59_900),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            mcpEnabled: true
        )
        try server.start()
        defer { server.stop() }

        let client = try await E2EMCPClient.connect(
            baseURL: server.baseURL,
            path: "/mcp",
            timeout: Self.e2eTimeout,
            server: server
        )
        try await waitUntilWorkerReady(using: client, timeout: Self.e2eTimeout, server: server)

        let resources = try await client.listResources()
        let resourceURIs = Set(resources.compactMap { $0["uri"] as? String })
        #expect(resourceURIs.contains("speak://runtime/overview"))
        #expect(resourceURIs.contains("speak://voices"))
        #expect(resourceURIs.contains("speak://text-profiles"))
        #expect(resourceURIs.contains("speak://playback/guide"))

        let templates = try await client.listResourceTemplates()
        let templateURIs = Set(templates.compactMap { $0["uriTemplate"] as? String })
        #expect(templateURIs.contains("speak://voices/{profile_name}"))
        #expect(templateURIs.contains("speak://text-profiles/stored/{profile_id}"))
        #expect(templateURIs.contains("speak://text-profiles/effective/{profile_id}"))
        #expect(templateURIs.contains("speak://requests/{request_id}"))

        let prompts = try await client.listPrompts()
        let promptNames = Set(prompts.compactMap { $0["name"] as? String })
        #expect(promptNames.contains("draft_profile_voice_description"))
        #expect(promptNames.contains("draft_text_profile"))
        #expect(promptNames.contains("draft_queue_playback_notice"))
        #expect(promptNames.contains("choose_surface_action"))

        let voicePrompt = try await client.getPrompt(
            name: "draft_profile_voice_description",
            arguments: [
                "profile_goal": "gentle narration",
                "voice_traits": "warm, steady, intimate",
            ]
        )
        let voicePromptText = try Self.requirePromptText(in: voicePrompt)
        #expect(voicePromptText.contains("gentle narration"))

        let chooseSurfacePrompt = try await client.getPrompt(
            name: "choose_surface_action",
            arguments: [
                "user_goal": "Help the user decide whether to clone a voice or create a synthetic profile.",
                "current_context": "The user has not provided reference audio yet.",
            ]
        )
        let chooseSurfaceText = try Self.requirePromptText(in: chooseSurfacePrompt)
        #expect(chooseSurfaceText.contains("action_type"))
        #expect(chooseSurfaceText.contains("create_voice_profile_from_description"))

        let statusPayload = try Self.requireObjectPayload(
            from: try await client.callToolJSON(name: "get_runtime_overview", arguments: [:])
        )
        #expect(statusPayload["worker_mode"] as? String == "ready")

        let runtimePayload = try Self.requireObjectPayload(from: try await client.readResourceJSON(uri: "speak://runtime/overview"))
        let runtimeTransports = try requireArray("transports", in: runtimePayload)
        #expect(runtimeTransports.contains {
            $0["name"] as? String == "mcp" && ($0["advertised_address"] as? String)?.contains("/mcp") == true
        })

        let textGuide = try await client.readResourceText(uri: "speak://text-profiles/guide")
        #expect(textGuide.contains("text_profile_name"))
        let voiceGuide = try await client.readResourceText(uri: "speak://voices/guide")
        #expect(voiceGuide.contains("create_voice_profile_from_audio"))
        let playbackGuide = try await client.readResourceText(uri: "speak://playback/guide")
        #expect(playbackGuide.contains("clear_playback_queue"))

        let eventStream = client.openEventStream()
        eventStream.start()
        defer { eventStream.stop() }

        try await client.subscribe(to: "speak://text-profiles")
        try await client.subscribe(to: "speak://voices")

        _ = try await client.callTool(
            name: "create_text_profile",
            arguments: [
                "id": "mcp-text-profile",
                "name": "MCP Text Profile",
                "replacements": [
                    Self.replacementJSON(
                        id: "expand-json",
                        text: "json",
                        replacement: "JSON",
                        match: "whole_token"
                    ),
                ],
            ]
        )

        let textProfileNotification = try await eventStream.waitForNotification(timeout: Duration.seconds(60)) {
            guard $0["method"] as? String == "notifications/resources/updated" else {
                return false
            }
            guard let params = $0["params"] as? [String: Any] else {
                return false
            }
            return params["uri"] as? String == "speak://text-profiles"
        }
        let textProfileNotificationParams = try requireDictionary("params", in: textProfileNotification)
        #expect(textProfileNotificationParams["uri"] as? String == "speak://text-profiles")

        let storedTextProfilesPayload = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://text-profiles")
        )
        let storedProfiles = try requireArray("stored_profiles", in: storedTextProfilesPayload)
        #expect(storedProfiles.contains { $0["id"] as? String == "mcp-text-profile" })

        _ = try await client.callTool(
            name: "store_text_profile",
            arguments: [
                "profile": [
                    "id": "mcp-text-profile",
                    "name": "MCP Text Profile Updated",
                    "replacements": [
                        Self.replacementJSON(
                            id: "expand-json",
                            text: "json",
                            replacement: "JavaScript Object Notation",
                            formats: ["markdown"]
                        ),
                    ],
                ],
            ]
        )

        _ = try await client.callTool(
            name: "use_text_profile",
            arguments: [
                "profile": [
                    "id": "mcp-session-profile",
                    "name": "MCP Session Profile",
                    "replacements": [
                        Self.replacementJSON(
                            id: "expand-cli",
                            text: "CLI",
                            replacement: "command line interface"
                        ),
                    ],
                ],
            ]
        )

        _ = try await client.callTool(
            name: "add_text_replacement",
            arguments: [
                "replacement": Self.replacementJSON(
                    id: "expand-rpc",
                    text: "RPC",
                    replacement: "remote procedure call"
                ),
            ]
        )
        _ = try await client.callTool(
            name: "replace_text_replacement",
            arguments: [
                "replacement": Self.replacementJSON(
                    id: "expand-rpc",
                    text: "RPC",
                    replacement: "Remote Procedure Call",
                    phase: "after_built_ins"
                ),
            ]
        )
        _ = try await client.callTool(
            name: "remove_text_replacement",
            arguments: [
                "replacement_id": "expand-rpc",
            ]
        )
        _ = try await client.callTool(
            name: "add_text_replacement",
            arguments: [
                "profile_id": "mcp-text-profile",
                "replacement": Self.replacementJSON(
                    id: "expand-ui",
                    text: "UI",
                    replacement: "user interface"
                ),
            ]
        )
        _ = try await client.callTool(
            name: "replace_text_replacement",
            arguments: [
                "profile_id": "mcp-text-profile",
                "replacement": Self.replacementJSON(
                    id: "expand-ui",
                    text: "UI",
                    replacement: "User Interface"
                ),
            ]
        )
        _ = try await client.callTool(
            name: "remove_text_replacement",
            arguments: [
                "profile_id": "mcp-text-profile",
                "replacement_id": "expand-ui",
            ]
        )

        let savedTextProfiles = try Self.requireObjectPayload(
            from: try await client.callToolJSON(name: "save_text_profiles", arguments: [:])
        )
        let savedStoredProfiles = try requireArray("stored_profiles", in: savedTextProfiles)
        #expect(savedStoredProfiles.contains { $0["id"] as? String == "mcp-text-profile" })

        let loadedTextProfiles = try Self.requireObjectPayload(
            from: try await client.callToolJSON(name: "load_text_profiles", arguments: [:])
        )
        let loadedStoredProfiles = try requireArray("stored_profiles", in: loadedTextProfiles)
        #expect(loadedStoredProfiles.contains { $0["id"] as? String == "mcp-text-profile" })

        let effectiveStoredProfile = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://text-profiles/effective/mcp-text-profile")
        )
        #expect(effectiveStoredProfile["id"] as? String == "mcp-text-profile")

        let storedProfileDetail = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://text-profiles/stored/mcp-text-profile")
        )
        #expect(storedProfileDetail["id"] as? String == "mcp-text-profile")

        let createdProfileName = "mcp-control-profile"
        let createProfilePayload = try await client.callTool(
            name: "create_voice_profile_from_description",
            arguments: [
                "profile_name": createdProfileName,
                "vibe": "femme",
                "text": Self.testingProfileText,
                "voice_description": Self.testingProfileVoiceDescription,
            ]
        )
        let createProfileJobID = try requireString("request_id", in: createProfilePayload)
        _ = try await waitForTerminalJob(
            id: createProfileJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )

        let profileNotification = try await eventStream.waitForNotification(timeout: Duration.seconds(60)) {
            guard $0["method"] as? String == "notifications/resources/updated" else {
                return false
            }
            guard let params = $0["params"] as? [String: Any] else {
                return false
            }
            return params["uri"] as? String == "speak://voices"
        }
        let profileNotificationParams = try requireDictionary("params", in: profileNotification)
        #expect(profileNotificationParams["uri"] as? String == "speak://voices")

        let profilesPayload = try requireProfiles(from: try await client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(profilesPayload.contains { $0.profileName == createdProfileName })

        let profileDetail = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://voices/\(createdProfileName)")
        )
        #expect(profileDetail["profile_name"] as? String == createdProfileName)

        let firstSpeechJobID = try requireString(
            "request_id",
            in: try await client.callTool(
                name: "queue_speech_live",
                arguments: [
                    "text": String(repeating: Self.testingPlaybackText + " ", count: 12),
                    "profile_name": createdProfileName,
                ]
            )
        )
        _ = try await Self.waitForMCPPlaybackState(
            using: client,
            timeout: .seconds(180),
            matching: { $0.state == "playing" && $0.activeRequest?.id == firstSpeechJobID }
        )
        let pausedPayload = try Self.requireObjectPayload(from: try await client.callToolJSON(name: "pause_playback", arguments: [:]))
        #expect(pausedPayload["state"] as? String == "paused")
        let resumedPayload = try Self.requireObjectPayload(from: try await client.callToolJSON(name: "resume_playback", arguments: [:]))
        #expect(resumedPayload["state"] as? String == "playing")

        let secondSpeechJobID = try requireString(
            "request_id",
            in: try await client.callTool(
                name: "queue_speech_live",
                arguments: [
                    "text": String(repeating: Self.testingPlaybackText + " ", count: 12),
                    "profile_name": createdProfileName,
                ]
            )
        )
        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in queue.queue.contains { $0.id == secondSpeechJobID } }
        )
        let cancelledPayload = try Self.requireObjectPayload(
            from: try await client.callToolJSON(
                name: "cancel_request",
                arguments: ["request_id": secondSpeechJobID]
            )
        )
        #expect(cancelledPayload["cancelled_request_id"] as? String == secondSpeechJobID)

        let thirdSpeechJobID = try requireString(
            "request_id",
            in: try await client.callTool(
                name: "queue_speech_live",
                arguments: [
                    "text": String(repeating: Self.testingPlaybackText + " ", count: 12),
                    "profile_name": createdProfileName,
                ]
            )
        )
        let fourthSpeechJobID = try requireString(
            "request_id",
            in: try await client.callTool(
                name: "queue_speech_live",
                arguments: [
                    "text": String(repeating: Self.testingPlaybackText + " ", count: 12),
                    "profile_name": createdProfileName,
                ]
            )
        )
        _ = try await Self.waitForMCPGenerationQueue(
            using: client,
            timeout: .seconds(180),
            matching: { queue in
                let ids = Set(queue.queue.map(\.id))
                return ids.contains(thirdSpeechJobID) && ids.contains(fourthSpeechJobID)
            }
        )
        let clearedPayload = try Self.requireObjectPayload(from: try await client.callToolJSON(name: "clear_playback_queue", arguments: [:]))
        #expect((clearedPayload["cleared_count"] as? Int) ?? 0 >= 2)

        _ = try await waitForTerminalJob(
            id: firstSpeechJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        let jobsResourcePayload = try Self.requireArrayPayload(from: try await client.readResourceJSON(uri: "speak://requests"))
        #expect(jobsResourcePayload.contains { $0["request_id"] as? String == firstSpeechJobID })

        let removeProfilePayload = try await client.callTool(
            name: "delete_voice_profile",
            arguments: ["profile_name": createdProfileName]
        )
        let removeProfileJobID = try requireString("request_id", in: removeProfilePayload)
        _ = try await waitForTerminalJob(
            id: removeProfileJobID,
            using: client,
            timeout: Self.e2eTimeout,
            server: server
        )
        let remainingProfiles = try requireProfiles(from: try await client.callToolJSON(name: "list_voice_profiles", arguments: [:]))
        #expect(remainingProfiles.contains { $0.profileName == createdProfileName } == false)

        _ = try await client.callToolJSON(name: "reset_active_text_profile", arguments: [:])
        _ = try await client.callToolJSON(
            name: "delete_text_profile",
            arguments: ["profile_id": "mcp-text-profile"]
        )
        let finalTextProfiles = try Self.requireObjectPayload(
            from: try await client.callToolJSON(name: "get_text_profiles_state", arguments: [:])
        )
        let finalStoredProfiles = try requireArray("stored_profiles", in: finalTextProfiles)
        #expect(finalStoredProfiles.contains { $0["id"] as? String == "mcp-text-profile" } == false)

        try await client.unsubscribe(from: "speak://text-profiles")
        try await client.unsubscribe(from: "speak://voices")
    }

    // MARK: Lane Workflows

    private static func runVoiceDesignLane(using transport: E2ETransport) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let profileName = "\(transport.profilePrefix)-voice-design-profile"

        do {
            let server = try makeServer(
                port: randomPort(in: 59_000..<59_200),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: profileName,
                    text: testingProfileText,
                    voiceDescription: testingProfileVoiceDescription
                )
                try await assertProfileIsVisible(using: client, profileName: profileName)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: profileName,
                    text: testingProfileText,
                    voiceDescription: testingProfileVoiceDescription
                )
                try await assertProfileIsVisible(using: client, profileName: profileName)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )
            }
        }

        do {
            let server = try makeServer(
                port: randomPort(in: 59_200..<59_400),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: isPlaybackTraceEnabled,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)

                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)

                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: profileName
                )
            }
        }
    }

    private static func runCloneLane(
        using transport: E2ETransport,
        transcriptMode: CloneTranscriptMode
    ) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let fixtureProfileName = "\(transport.profilePrefix)-\(transcriptMode.slug)-clone-source-profile"
        let cloneProfileName = "\(transport.profilePrefix)-\(transcriptMode.slug)-clone-profile"
        let referenceAudioURL = sandbox.rootURL.appendingPathComponent("\(transport.profilePrefix)-\(transcriptMode.slug)-reference.wav")

        do {
            let server = try makeServer(
                port: randomPort(in: 59_400..<59_600),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: true,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: fixtureProfileName,
                    text: testingCloneSourceText,
                    voiceDescription: testingProfileVoiceDescription,
                    outputPath: referenceAudioURL.path
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: referenceAudioURL.path,
                    transcript: transcriptMode.providedTranscript,
                    expectTranscription: transcriptMode.expectTranscription
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: fixtureProfileName,
                    text: testingCloneSourceText,
                    voiceDescription: testingProfileVoiceDescription,
                    outputPath: referenceAudioURL.path
                )
                #expect(FileManager.default.fileExists(atPath: referenceAudioURL.path))

                try await createCloneProfile(
                    using: client,
                    server: server,
                    profileName: cloneProfileName,
                    referenceAudioPath: referenceAudioURL.path,
                    transcript: transcriptMode.providedTranscript,
                    expectTranscription: transcriptMode.expectTranscription
                )
                try await assertProfileIsVisible(using: client, profileName: cloneProfileName)
            }

            let storedProfile = try loadStoredProfileManifest(
                named: cloneProfileName,
                from: sandbox.profileRootURL
            )
            switch transcriptMode {
            case .provided:
                #expect(storedProfile.sourceText == testingCloneSourceText)
            case .inferred:
                let inferredTranscript = storedProfile.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                #expect(!inferredTranscript.isEmpty)
                #expect(transcriptLooksCloseToCloneSource(inferredTranscript))
            }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await runSilentSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )
            }
        }

        do {
            let server = try makeServer(
                port: randomPort(in: 59_600..<59_800),
                profileRootURL: sandbox.profileRootURL,
                silentPlayback: false,
                playbackTrace: isPlaybackTraceEnabled,
                mcpEnabled: transport == .mcp
            )
            try server.start()
            defer { server.stop() }

            switch transport {
            case .http:
                let client = E2EHTTPClient(baseURL: server.baseURL)
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )

            case .mcp:
                let client = try await E2EMCPClient.connect(
                    baseURL: server.baseURL,
                    path: "/mcp",
                    timeout: e2eTimeout,
                    server: server
                )
                try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
                _ = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: cloneProfileName
                )
            }
        }
    }

    private static func runMarvisTripletLane(using transport: E2ETransport) async throws {
        struct MarvisProfileLane {
            let profileName: String
            let vibe: String
            let voiceDescription: String
            let expectedVoice: String
        }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let prefix = transport.profilePrefix
        let lanes = [
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-femme-profile",
                vibe: "femme",
                voiceDescription: "A warm, bright, feminine narrator voice.",
                expectedVoice: "conversational_a"
            ),
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-masc-profile",
                vibe: "masc",
                voiceDescription: "A grounded, rich, masculine speaking voice.",
                expectedVoice: "conversational_b"
            ),
            MarvisProfileLane(
                profileName: "\(prefix)-marvis-triplet-androgenous-profile",
                vibe: "androgenous",
                voiceDescription: "A calm, balanced, and gentle speaking voice.",
                expectedVoice: "conversational_a"
            ),
        ]

        let server = try makeServer(
            port: randomPort(in: 58_800..<59_000),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: isPlaybackTraceEnabled,
            mcpEnabled: transport == .mcp,
            speechBackend: "marvis"
        )
        try server.start()
        defer { server.stop() }

        switch transport {
        case .http:
            let client = E2EHTTPClient(baseURL: server.baseURL)
            try await waitUntilWorkerReady(
                using: client,
                timeout: e2eTimeout,
                server: server,
                expectPlaybackEngine: true
            )

            for lane in lanes {
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: lane.profileName,
                    vibe: lane.vibe,
                    text: testingProfileText,
                    voiceDescription: lane.voiceDescription
                )
            }

            let profilesResponse = try await client.request(path: "/voices", method: "GET")
            #expect(profilesResponse.statusCode == 200)
            let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
            for lane in lanes {
                #expect(profiles.contains {
                    $0.profileName == lane.profileName && $0.vibe == lane.vibe
                })
            }

            for lane in lanes {
                let jobID = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: lane.profileName
                )
                try await expectMarvisVoiceSelection(
                    on: server,
                    requestID: jobID,
                    expectedVoice: lane.expectedVoice
                )
            }

        case .mcp:
            let client = try await E2EMCPClient.connect(
                baseURL: server.baseURL,
                path: "/mcp",
                timeout: e2eTimeout,
                server: server
            )
            try await waitUntilWorkerReady(
                using: client,
                timeout: e2eTimeout,
                server: server,
                expectPlaybackEngine: true
            )

            for lane in lanes {
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: lane.profileName,
                    vibe: lane.vibe,
                    text: testingProfileText,
                    voiceDescription: lane.voiceDescription
                )
            }

            let profilesPayload = try await client.callToolJSON(name: "list_voice_profiles", arguments: [:])
            let profiles = try requireProfiles(from: profilesPayload)
            for lane in lanes {
                #expect(profiles.contains {
                    $0.profileName == lane.profileName && $0.vibe == lane.vibe
                })
            }

            for lane in lanes {
                let jobID = try await runAudibleSpeech(
                    using: client,
                    server: server,
                    text: testingPlaybackText,
                    profileName: lane.profileName
                )
                try await expectMarvisVoiceSelection(
                    on: server,
                    requestID: jobID,
                    expectedVoice: lane.expectedVoice
                )
            }
        }
    }

    private static func runRelativePathProfileAndCloneLane(using transport: E2ETransport) async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let callerWorkingDirectory = sandbox.rootURL.appendingPathComponent("\(transport.profilePrefix)-caller-cwd", isDirectory: true)
        try FileManager.default.createDirectory(at: callerWorkingDirectory, withIntermediateDirectories: true)

        let relativeReferencePath = "exports/reference.wav"
        let exportedReferenceURL = callerWorkingDirectory.appending(path: relativeReferencePath)
        let fixtureProfileName = "\(transport.profilePrefix)-relative-profile-source"
        let cloneProfileName = "\(transport.profilePrefix)-relative-profile-clone"

        let server = try makeServer(
            port: randomPort(in: 58_600..<58_800),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
            mcpEnabled: transport == .mcp
        )
        try server.start()
        defer { server.stop() }

        switch transport {
        case .http:
            let client = E2EHTTPClient(baseURL: server.baseURL)
            try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
            try await createVoiceDesignProfile(
                using: client,
                server: server,
                profileName: fixtureProfileName,
                text: testingCloneSourceText,
                voiceDescription: testingProfileVoiceDescription,
                outputPath: relativeReferencePath,
                cwd: callerWorkingDirectory.path
            )
            #expect(FileManager.default.fileExists(atPath: exportedReferenceURL.path))

            try await createCloneProfile(
                using: client,
                server: server,
                profileName: cloneProfileName,
                referenceAudioPath: relativeReferencePath,
                transcript: testingCloneSourceText,
                expectTranscription: false,
                cwd: callerWorkingDirectory.path
            )
            try await assertProfileIsVisible(using: client, profileName: cloneProfileName)

        case .mcp:
            let client = try await E2EMCPClient.connect(
                baseURL: server.baseURL,
                path: "/mcp",
                timeout: e2eTimeout,
                server: server
            )
            try await waitUntilWorkerReady(using: client, timeout: e2eTimeout, server: server)
            try await createVoiceDesignProfile(
                using: client,
                server: server,
                profileName: fixtureProfileName,
                text: testingCloneSourceText,
                voiceDescription: testingProfileVoiceDescription,
                outputPath: relativeReferencePath,
                cwd: callerWorkingDirectory.path
            )
            #expect(FileManager.default.fileExists(atPath: exportedReferenceURL.path))

            try await createCloneProfile(
                using: client,
                server: server,
                profileName: cloneProfileName,
                referenceAudioPath: relativeReferencePath,
                transcript: testingCloneSourceText,
                expectTranscription: false,
                cwd: callerWorkingDirectory.path
            )
            try await assertProfileIsVisible(using: client, profileName: cloneProfileName)
        }

        let storedProfile = try loadStoredProfileManifest(
            named: cloneProfileName,
            from: sandbox.profileRootURL
        )
        #expect(storedProfile.sourceText == testingCloneSourceText)
    }

    private static func runQueuedMarvisTripletLane(using transport: E2ETransport) async throws {
        struct MarvisQueuedLane {
            let profileName: String
            let vibe: String
            let voiceDescription: String
            let expectedVoice: String
        }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let prefix = transport.profilePrefix
        let lanes = [
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-femme-profile",
                vibe: "femme",
                voiceDescription: "A warm, bright, feminine narrator voice.",
                expectedVoice: "conversational_a"
            ),
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-masc-profile",
                vibe: "masc",
                voiceDescription: "A grounded, rich, masculine speaking voice.",
                expectedVoice: "conversational_b"
            ),
            MarvisQueuedLane(
                profileName: "\(prefix)-marvis-queued-androgenous-profile",
                vibe: "androgenous",
                voiceDescription: "A calm, balanced, and gentle speaking voice.",
                expectedVoice: "conversational_a"
            ),
        ]

        let server = try makeServer(
            port: randomPort(in: 59_000..<59_200),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: false,
            playbackTrace: isPlaybackTraceEnabled,
            mcpEnabled: transport == .mcp,
            speechBackend: "marvis"
        )
        try server.start()
        defer { server.stop() }

        switch transport {
        case .http:
            let client = E2EHTTPClient(baseURL: server.baseURL)
            try await waitUntilWorkerReady(
                using: client,
                timeout: e2eTimeout,
                server: server,
                expectPlaybackEngine: true
            )

            for lane in lanes {
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: lane.profileName,
                    vibe: lane.vibe,
                    text: testingProfileText,
                    voiceDescription: lane.voiceDescription
                )
            }

            var jobIDs = [String]()
            for lane in lanes {
                let jobID = try await submitSpeechJob(
                    using: client,
                    text: testingPlaybackText,
                    profileName: lane.profileName
                )
                jobIDs.append(jobID)
            }

            _ = try await waitForPlaybackState(
                using: client,
                timeout: .seconds(180),
                matching: { $0.state == "playing" && $0.activeRequest?.id == jobIDs[0] }
            )
            let queued = try await waitForGenerationQueue(
                using: client,
                timeout: .seconds(180),
                matching: { snapshot in
                    let ids = Set(snapshot.queue.map(\.id))
                    return ids.contains(jobIDs[1]) && ids.contains(jobIDs[2])
                }
            )
            #expect(queued.queueType == "generation")

            do {
                let firstSnapshot = try await waitForTerminalJob(
                    id: jobIDs[0],
                    using: client,
                    timeout: e2eTimeout,
                    server: server
                )
                assertSpeechJobCompleted(firstSnapshot, expectedJobID: jobIDs[0])
                #expect(!firstSnapshot.history.contains { $0.event == "queued" })

                let secondSnapshot = try await waitForTerminalJob(
                    id: jobIDs[1],
                    using: client,
                    timeout: e2eTimeout,
                    server: server
                )
                assertSpeechJobCompleted(secondSnapshot, expectedJobID: jobIDs[1])
                #expect(secondSnapshot.history.contains {
                    $0.event == "queued" && $0.reason == "waiting_for_active_request"
                })

                let thirdSnapshot = try await waitForTerminalJob(
                    id: jobIDs[2],
                    using: client,
                    timeout: e2eTimeout,
                    server: server
                )
                assertSpeechJobCompleted(thirdSnapshot, expectedJobID: jobIDs[2])
                #expect(thirdSnapshot.history.contains {
                    $0.event == "queued" && $0.reason == "waiting_for_active_request"
                })
            } catch {
                await recordQueuedMarvisHTTPDiagnostics(
                    using: client,
                    requestIDs: jobIDs,
                    expectedProfiles: lanes.map(\.profileName)
                )
                throw error
            }

            try await assertMarvisPlaybackStartedInOrder(on: server, requestIDs: jobIDs)

            for (jobID, lane) in zip(jobIDs, lanes) {
                try await expectMarvisVoiceSelection(
                    on: server,
                    requestID: jobID,
                    expectedVoice: lane.expectedVoice
                )
            }

        case .mcp:
            let client = try await E2EMCPClient.connect(
                baseURL: server.baseURL,
                path: "/mcp",
                timeout: e2eTimeout,
                server: server
            )
            try await waitUntilWorkerReady(
                using: client,
                timeout: e2eTimeout,
                server: server,
                expectPlaybackEngine: true
            )

            for lane in lanes {
                try await createVoiceDesignProfile(
                    using: client,
                    server: server,
                    profileName: lane.profileName,
                    vibe: lane.vibe,
                    text: testingProfileText,
                    voiceDescription: lane.voiceDescription
                )
            }

            var jobIDs = [String]()
            for lane in lanes {
                let payload = try await client.callTool(
                    name: "queue_speech_live",
                    arguments: [
                        "text": testingPlaybackText,
                        "profile_name": lane.profileName,
                    ]
                )
                let jobID = try requireString("request_id", in: payload)
                #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")
                jobIDs.append(jobID)
            }

            let queued = try await waitForMCPGenerationQueue(
                using: client,
                timeout: .seconds(180),
                matching: { snapshot in
                    let ids = Set(snapshot.queue.map(\.id))
                    return ids.contains(jobIDs[1]) && ids.contains(jobIDs[2])
                }
            )
            #expect(queued.queueType == "generation")

            let firstSnapshot = try await waitForTerminalJob(
                id: jobIDs[0],
                using: client,
                timeout: e2eTimeout,
                server: server
            )
            assertSpeechJobCompleted(firstSnapshot, expectedJobID: jobIDs[0])
            #expect(!firstSnapshot.history.contains { $0.event == "queued" })

            let secondSnapshot = try await waitForTerminalJob(
                id: jobIDs[1],
                using: client,
                timeout: e2eTimeout,
                server: server
            )
            assertSpeechJobCompleted(secondSnapshot, expectedJobID: jobIDs[1])
            #expect(secondSnapshot.history.contains {
                $0.event == "queued" && $0.reason == "waiting_for_active_request"
            })

            let thirdSnapshot = try await waitForTerminalJob(
                id: jobIDs[2],
                using: client,
                timeout: e2eTimeout,
                server: server
            )
            assertSpeechJobCompleted(thirdSnapshot, expectedJobID: jobIDs[2])
            #expect(thirdSnapshot.history.contains {
                $0.event == "queued" && $0.reason == "waiting_for_active_request"
            })

            try await assertMarvisPlaybackStartedInOrder(on: server, requestIDs: jobIDs)

            for (jobID, lane) in zip(jobIDs, lanes) {
                try await expectMarvisVoiceSelection(
                    on: server,
                    requestID: jobID,
                    expectedVoice: lane.expectedVoice
                )
            }
        }
    }

    // MARK: HTTP Lane Helpers

    private static func createVoiceDesignProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "vibe": vibe,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            body["output_path"] = outputPath
        }
        if let cwd {
            body["cwd"] = cwd
        }

        let response = try await client.request(path: "/voices/from-description", method: "POST", jsonBody: body)
        #expect(response.statusCode == 202)

        let createJobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: createJobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)
        if outputPath != nil {
            #expect(snapshot.terminalEvent?.profilePath?.isEmpty == false)
        }
    }

    private static func createCloneProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool,
        cwd: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "profile_name": profileName,
            "vibe": vibe,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            body["transcript"] = transcript
        }
        if let cwd {
            body["cwd"] = cwd
        }

        let response = try await client.request(path: "/voices/from-audio", method: "POST", jsonBody: body)
        #expect(response.statusCode == 202)

        let cloneJobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: cloneJobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)

        assertCloneTranscriptionStages(
            in: snapshot,
            expectTranscription: expectTranscription
        )
    }

    private static func assertProfileIsVisible(
        using client: E2EHTTPClient,
        profileName: String
    ) async throws {
        let profilesResponse = try await client.request(path: "/voices", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName })
    }

    private static func assertProfileIsNotVisible(
        using client: E2EHTTPClient,
        profileName: String
    ) async throws {
        let profilesResponse = try await client.request(path: "/voices", method: "GET")
        #expect(profilesResponse.statusCode == 200)
        let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
        #expect(profiles.contains { $0.profileName == profileName } == false)
    }

    private static func runSilentSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        #expect(response.statusCode == 202)

        let jobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID
        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "started" && $0.op == "queue_speech_live" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        #expect(!snapshot.history.contains { $0.event == "queued" })

        let eventsResponse = try await client.request(path: "/requests/\(jobID)/events", method: "GET")
        #expect(eventsResponse.statusCode == 200)
        #expect(eventsResponse.text.contains("event: worker_status"))
        #expect(eventsResponse.text.contains(#""event":"started""#))
        #expect(eventsResponse.text.contains(#""ok":true"#))
        #expect(!eventsResponse.text.contains(#""event":"queued""#))
    }

    private static func runAudibleSpeech(
        using client: E2EHTTPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws -> String {
        let engineReadyLog = try await server.waitForStderrJSONObject(timeout: .seconds(120)) {
            guard
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }
        #expect(engineReadyLog["event"] as? String == "playback_engine_ready")

        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        #expect(response.statusCode == 202)

        let jobID = try decode(E2EJobCreatedResponse.self, from: response.data).jobID

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_started",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["startup_buffered_audio_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["time_to_first_chunk_ms"] as? Int != nil
                && details["played_back_callback_count"] as? Int != nil
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["low_water_target_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "preroll_ready" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        return jobID
    }

    private static func submitSpeechJob(
        using client: E2EHTTPClient,
        text: String,
        profileName: String
    ) async throws -> String {
        let response = try await client.request(
            path: "/speech/live",
            method: "POST",
            jsonBody: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        #expect(response.statusCode == 202)
        return try decode(E2EJobCreatedResponse.self, from: response.data).jobID
    }

    private static func waitForPlaybackState(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackStateSnapshot) -> Bool
    ) async throws -> E2EPlaybackStateSnapshot {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let response = try await client.request(path: "/playback/state", method: "GET")
            guard response.statusCode == 200 else { return nil }
            let snapshot = try decode(E2EPlaybackStateResponse.self, from: response.data).playback
            return predicate(snapshot) ? snapshot : nil
        }
    }

    private static func waitForGenerationQueue(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let response = try await client.request(path: "/generation/queue", method: "GET")
            guard response.statusCode == 200 else { return nil }
            let snapshot = try decode(E2EQueueSnapshotResponse.self, from: response.data)
            return predicate(snapshot) ? snapshot : nil
        }
    }

    // MARK: MCP Lane Helpers

    private static func createVoiceDesignProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "vibe": vibe,
            "text": text,
            "voice_description": voiceDescription,
        ]
        if let outputPath {
            arguments["output_path"] = outputPath
        }
        if let cwd {
            arguments["cwd"] = cwd
        }

        let payload = try await client.callTool(name: "create_voice_profile_from_description", arguments: arguments)
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)
        if outputPath != nil {
            #expect(snapshot.terminalEvent?.profilePath?.isEmpty == false)
        }
    }

    private static func createCloneProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "femme",
        referenceAudioPath: String,
        transcript: String?,
        expectTranscription: Bool,
        cwd: String? = nil
    ) async throws {
        var arguments = [
            "profile_name": profileName,
            "vibe": vibe,
            "reference_audio_path": referenceAudioPath,
        ]
        if let transcript {
            arguments["transcript"] = transcript
        }
        if let cwd {
            arguments["cwd"] = cwd
        }

        let payload = try await client.callTool(name: "create_voice_profile_from_audio", arguments: arguments)
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.terminalEvent?.profileName == profileName)

        assertCloneTranscriptionStages(
            in: snapshot,
            expectTranscription: expectTranscription
        )
    }

    private static func assertProfileIsVisible(
        using client: E2EMCPClient,
        profileName: String
    ) async throws {
        let payload = try await client.callToolJSON(name: "list_voice_profiles", arguments: [:])
        let profiles = try requireProfiles(from: payload)
        #expect(profiles.contains { $0.profileName == profileName })
    }

    private static func runSilentSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws {
        let payload = try await client.callTool(
            name: "queue_speech_live",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "started" && $0.op == "queue_speech_live" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        #expect(!snapshot.history.contains { $0.event == "queued" })
    }

    private static func runAudibleSpeech(
        using client: E2EMCPClient,
        server: ServerProcess,
        text: String,
        profileName: String
    ) async throws -> String {
        let engineReadyLog = try await server.waitForStderrJSONObject(timeout: .seconds(120)) {
            guard
                $0["event"] as? String == "playback_engine_ready",
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }
        #expect(engineReadyLog["event"] as? String == "playback_engine_ready")

        let payload = try await client.callTool(
            name: "queue_speech_live",
            arguments: [
                "text": text,
                "profile_name": profileName,
            ]
        )
        let jobID = try requireString("request_id", in: payload)
        #expect(payload["request_resource_uri"] as? String == "speak://requests/\(jobID)")

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_started",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["startup_buffered_audio_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }

        _ = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "playback_finished",
                $0["request_id"] as? String == jobID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            let textComplexityClass = details["text_complexity_class"] as? String
            return ["compact", "balanced", "extended"].contains(textComplexityClass)
                && details["time_to_first_chunk_ms"] as? Int != nil
                && details["played_back_callback_count"] as? Int != nil
                && details["startup_buffer_target_ms"] as? Int != nil
                && details["low_water_target_ms"] as? Int != nil
                && details["process_phys_footprint_bytes"] as? Int != nil
                && details["mlx_active_memory_bytes"] as? Int != nil
        }

        let snapshot = try await waitForTerminalJob(
            id: jobID,
            using: client,
            timeout: e2eTimeout,
            server: server
        )

        assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "preroll_ready" })
        #expect(snapshot.history.contains { $0.event == "progress" && $0.stage == "playback_finished" })
        return jobID
    }

    private static func expectMarvisVoiceSelection(
        on server: ServerProcess,
        requestID: String,
        expectedVoice: String
    ) async throws {
        let log = try await server.waitForStderrJSONObject(timeout: e2eTimeout) {
            guard
                $0["event"] as? String == "marvis_voice_selected",
                $0["request_id"] as? String == requestID,
                let details = $0["details"] as? [String: Any]
            else {
                return false
            }

            return details["speech_backend"] as? String == "marvis"
                && details["marvis_voice"] as? String == expectedVoice
        }
        #expect(log["event"] as? String == "marvis_voice_selected")
    }

    private static func assertMarvisPlaybackStartedInOrder(
        on server: ServerProcess,
        requestIDs: [String]
    ) async throws {
        let startedRequestIDs: [String] = try await e2eWaitUntil(
            timeout: e2eTimeout,
            pollInterval: .milliseconds(200)
        ) {
            let matches = server.stderrObjects().compactMap { object -> String? in
                guard object["event"] as? String == "playback_started" else { return nil }
                return object["request_id"] as? String
            }
            let filtered = matches.filter { requestIDs.contains($0) }
            guard Set(filtered).isSuperset(of: Set(requestIDs)) else { return nil }
            return filtered
        }

        var previousIndex = -1
        for requestID in requestIDs {
            guard let index = startedRequestIDs.firstIndex(of: requestID) else {
                Issue.record("The live Marvis playback trace never reported a playback_started event for request '\(requestID)'.")
                return
            }
            #expect(index > previousIndex)
            previousIndex = index
        }
    }

    private static func recordQueuedMarvisHTTPDiagnostics(
        using client: E2EHTTPClient,
        requestIDs: [String],
        expectedProfiles: [String]
    ) async {
        do {
            let requestList = try decode(
                E2ERequestListResponse.self,
                from: try await client.request(path: "/requests", method: "GET").data
            )
            let hostState = try jsonObject(
                from: try await client.request(path: "/runtime/host", method: "GET").data
            )

            let retainedRequests = requestList.requests
                .filter { requestIDs.contains($0.requestID) }
                .sorted { lhs, rhs in
                    requestIDs.firstIndex(of: lhs.requestID) ?? .max
                        < requestIDs.firstIndex(of: rhs.requestID) ?? .max
                }
                .map(requestDiagnosticSummary)
                .joined(separator: "\n")

            let playbackQueue = try diagnosticJSONString(from: hostState["playback_queue"])
            let generationQueue = try diagnosticJSONString(from: hostState["generation_queue"])
            let currentGenerationJob = try diagnosticJSONString(from: hostState["current_generation_job"])

            Issue.record(
                """
                Queued Marvis HTTP diagnostics
                expected_profiles: \(expectedProfiles.joined(separator: ", "))
                request_ids: \(requestIDs.joined(separator: ", "))
                playback_queue: \(playbackQueue)
                generation_queue: \(generationQueue)
                current_generation_job: \(currentGenerationJob)
                retained_requests:
                \(retainedRequests.isEmpty ? "none" : retainedRequests)
                """
            )
        } catch {
            Issue.record(
                "Queued Marvis HTTP diagnostics could not be captured after a live-playback failure. Likely cause: \(error.localizedDescription)"
            )
        }
    }

    private static func requestDiagnosticSummary(_ snapshot: E2EJobSnapshot) -> String {
        let latestEvent = snapshot.history.last?.event ?? "nil"
        let latestStage = snapshot.history.last?.stage ?? "nil"
        let terminalEvent = snapshot.terminalEvent?.event ?? "nil"
        let historySummary = snapshot.history
            .map {
                [
                    $0.event ?? "message",
                    $0.stage,
                    $0.reason,
                    $0.op,
                ]
                .compactMap { $0 }
                .joined(separator: ":")
            }
            .joined(separator: " -> ")

        return "- \(snapshot.requestID) status=\(snapshot.status) latest=\(latestEvent):\(latestStage) terminal=\(terminalEvent) history=\(historySummary)"
    }

    private static func diagnosticJSONString(from value: Any?) throws -> String {
        guard let value else { return "null" }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func waitForMCPPlaybackState(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EPlaybackStateSnapshot) -> Bool
    ) async throws -> E2EPlaybackStateSnapshot {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try requireObjectPayload(
                from: try await client.callToolJSON(name: "playback_state", arguments: [:])
            )
            let snapshot: E2EPlaybackStateSnapshot
            if let playback = payload["playback"] as? [String: Any] {
                snapshot = try decodePayload(E2EPlaybackStateSnapshot.self, from: playback)
            } else {
                snapshot = try decodePayload(E2EPlaybackStateSnapshot.self, from: payload)
            }
            return predicate(snapshot) ? snapshot : nil
        }
    }

    private static func waitForMCPGenerationQueue(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping (E2EQueueSnapshotResponse) -> Bool
    ) async throws -> E2EQueueSnapshotResponse {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(200)) {
            let payload = try requireObjectPayload(
                from: try await client.callToolJSON(name: "list_queue_generation", arguments: [:])
            )
            let snapshot = try decodePayload(E2EQueueSnapshotResponse.self, from: payload)
            return predicate(snapshot) ? snapshot : nil
        }
    }

    // MARK: Shared Assertions

    private static func assertSpeechJobCompleted(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        #expect(snapshot.status == "completed")
        #expect(snapshot.terminalEvent?.id == jobID)
        #expect(snapshot.terminalEvent?.ok == true)
        #expect(snapshot.history.contains { $0.ok == true })
    }

    private static func assertCloneTranscriptionStages(
        in snapshot: E2EJobSnapshot,
        expectTranscription: Bool
    ) {
        let sawLoading = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "loading_clone_transcription_model"
        }
        let sawTranscribing = snapshot.history.contains {
            $0.event == "progress" && $0.stage == "transcribing_clone_audio"
        }

        if expectTranscription {
            #expect(sawLoading)
            #expect(sawTranscribing)
        } else {
            #expect(!sawLoading)
            #expect(!sawTranscribing)
        }
    }

    private static func transcriptLooksCloseToCloneSource(_ transcript: String) -> Bool {
        let expectedTokens = normalizedTranscriptTokens(from: testingCloneSourceText)
        let actualTokens = normalizedTranscriptTokens(from: transcript)

        guard !expectedTokens.isEmpty, !actualTokens.isEmpty else {
            return false
        }

        let sharedTokens = expectedTokens.intersection(actualTokens)
        let recall = Double(sharedTokens.count) / Double(expectedTokens.count)
        let precision = Double(sharedTokens.count) / Double(actualTokens.count)

        return recall >= 0.7 && precision >= 0.6
    }

    private static func normalizedTranscriptTokens(from text: String) -> Set<String> {
        let scalars = text.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        let normalized = String(scalars)
        return Set(
            normalized
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    private static func replacementJSON(
        id: String,
        text: String,
        replacement: String,
        match: String = "exact_phrase",
        phase: String = "before_built_ins",
        isCaseSensitive: Bool = false,
        formats: [String] = [],
        priority: Int = 0
    ) -> [String: Any] {
        [
            "id": id,
            "text": text,
            "replacement": replacement,
            "match": match,
            "phase": phase,
            "is_case_sensitive": isCaseSensitive,
            "formats": formats,
            "priority": priority,
        ]
    }

    private static func requirePromptText(in result: [String: Any]) throws -> String {
        let messages = try requireArray("messages", in: result)
        let firstMessage = try requireFirstDictionary(in: messages)
        let content = try requireDictionary("content", in: firstMessage)
        return try requireString("text", in: content)
    }

    private static func requireObjectPayload(from payload: Any) throws -> [String: Any] {
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON object payload, but received '\(type(of: payload))'."
            )
        }
        return object
    }

    private static func requireArrayPayload(from payload: Any) throws -> [[String: Any]] {
        guard let array = payload as? [[String: Any]] else {
            throw E2ETransportError(
                "The live end-to-end helper expected a JSON array payload, but received '\(type(of: payload))'."
            )
        }
        return array
    }

    private static func decodePayload<Value: Decodable>(_ type: Value.Type, from payload: [String: Any]) throws -> Value {
        let data = try JSONSerialization.data(withJSONObject: payload)
        return try decode(Value.self, from: data)
    }

    // MARK: Build Artifacts

    private struct SpeakSwiftlyPublishedRuntimeMetadata: Decodable {
        let buildConfiguration: String
        let productsPath: String
        let executablePath: String
        let launcherPath: String
        let metallibPath: String
        let aliasPath: String

        enum CodingKeys: String, CodingKey {
            case buildConfiguration = "build_configuration"
            case productsPath = "products_path"
            case executablePath = "executable_path"
            case launcherPath = "launcher_path"
            case metallibPath = "metallib_path"
            case aliasPath = "alias_path"
        }
    }

    private static func speakSwiftlyPublishedRuntimeMetadata(configuration: String) throws -> SpeakSwiftlyPublishedRuntimeMetadata {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let metadataURL = serverRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.local/xcode/SpeakSwiftly.\(configuration.lowercased()).json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The live SpeakSwiftlyServer end-to-end suite requires the sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)'. Publish and verify the sibling \(configuration) runtime first."
            )
        }

        let metadata = try decode(
            SpeakSwiftlyPublishedRuntimeMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        guard metadata.buildConfiguration == configuration else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata at '\(metadataURL.path)' reported build configuration '\(metadata.buildConfiguration)' instead of the expected '\(configuration)'."
            )
        }

        let aliasURL = URL(fileURLWithPath: metadata.aliasPath, isDirectory: true)
        let metallibURL = URL(fileURLWithPath: metadata.metallibPath, isDirectory: false)
        let launcherURL = URL(fileURLWithPath: metadata.launcherPath, isDirectory: false)
        let executableURL = URL(fileURLWithPath: metadata.executablePath, isDirectory: false)

        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing metallib path '\(metallibURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: launcherURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing runtime launcher '\(launcherURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing executable '\(executableURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }
        guard FileManager.default.fileExists(atPath: aliasURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The sibling SpeakSwiftly published runtime metadata pointed at a missing stable alias '\(aliasURL.path)'. Re-publish and verify the sibling \(configuration) runtime before running the live server suite."
            )
        }

        return metadata
    }

    private static func serverToolExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServerTool", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServerTool executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live end-to-end suite."
            )
        }
        return executableURL
    }

    private static func stageMetallibForServerBinary(
        from publishedRuntimeMetadata: SpeakSwiftlyPublishedRuntimeMetadata,
        serverExecutableURL: URL
    ) throws {
        let sourceURL = URL(fileURLWithPath: publishedRuntimeMetadata.metallibPath, isDirectory: false)
        let targetDirectoryURL = serverExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let targetURL = targetDirectoryURL.appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    }

    private static func makeServer(
        port: Int,
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil
    ) throws -> ServerProcess {
        let publishedRuntimeMetadata = try speakSwiftlyPublishedRuntimeMetadata(configuration: "Debug")
        let executableURL = try serverToolExecutableURL()
        try stageMetallibForServerBinary(
            from: publishedRuntimeMetadata,
            serverExecutableURL: executableURL
        )

        return try ServerProcess(
            executableURL: executableURL,
            profileRootURL: profileRootURL,
            port: port,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled,
            speechBackend: speechBackend
        )
    }

    private static func randomPort(in range: Range<Int>) -> Int {
        Int.random(in: range)
    }

    private static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    private static var e2eTimeout: Duration {
        .seconds(1_200)
    }
}
