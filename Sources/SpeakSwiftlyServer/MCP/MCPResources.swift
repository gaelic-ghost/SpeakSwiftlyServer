import Foundation
import MCP
import SpeakSwiftly

private func mapTextProfileResourceError(_ error: any Error) -> MCPError {
    if let error = error as? MCPError {
        return error
    }

    if let error = error as? SpeakSwiftly.Error {
        return .internalError(error.message)
    }

    return .internalError(
        "SpeakSwiftlyServer could not complete the text-profile MCP resource request. Likely cause: \(error.localizedDescription)",
    )
}

enum MCPResourceCatalog {
    static let resourceURIs = Set([
        "speak-swiftly://overview",
        "speak-swiftly://status",
        "speak-swiftly://configuration",
        "speak-swiftly://voices",
        "speak-swiftly://voices/guide",
        "speak-swiftly://text-profiles",
        "speak-swiftly://text-profiles/style",
        "speak-swiftly://text-profiles/guide",
        "speak-swiftly://text-profiles/base",
        "speak-swiftly://text-profiles/active",
        "speak-swiftly://text-profiles/effective",
        "speak-swiftly://playback",
        "speak-swiftly://playback/queue",
        "speak-swiftly://playback/guide",
        "speak-swiftly://requests",
        "speak-swiftly://generation/jobs",
        "speak-swiftly://generation/artifacts",
    ])

    static let resources: [Resource] = [
        .init(name: "Runtime Overview", uri: "speak-swiftly://overview", description: "Shared-host runtime overview with readiness, queues, transports, and recent errors.", mimeType: "application/json"),
        .init(name: "Runtime Status", uri: "speak-swiftly://status", description: "Underlying SpeakSwiftly runtime snapshot, including state, resident-model state, speech backend, storage paths, and default voice profile.", mimeType: "application/json"),
        .init(name: "Runtime Configuration", uri: "speak-swiftly://configuration", description: "Persisted runtime configuration snapshot for the next runtime start, including backend, Qwen resident model, and Marvis resident policy.", mimeType: "application/json"),
        .init(name: "Voice Profiles", uri: "speak-swiftly://voices", description: "Current cached SpeakSwiftly voice profiles.", mimeType: "application/json"),
        .init(name: "Voice Profile Guide", uri: "speak-swiftly://voices/guide", description: "Operator guidance for creating, cloning, renaming, rerolling, deleting, and using SpeakSwiftly voice profiles.", mimeType: "text/markdown"),
        .init(name: "Text Profiles", uri: "speak-swiftly://text-profiles", description: "Current SpeakSwiftly text-profile snapshot, including built-in style plus base, active, stored, and effective profiles.", mimeType: "application/json"),
        .init(name: "Text Profile Style", uri: "speak-swiftly://text-profiles/style", description: "Current built-in SpeakSwiftly text-profile style.", mimeType: "application/json"),
        .init(name: "Text Profile Guide", uri: "speak-swiftly://text-profiles/guide", description: "Operator guidance for working with SpeakSwiftly text profiles and replacements.", mimeType: "text/markdown"),
        .init(name: "Base Text Profile", uri: "speak-swiftly://text-profiles/base", description: "Built-in-style-derived base SpeakSwiftly text profile.", mimeType: "application/json"),
        .init(name: "Active Text Profile", uri: "speak-swiftly://text-profiles/active", description: "Current active custom SpeakSwiftly text profile.", mimeType: "application/json"),
        .init(name: "Effective Text Profile", uri: "speak-swiftly://text-profiles/effective", description: "Default effective SpeakSwiftly text profile after merging base and active custom state.", mimeType: "application/json"),
        .init(name: "Playback State", uri: "speak-swiftly://playback", description: "Current playback state, active request, buffer stability, and latest playback milestone.", mimeType: "application/json"),
        .init(name: "Playback Queue", uri: "speak-swiftly://playback/queue", description: "Current active and queued playback work.", mimeType: "application/json"),
        .init(name: "Playback Guide", uri: "speak-swiftly://playback/guide", description: "Operator guidance for reading queues, controlling playback, and choosing the least destructive action.", mimeType: "text/markdown"),
        .init(name: "Tracked Requests", uri: "speak-swiftly://requests", description: "Retained shared-host request snapshots for live server operations.", mimeType: "application/json"),
        .init(name: "Generation Jobs", uri: "speak-swiftly://generation/jobs", description: "Retained v2 generation jobs known to the SpeakSwiftly runtime.", mimeType: "application/json"),
        .init(name: "Generation Artifacts", uri: "speak-swiftly://generation/artifacts", description: "Retained generated audio artifacts known to the SpeakSwiftly runtime.", mimeType: "application/json"),
    ]

