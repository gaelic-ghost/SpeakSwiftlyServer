import Foundation
import MCP
import SpeakSwiftly
import SSSCore

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

package enum MCPResourceCatalog {
    package static let resources: [Resource] = [
        .init(name: "Runtime Overview", uri: "speak-swiftly://overview", description: "Shared-host runtime overview with readiness, queues, transports, and recent errors.", mimeType: "application/json"),
        .init(name: "Voice Profiles", uri: "speak-swiftly://voices", description: "Current cached SpeakSwiftly voice profiles.", mimeType: "application/json"),
        .init(name: "Voice Profile Guide", uri: "speak-swiftly://voices/guide", description: "Operator guidance for creating, cloning, renaming, rerolling, deleting, and using SpeakSwiftly voice profiles.", mimeType: "text/markdown"),
        .init(name: "Text Profiles", uri: "speak-swiftly://text-profiles", description: "Current SpeakSwiftly text-profile snapshot, including built-in style plus base, active, stored, and effective profiles.", mimeType: "application/json"),
        .init(name: "Text Profile Guide", uri: "speak-swiftly://text-profiles/guide", description: "Operator guidance for working with SpeakSwiftly text profiles and replacements.", mimeType: "text/markdown"),
        .init(name: "Playback State", uri: "speak-swiftly://playback", description: "Current playback state, active request, buffer stability, and latest playback milestone.", mimeType: "application/json"),
        .init(name: "Playback Guide", uri: "speak-swiftly://playback/guide", description: "Operator guidance for reading queues, controlling playback, and choosing the least destructive action.", mimeType: "text/markdown"),
    ]

    package static let templates: [Resource.Template] = [
        .init(uriTemplate: "speak-swiftly://requests/{request_id}", name: "Request Detail", description: "Detailed shared-host state for one tracked request.", mimeType: "application/json"),
    ]

    static let resourceURIs = Set(resources.map(\.uri))
}

// MARK: - Resource Handlers

