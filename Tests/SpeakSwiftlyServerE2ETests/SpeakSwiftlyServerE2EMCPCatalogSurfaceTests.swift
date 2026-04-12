import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - MCP Catalog Surface End-to-End Tests

extension SpeakSwiftlyServerE2EControlSurfaceTests {
    @Test func mcpCatalogControlResourcesPromptsAndSubscriptionsStayLiveAndAccurate() async throws {
        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let server = try Self.makeServer(
            port: Self.randomPort(in: 59_800..<59_900),
            profileRootURL: sandbox.profileRootURL,
            silentPlayback: true,
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
        #expect(resourceURIs.contains("speak://text-profiles/style"))
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
        #expect(textGuide.contains("set_text_profile_style"))
        let voiceGuide = try await client.readResourceText(uri: "speak://voices/guide")
        #expect(voiceGuide.contains("create_voice_profile_from_audio"))
        let playbackGuide = try await client.readResourceText(uri: "speak://playback/guide")
        #expect(playbackGuide.contains("clear_playback_queue"))

        let eventStream = client.openEventStream()
        try await eventStream.start()
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

        let textProfileNotification: [String: Any]
        do {
            textProfileNotification = try await eventStream.waitForNotification(timeout: Duration.seconds(60)) {
                guard $0["method"] as? String == "notifications/resources/updated" else {
                    return false
                }
                guard let params = $0["params"] as? [String: Any] else {
                    return false
                }
                return params["uri"] as? String == "speak://text-profiles"
            }
        } catch {
            let textProfilesResource = try? await client.readResourceText(uri: "speak://text-profiles")
            throw E2ETransportError(
                """
                The live MCP suite timed out while waiting for a text-profile resource update notification after `create_text_profile`.
                Underlying error: \(error)

                Current `speak://text-profiles` resource:
                \(textProfilesResource ?? "unavailable")

                Server stdout/stderr:
                \(server.combinedOutput)
                """
            )
        }
        let textProfileNotificationParams = try requireDictionary("params", in: textProfileNotification)
        #expect(textProfileNotificationParams["uri"] as? String == "speak://text-profiles")

        let storedTextProfilesPayload = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://text-profiles")
        )
        #expect(storedTextProfilesPayload["built_in_style"] as? String == "balanced")
        let storedProfiles = try requireArray("stored_profiles", in: storedTextProfilesPayload)
        #expect(storedProfiles.contains { $0["id"] as? String == "mcp-text-profile" })

        let initialTextProfileStylePayload = try Self.requireObjectPayload(
            from: try await client.readResourceJSON(uri: "speak://text-profiles/style")
        )
        #expect(initialTextProfileStylePayload["built_in_style"] as? String == "balanced")

        _ = try await client.callTool(
            name: "set_text_profile_style",
            arguments: [
                "built_in_style": "compact",
            ]
        )

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
        #expect(loadedTextProfiles["built_in_style"] as? String == "compact")
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

        _ = try await client.callToolJSON(name: "reset_active_text_profile", arguments: [:])
        _ = try await client.callToolJSON(
            name: "delete_text_profile",
            arguments: ["profile_id": "mcp-text-profile"]
        )
        let finalTextProfiles = try Self.requireObjectPayload(
            from: try await client.callToolJSON(name: "get_text_normalizer_snapshot", arguments: [:])
        )
        let finalStoredProfiles = try requireArray("stored_profiles", in: finalTextProfiles)
        #expect(finalStoredProfiles.contains { $0["id"] as? String == "mcp-text-profile" } == false)

        try await client.unsubscribe(from: "speak://text-profiles")
        try await client.unsubscribe(from: "speak://voices")
    }
}