    static let templates: [Resource.Template] = [
        .init(uriTemplate: "speak-swiftly://voices/{profile_name}", name: "Voice Profile Detail", description: "Cached SpeakSwiftly voice profile detail for one profile.", mimeType: "application/json"),
        .init(uriTemplate: "speak-swiftly://text-profiles/stored/{profile_id}", name: "Stored Text Profile", description: "One persisted SpeakSwiftly text profile by profile id.", mimeType: "application/json"),
        .init(uriTemplate: "speak-swiftly://text-profiles/effective/{profile_id}", name: "Effective Stored Text Profile", description: "The effective text profile produced by merging the base profile with one stored profile.", mimeType: "application/json"),
        .init(uriTemplate: "speak-swiftly://requests/{request_id}", name: "Request Detail", description: "Detailed shared-host state for one tracked request.", mimeType: "application/json"),
        .init(uriTemplate: "speak-swiftly://generation/jobs/{job_id}", name: "Generation Job Detail", description: "One retained v2 generation job.", mimeType: "application/json"),
        .init(uriTemplate: "speak-swiftly://generation/artifacts/{artifact_id}", name: "Generation Artifact Detail", description: "One retained generated audio artifact.", mimeType: "application/json"),
    ]
}

// MARK: - Resource Handlers

extension MCPSurface {
    static func registerResourceHandlers(
        on server: Server,
        host: ServerHost,
        subscriptionBroker: MCPSubscriptionBroker,
    ) async {
        await server.withMethodHandler(ListResources.self) { _ in
            .init(resources: MCPResourceCatalog.resources)
        }

        await server.withMethodHandler(ListResourceTemplates.self) { _ in
            .init(templates: MCPResourceCatalog.templates)
        }

        await server.withMethodHandler(ResourceSubscribe.self) { params in
            try ensureKnownResourceURI(params.uri)
            await subscriptionBroker.subscribe(to: params.uri)
            return Empty()
        }

        await server.withMethodHandler(ResourceUnsubscribe.self) { params in
            try ensureKnownResourceURI(params.uri)
            await subscriptionBroker.unsubscribe(from: params.uri)
            return Empty()
        }

        await server.withMethodHandler(ReadResource.self) { params in
            switch params.uri {
                case "speak-swiftly://overview":
                    return try await resourceResult(uri: params.uri, payload: host.statusSnapshot())

                case "speak-swiftly://status":
                    return try await resourceResult(uri: params.uri, payload: host.runtimeStatus())

                case "speak-swiftly://configuration":
                    return try await resourceResult(uri: params.uri, payload: host.runtimeConfigurationSnapshot())

                case "speak-swiftly://voices":
                    return try await resourceResult(uri: params.uri, payload: host.cachedProfiles())

                case "speak-swiftly://voices/guide":
                    return .init(
                        contents: [
                            .text(
                                voiceProfilesGuideMarkdown(),
                                uri: params.uri,
                                mimeType: "text/markdown",
                            ),
                        ],
                    )

                case "speak-swiftly://text-profiles":
                    do {
                        let snapshot = try await host.textProfilesSnapshot()
                        return try resourceResult(uri: params.uri, payload: snapshot)
                    } catch {
                        throw mapTextProfileResourceError(error)
                    }

                case "speak-swiftly://text-profiles/style":
                    return try await resourceResult(uri: params.uri, payload: host.textProfileStyleSnapshot())

                case "speak-swiftly://text-profiles/guide":
                    return .init(
                        contents: [
                            .text(
                                textProfilesGuideMarkdown(),
                                uri: params.uri,
                                mimeType: "text/markdown",
                            ),
                        ],
                    )

                case "speak-swiftly://playback":
                    return try await resourceResult(uri: params.uri, payload: host.playbackStateSnapshot())

                case "speak-swiftly://playback/queue":
                    return try await resourceResult(uri: params.uri, payload: host.playbackQueueSnapshot())

                case "speak-swiftly://playback/guide":
                    return .init(
                        contents: [
                            .text(
                                playbackGuideMarkdown(),
                                uri: params.uri,
                                mimeType: "text/markdown",
                            ),
                        ],
                    )

                case "speak-swiftly://text-profiles/base":
                    do {
                        let snapshot = try await host.textProfilesSnapshot()
                        return try resourceResult(uri: params.uri, payload: snapshot.baseProfile)
                    } catch {
                        throw mapTextProfileResourceError(error)
                    }

                case "speak-swiftly://text-profiles/active":
                    do {
                        let snapshot = try await host.textProfilesSnapshot()
                        return try resourceResult(uri: params.uri, payload: snapshot.activeProfile)
                    } catch {
                        throw mapTextProfileResourceError(error)
                    }

                case "speak-swiftly://text-profiles/effective":
                    do {
                        let profile = try await host.effectiveTextProfile(nil)
                        return try resourceResult(uri: params.uri, payload: profile)
                    } catch {
                        throw mapTextProfileResourceError(error)
                    }

                case "speak-swiftly://requests":
                    return try await resourceResult(uri: params.uri, payload: host.jobSnapshots())

                case "speak-swiftly://generation/jobs":
                    return try await resourceResult(uri: params.uri, payload: host.listGenerationJobs())

                case "speak-swiftly://generation/artifacts":
                    return try await resourceResult(uri: params.uri, payload: host.listGenerationArtifacts())

                default:
                    if let profileName = profileDetailName(from: params.uri) {
                        guard let profile = await host.cachedProfile(profileName) else {
                            throw MCPError.invalidRequest(
                                "No cached SpeakSwiftly profile matched that profile name. Refresh or recreate the profile before requesting detail.",
                            )
                        }

                        return try resourceResult(uri: params.uri, payload: profile)
                    }

                    if let profileID = storedTextProfileID(from: params.uri) {
                        do {
                            guard let profile = try await host.storedTextProfile(profileID) else {
                                throw MCPError.invalidRequest(
                                    "No stored SpeakSwiftly text profile matched that profile id. Read speak-swiftly://text-profiles first to inspect the current stored profile set.",
                                )
                            }

                            return try resourceResult(uri: params.uri, payload: profile)
                        } catch {
                            throw mapTextProfileResourceError(error)
                        }
                    }

                    if let profileID = effectiveTextProfileID(from: params.uri) {
                        do {
                            let profile = try await host.effectiveTextProfile(profileID)
                            return try resourceResult(uri: params.uri, payload: profile)
                        } catch {
                            throw mapTextProfileResourceError(error)
                        }
                    }

                    if let requestID = requestID(from: params.uri) {
                        do {
                            return try await resourceResult(uri: params.uri, payload: host.jobSnapshot(id: requestID))
                        } catch {
                            throw MCPError.invalidRequest(
                                "No tracked SpeakSwiftly request matched that request id. Submit work first, or read speak-swiftly://requests to inspect retained request state.",
                            )
                        }
                    }

                    if let jobID = generationJobID(from: params.uri) {
                        return try await resourceResult(uri: params.uri, payload: host.generationJob(id: jobID))
                    }

                    if let artifactID = generationArtifactID(from: params.uri) {
                        return try await resourceResult(uri: params.uri, payload: host.generationArtifact(id: artifactID))
                    }

                    throw MCPError.invalidRequest(
                        "Resource '\(params.uri)' is not available on this embedded SpeakSwiftly MCP surface.",
                    )
            }
        }
    }
}