package extension MCPSurface {
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

                default:
                    if let requestID = requestID(from: params.uri) {
                        do {
                            return try await resourceResult(uri: params.uri, payload: host.jobSnapshot(id: requestID))
                        } catch {
                            throw MCPError.invalidRequest(
                                "No tracked SpeakSwiftly request matched that request id. Submit work first, or read speak-swiftly://overview to inspect current request and queue state.",
                            )
                        }
                    }

                    throw MCPError.invalidRequest(
                        "Resource '\(params.uri)' is not available on this slim SpeakSwiftly MCP surface. Use HTTP endpoints for detailed runtime, voice, text-profile, playback queue, network-audio, retained generation, and artifact inspection.",
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

package func ensureKnownResourceURI(_ uri: String) throws {
    guard MCPResourceCatalog.resourceURIs.contains(uri)
        || requestID(from: uri) != nil
    else {
        throw MCPError.invalidRequest(
            "Resource '\(uri)' is not available on this slim SpeakSwiftly MCP surface. Use HTTP endpoints for detailed runtime, voice, text-profile, playback queue, network-audio, retained generation, and artifact inspection.",
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
    3. Use the HTTP text-profile endpoints when the operator wants to change built-in style, create profiles, rename profiles, choose the active profile, or edit replacement rules.
    4. Pass `text_profile_id` on `generate_speech` when the caller wants stored-profile selection for one spoken request without mutating the active profile.
    5. Use `GET /text-profiles/effective/{profile_id}` before queuing speech if the user wants to verify what normalization will really happen.

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

    Use the MCP voice-profile resources and prompts to inspect and draft voice choices. Use HTTP voice-profile endpoints when the user wants to create, import, rename, reroll, or remove reusable user-owned speaking voices. Package-owned built-ins are ordinary list-and-select choices for users; their bundled resource workflow is owned by SpeakSwiftly.

    Recommended workflow:

    1. Read `speak-swiftly://voices` to inspect the currently cached voice profiles.
    2. Read `speak-swiftly://overview` when the user asks which voice an omitted `profile_name` will use. Speech requests use the configured app default voice when present, then the runtime's built-in default voice.
    3. Pass `profile_name` to `generate_speech` when the user wants a specific voice for one request. Omit `generation_location` or use `local` for generation on this server. Use a remote generation location only when the caller intentionally wants another SpeakSwiftlyServer to generate `/speech/stream` while this server owns playback or selected LAN receiver output.
    4. Treat system-authored built-ins such as `swift-signal` and `swift-anchor` as list-and-select profiles for ordinary users. They are package-owned defaults, not user-editable profile designs.
    5. Use `POST /voices/from-description` when the user wants a new user-owned synthetic profile from source text plus a voice description.
    6. Use `POST /voices/from-audio` when the user already has reference audio and wants SpeakSwiftly to capture that voice as a user-owned profile.
    7. Use `PUT /voices/{profile_name}/name` when the user wants to keep a user-owned stored voice but correct or improve its visible profile name.
    8. Use `POST /voices/{profile_name}/reroll` when the user wants SpeakSwiftly to rebuild one user-owned stored profile from its original source inputs while keeping the same profile name. System profile rerolls create or target a user-owned copy in SpeakSwiftly rather than mutating the built-in in place.
    9. Provide `transcript` to `POST /voices/from-audio` when the user knows the spoken words already; omit it only when transcription is actually needed.
    10. The MCP surface applies request purpose from the selected tool and fills client and tool provenance by default; pass `cwd`, `repo_root`, or `request_context` only when path or caller metadata needs to be more specific. Caller-provided `request_context` may include `source`, `topic`, `cwd`, `repo_root`, `attributes`, and optional `prefacePolicy`; omit `prefacePolicy` to use the default behavior.
    11. Use `DELETE /voices/{profile_name}` only after confirming the exact `profile_name`, especially when multiple similar profiles exist. Ordinary deletion is for user-owned profiles; system-authored built-ins are maintained by SpeakSwiftly's bundled system-profile install and refresh behavior.

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

    Use playback resources and HTTP controls when the user wants to know what is running, what is waiting, or how to control audible output.

    Recommended workflow:

    1. Read `speak-swiftly://overview` first for a broad overview of worker readiness, queues, playback state, and recent errors.
    2. Read `speak-swiftly://requests/{request_id}` when the user is asking about one specific server-tracked request returned by `generate_speech`.
    3. Use the generation queue in `speak-swiftly://overview` when the question is about what is still generating.
    4. Use the playback queue in `speak-swiftly://overview` when the question is about what is waiting to be heard.
    5. Read `speak-swiftly://overview` before `POST /playback/pause` or `POST /playback/resume` if the user first needs confirmation about whether anything is currently playing.
    6. Use `DELETE /requests/{request_id}` when the user wants one known request stopped by id.
    7. Add the HTTP `scope` query parameter only when the user explicitly wants to constrain cancellation to `generation` or `playback`.
    8. Use `DELETE /generation/queue` or `DELETE /playback/queue` when the user wants to drop one waiting backlog without interrupting the active request.
    9. Use `GET /playback/recent-generated-audio` before replaying audio the user missed, then use the HTTP recent-audio replay endpoints for one item or all complete recent items.
    10. Use `DELETE /playback/recent-generated-audio` only when the user wants to discard the bounded in-memory replay cache; this does not remove retained generated-file artifacts.

    Safety guidance:

    - Prefer the least destructive control that satisfies the user’s intent.
    - Confirm the target request id before cancelling when multiple queued requests exist.
    - Confirm the recent audio id before replaying one item when multiple recent items exist.
    - Distinguish generation backlog from playback backlog so the user understands whether work is waiting on model generation or audible output.
    - Distinguish recent in-memory replay from generated-file artifact playback; file-backed playback is not part of this surface yet.
    - Playback freshness is currently host-event-driven; until SpeakSwiftly exposes a runtime-level playback event stream, read `speak-swiftly://overview` again when you need the latest state before a destructive playback action.
    """
}

// MARK: - Resource URI Helpers

private func requestID(from uri: String) -> String? {
    let prefix = "speak-swiftly://requests/"
    guard uri.hasPrefix(prefix) else { return nil }

    return String(uri.dropFirst(prefix.count))
}