// MARK: - Resource Encoding

private func resourceResult(
    uri: String,
    payload: some Encodable,
) throws -> ReadResource.Result {
    let data = try JSONEncoder().encode(payload)
    let json = String(decoding: data, as: UTF8.self)
    return .init(contents: [.text(json, uri: uri, mimeType: "application/json")])
}

// MARK: - Resource Validation

func ensureKnownResourceURI(_ uri: String) throws {
    guard MCPResourceCatalog.resourceURIs.contains(uri)
        || profileDetailName(from: uri) != nil
        || storedTextProfileID(from: uri) != nil
        || effectiveTextProfileID(from: uri) != nil
        || requestID(from: uri) != nil
        || generationJobID(from: uri) != nil
        || generationArtifactID(from: uri) != nil
    else {
        throw MCPError.invalidRequest(
            "Resource '\(uri)' is not available on this embedded SpeakSwiftly MCP surface.",
        )
    }
}

// MARK: - Resource Guides

private func textProfilesGuideMarkdown() -> String {
    """
    # SpeakSwiftly Text Profile Guide

    Use text profiles when a downstream app or agent needs to normalize phrasing before speech generation without changing the underlying voice profile.

    - `base profile`: immutable built-ins that always participate in effective normalization.
    - `built-in style`: the balanced, compact, or explicit built-in normalization mode that shapes the base profile.
    - `active profile`: the current custom profile used by default when no explicit `text_profile_id` is provided during speech submission.
    - `stored profiles`: named reusable normalization policies that an app or agent can apply on demand.
    - `effective profile`: the merged profile SpeakSwiftly will actually apply after combining the base profile with the selected active or stored profile.

    Recommended workflow:

    1. Read `speak-swiftly://text-profiles` to inspect the current built-in style plus base, active, stored, and effective state.
    2. Draft or edit rules with the `draft_text_profile` and `draft_text_replacement` prompts when a user needs help authoring replacements.
    3. Read `speak-swiftly://text-profiles/style` to inspect the built-in normalization mode, and use `set_text_profile_style` only when the operator wants to change it.
    4. Store reusable policies with `create_text_profile`, then use `rename_text_profile` if the operator wants to refine a saved profile name later.
    5. Use `set_active_text_profile` when the downstream app wants to switch the default custom profile, or pass `text_profile_id` on one speech request when the caller wants stored-profile selection without mutating the active profile.
    6. Use `save_text_profiles` when the operator wants an explicit persistence checkpoint, and `load_text_profiles` when another process changed the persistence file and the in-memory state should be refreshed from disk.
    7. Read `speak-swiftly://text-profiles/effective/{profile_id}` before queuing speech if the user wants to verify what normalization will really happen.

    Replacement guidance:

    - Prefer `whole_token` for acronyms, identifiers, and word-level substitutions.
    - Prefer `exact_phrase` for multi-word phrasing that should only fire as a phrase.
    - Use `before_built_ins` when custom text should shape built-in normalization input.
    - Use `after_built_ins` when the custom rule should clean up the normalized output instead.
    - Restrict `formats` when a rule should only apply to source code, CLI output, or other narrow content types.
    """
}

private func voiceProfilesGuideMarkdown() -> String {
    """
    # SpeakSwiftly Voice Profile Guide

    Use voice-profile tools when the user wants to create, import, inspect, rename, reroll, choose, or remove reusable user-owned speaking voices. Package-owned built-ins are ordinary list-and-select choices for users; their bundled resource workflow is owned by SpeakSwiftly.

    Recommended workflow:

    1. Read `speak-swiftly://voices` to inspect the currently cached voice profiles.
    2. Read `speak-swiftly://status` when the user asks which voice an omitted `profile_name` will use. Speech requests use the configured app default voice when present, then the runtime's built-in default voice.
    3. Pass `profile_name` to `generate_speech` when the user wants a specific voice for one request.
    4. Treat system-authored built-ins such as `swift-signal` and `swift-anchor` as list-and-select profiles for ordinary users. They are package-owned defaults, not user-editable profile designs.
    5. Use `create_voice_profile_from_description` when the user wants a new user-owned synthetic profile from source text plus a voice description.
    6. Use `create_voice_profile_from_audio` when the user already has reference audio and wants SpeakSwiftly to capture that voice as a user-owned profile.
    7. Use `update_voice_profile_name` when the user wants to keep a user-owned stored voice but correct or improve its visible profile name.
    8. Use `reroll_voice_profile` when the user wants SpeakSwiftly to rebuild one user-owned stored profile from its original source inputs while keeping the same profile name. System profile rerolls create or target a user-owned copy in SpeakSwiftly rather than mutating the built-in in place.
    9. Provide `transcript` to `create_voice_profile_from_audio` when the user knows the spoken words already; omit it only when transcription is actually needed.
    10. Pass `source_format` to `generate_speech` when source-like input needs explicit format-aware normalization instead of automatic detection. The MCP surface fills client and tool provenance in `request_context` by default; pass `cwd`, `repo_root`, or `request_context` only when path or caller metadata needs to be more specific.
    11. Use `delete_voice_profile` only after confirming the exact `profile_name`, especially when multiple similar profiles exist. Ordinary deletion is for user-owned profiles; system-authored built-ins are maintained by SpeakSwiftly's bundled system-profile install and refresh behavior.

    Drafting guidance:

    - Use `draft_profile_voice_description` when the user is still exploring how a synthetic profile should sound.
    - Use `draft_profile_source_text` when the user needs a good source passage for profile creation.
    - Use `draft_voice_design_instruction` when the user is shaping one spoken line rather than a reusable stored profile.

    Qwen voice-design guidance:

    - Treat Qwen3-TTS VoiceDesign instructions as standalone designs. The model receives the current spoken text plus the current natural-language instruction, not a remembered prior generated voice.
    - When revising a synthetic voice, rewrite the full target voice with both preserved and changed traits. Avoid relative wording such as "same as before", "this voice", or "like the previous one".
    - Describe concrete acoustic traits: timbre, pitch range, pace, affect, breath or texture, and performance style. Mention age, gender presentation, accent, or dialect only when the user asked for them.
    - Use source text that naturally exercises the target cadence and emotion. For many lines that need a stable identity, create or reroll a stored profile from a strong self-contained design, then reuse that stored profile.

    Broad-appeal example names and directions:

    - `swift-lumen`: luminous, clean, gentle, and polished.
    - `swift-arc`: compact, focused, modern, and precise.
    - `swift-melody`: warm, expressive, friendly, and persona-ready.
    - `swift-foundry`: grounded, maker-like, textured, and steady.

    Keep `swift-signal` and `swift-anchor` available for package built-in defaults when the default
    voice catalog is present. Built-in defaults are package-owned seed voices; ordinary user-created
    profiles use `.user` authorship.
    """
}

private func playbackGuideMarkdown() -> String {
    """
    # SpeakSwiftly Playback And Queue Guide

    Use queue and playback tools when the user wants to know what is running, what is waiting, or how to control audible output.

    Recommended workflow:

    1. Read `speak-swiftly://overview` first for a broad overview of worker readiness, queues, playback state, and recent errors.
    2. Read `speak-swiftly://requests` or `speak-swiftly://requests/{request_id}` when the user is asking about one specific server-tracked request.
    3. Use the generation queue in `speak-swiftly://overview` when the question is about what is still generating.
    4. Use the playback queue in `speak-swiftly://overview` when the question is about what is waiting to be heard.
    5. Read `speak-swiftly://overview` before `pause_playback` or `resume_playback` if the user first needs confirmation about whether anything is currently playing.
    6. Use `cancel_request` when the user wants one known request stopped by id.
    7. Add `scope` to `cancel_request` only when the user explicitly wants to constrain cancellation to `generation` or `playback`.
    8. Use `clear_generation_queue` or `clear_playback_queue` when the user wants to drop one waiting backlog without interrupting the active request.

    Safety guidance:

    - Prefer the least destructive control that satisfies the user’s intent.
    - Confirm the target request id before cancelling when multiple queued requests exist.
    - Distinguish generation backlog from playback backlog so the user understands whether work is waiting on model generation or audible output.
    - Playback freshness is currently host-event-driven; until SpeakSwiftly exposes a runtime-level playback event stream, read `speak-swiftly://overview` again when you need the latest state before a destructive playback action.
    """
}

// MARK: - Resource URI Helpers

private func profileDetailName(from uri: String) -> String? {
    let prefix = "speak-swiftly://voices/"
    guard uri.hasPrefix(prefix) else { return nil }

    let profileName = String(uri.dropFirst(prefix.count))
    return profileName.isEmpty ? nil : profileName
}

func isVoiceProfileURI(_ uri: String) -> Bool {
    profileDetailName(from: uri) != nil
}

private func storedTextProfileID(from uri: String) -> String? {
    let prefix = "speak-swiftly://text-profiles/stored/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}

func isStoredTextProfileURI(_ uri: String) -> Bool {
    storedTextProfileID(from: uri) != nil
}

private func effectiveTextProfileID(from uri: String) -> String? {
    let prefix = "speak-swiftly://text-profiles/effective/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}

func isEffectiveTextProfileURI(_ uri: String) -> Bool {
    effectiveTextProfileID(from: uri) != nil
}

private func requestID(from uri: String) -> String? {
    let prefix = "speak-swiftly://requests/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}

private func generationJobID(from uri: String) -> String? {
    let prefix = "speak-swiftly://generation/jobs/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}

private func generationArtifactID(from uri: String) -> String? {
    let prefix = "speak-swiftly://generation/artifacts/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}
