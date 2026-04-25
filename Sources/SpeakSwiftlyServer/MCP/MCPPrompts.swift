import Foundation
import MCP

enum MCPPromptCatalog {
    static let promptNames = Set([
        "draft_profile_voice_description",
        "draft_profile_source_text",
        "draft_text_profile",
        "draft_text_replacement",
        "draft_voice_design_instruction",
        "draft_queue_playback_notice",
        "choose_surface_action",
    ])

    static let prompts: [Prompt] = [
        Prompt(
            name: "draft_profile_voice_description",
            title: "Draft Profile Voice Description",
            description: "Create a reusable natural-language voice description suitable for SpeakSwiftly profile creation and voice-design control.",
            arguments: [
                .init(name: "profile_goal", required: true),
                .init(name: "voice_traits", required: true),
                .init(name: "language"),
                .init(name: "delivery_style"),
                .init(name: "constraints"),
            ],
        ),
        Prompt(
            name: "draft_profile_source_text",
            title: "Draft Profile Source Text",
            description: "Create a spoken sample text that works well as source text for SpeakSwiftly voice-profile creation.",
            arguments: [
                .init(name: "language", required: true),
                .init(name: "persona_or_context", required: true),
                .init(name: "length_hint"),
                .init(name: "style_notes"),
            ],
        ),
        Prompt(
            name: "draft_text_profile",
            title: "Draft Text Profile",
            description: "Draft a stored SpeakSwiftly text profile id, display name, and initial replacement plan for a downstream app or agent workflow.",
            arguments: [
                .init(name: "user_goal", required: true),
                .init(name: "profile_scope", required: true),
                .init(name: "format_focus"),
                .init(name: "constraints"),
            ],
        ),
        Prompt(
            name: "draft_text_replacement",
            title: "Draft Text Replacement",
            description: "Draft one SpeakSwiftly text replacement rule with the right match mode, phase, casing, and format scope.",
            arguments: [
                .init(name: "original_text", required: true),
                .init(name: "desired_output", required: true),
                .init(name: "usage_context", required: true),
                .init(name: "format_focus"),
                .init(name: "constraints"),
            ],
        ),
        Prompt(
            name: "draft_voice_design_instruction",
            title: "Draft Voice Design Instruction",
            description: "Create a natural-language voice-direction instruction aligned with SpeakSwiftly voice-design inputs.",
            arguments: [
                .init(name: "spoken_text", required: true),
                .init(name: "emotion", required: true),
                .init(name: "delivery_style", required: true),
                .init(name: "language"),
                .init(name: "constraints"),
            ],
        ),
        Prompt(
            name: "draft_queue_playback_notice",
            title: "Draft Queued Playback Notice",
            description: "Create a short acknowledgement that spoken playback has been queued and tell the operator where to check request status.",
            arguments: [
                .init(name: "spoken_text_summary", required: true),
                .init(name: "request_id", required: true),
                .init(name: "status_resource_uri", required: true),
                .init(name: "tone"),
            ],
        ),
        Prompt(
            name: "choose_surface_action",
            title: "Choose Surface Action",
            description: "Choose the most appropriate SpeakSwiftly MCP tool, resource, or prompt for the user’s request before taking action.",
            arguments: [
                .init(name: "user_goal", required: true),
                .init(name: "current_context"),
                .init(name: "constraints"),
            ],
        ),
    ]
}

// MARK: - Prompt Handlers

extension MCPSurface {
    static func registerPromptHandlers(on server: Server) async {
        await server.withMethodHandler(ListPrompts.self) { _ in
            .init(prompts: MCPPromptCatalog.prompts)
        }

        await server.withMethodHandler(GetPrompt.self) { params in
            let arguments = params.arguments ?? [:]

            switch params.name {
                case "draft_profile_voice_description":
                    let profileGoal = try requiredPromptString("profile_goal", in: arguments)
                    let voiceTraits = try requiredPromptString("voice_traits", in: arguments)
                    let constraints = textIfPresent("constraints", in: arguments)
                    let deliveryStyle = textIfPresent("delivery_style", in: arguments)
                    let body = """
                    Write exactly one concise natural-language voice description for a reusable speech profile.
                    Profile goal: \(profileGoal)
                    Primary language: \(textIfPresent("language", in: arguments) ?? "Auto")
                    Requested voice traits: \(voiceTraits)
                    \(deliveryStyle.map { "Delivery style guidance: \($0)" } ?? "")
                    \(constraints.map { "Additional constraints: \($0)" } ?? "")
                    Focus on concrete timbre, affect, pacing, and speaking texture. Mention age or gender presentation only if explicitly requested above. Do not add bullets, labels, surrounding explanation, or more than one candidate.
                    """
                    return .init(
                        description: "Reusable authoring prompt for profile voice descriptions.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "draft_profile_source_text":
                    let language = try requiredPromptString("language", in: arguments)
                    let personaOrContext = try requiredPromptString("persona_or_context", in: arguments)
                    let body = """
                    Write spoken sample text for a voice-profile creation flow.
                    Language: \(language)
                    Persona or context: \(personaOrContext)
                    Length hint: \(textIfPresent("length_hint", in: arguments) ?? "short paragraph")
                    \(textIfPresent("style_notes", in: arguments).map { "Style notes: \($0)" } ?? "")
                    The text should sound natural when read aloud, include enough phrasing variation to show rhythm and expression, and avoid meta commentary. Return only the sample text.
                    """
                    return .init(
                        description: "Reusable authoring prompt for profile source text.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "draft_text_profile":
                    let userGoal = try requiredPromptString("user_goal", in: arguments)
                    let profileScope = try requiredPromptString("profile_scope", in: arguments)
                    let body = """
                    Draft exactly one initial SpeakSwiftly text profile plan for a downstream app or agent workflow.
                    User goal: \(userGoal)
                    Profile scope: \(profileScope)
                    Format focus: \(textIfPresent("format_focus", in: arguments) ?? "general")
                    \(textIfPresent("constraints", in: arguments).map { "Constraints: \($0)" } ?? "")
                    Return concise JSON with keys id, name, and replacements. Use a stable lowercase id with hyphens, a human-readable display name, and a short replacements array that only includes high-confidence initial rules.
                    """
                    return .init(
                        description: "Reusable authoring prompt for an initial stored text profile.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "draft_text_replacement":
                    let originalText = try requiredPromptString("original_text", in: arguments)
                    let desiredOutput = try requiredPromptString("desired_output", in: arguments)
                    let usageContext = try requiredPromptString("usage_context", in: arguments)
                    let body = """
                    Draft exactly one SpeakSwiftly text replacement rule.
                    Original text: \(originalText)
                    Desired output: \(desiredOutput)
                    Usage context: \(usageContext)
                    Format focus: \(textIfPresent("format_focus", in: arguments) ?? "general")
                    \(textIfPresent("constraints", in: arguments).map { "Constraints: \($0)" } ?? "")
                    Return concise JSON with keys id, text, replacement, match, phase, is_case_sensitive, formats, and priority. Prefer whole_token when the rule should not fire inside larger words, and use exact_phrase when multi-word phrasing matters.
                    """
                    return .init(
                        description: "Reusable authoring prompt for one text replacement rule.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "draft_voice_design_instruction":
                    let spokenText = try requiredPromptString("spoken_text", in: arguments)
                    let emotion = try requiredPromptString("emotion", in: arguments)
                    let deliveryStyle = try requiredPromptString("delivery_style", in: arguments)
                    let body = """
                    Write exactly one natural-language instruction for a speech generation model that supports voice-design style prompting.
                    Spoken text: \(spokenText)
                    Language: \(textIfPresent("language", in: arguments) ?? "Auto")
                    Target emotion: \(emotion)
                    Delivery style: \(deliveryStyle)
                    \(textIfPresent("constraints", in: arguments).map { "Additional constraints: \($0)" } ?? "")
                    Describe how the line should sound without rewriting the spoken text. Focus on tone, pacing, emphasis, and prosody. Return only the instruction.
                    """
                    return .init(
                        description: "Reusable authoring prompt for future voice-design instructions.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "draft_queue_playback_notice":
                    let spokenTextSummary = try requiredPromptString("spoken_text_summary", in: arguments)
                    let requestID = try requiredPromptString("request_id", in: arguments)
                    let statusResourceURI = try requiredPromptString("status_resource_uri", in: arguments)
                    let body = """
                    Write exactly one short operator-facing acknowledgement for a speech request that was accepted by the shared SpeakSwiftly server host.
                    Spoken text summary: \(spokenTextSummary)
                    Shared host request id: \(requestID)
                    Status resource URI: \(statusResourceURI)
                    Requested tone: \(textIfPresent("tone", in: arguments) ?? "calm and direct")
                    State that the request was accepted and queued or running under the shared host, avoid promising that playback has already finished, and point to the status resource for follow-up. Return only the acknowledgement text.
                    """
                    return .init(
                        description: "Reusable operator-facing prompt for accepted speech-request notices.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                case "choose_surface_action":
                    let userGoal = try requiredPromptString("user_goal", in: arguments)
                    let body = """
                    Choose the most appropriate SpeakSwiftly MCP next step for the user request below.
                    User goal: \(userGoal)
                    Current context: \(textIfPresent("current_context", in: arguments) ?? "unknown")
                    \(textIfPresent("constraints", in: arguments).map { "Constraints: \($0)" } ?? "")
                    Available action families:
                    - voice profile work: create_voice_profile_from_description, create_voice_profile_from_audio, list_voice_profiles, update_voice_profile_name, reroll_voice_profile, delete_voice_profile, speak://voices, speak://voices/guide
                    - speech and retained generation: generate_speech, generate_audio_file, generate_batch, speak://requests/{request_id}, speak://generation/jobs, speak://generation/files, speak://generation/batches
                    - text profile work: get_text_normalizer_snapshot, load_text_profiles, save_text_profiles, create_text_profile, rename_text_profile, set_active_text_profile, delete_text_profile, factory_reset_text_profiles, reset_text_profile, add_text_replacement, replace_text_replacement, remove_text_replacement, speak://text-profiles, speak://text-profiles/guide
                    - playback and queue control: list_generation_queue, list_playback_queue, get_playback_state, pause_playback, resume_playback, clear_playback_queue, cancel_request, speak://playback/guide
                    - runtime controls: get_runtime_overview, get_runtime_status, get_staged_runtime_config, set_staged_config, switch_speech_backend, reload_models, unload_models, speak://runtime/overview, speak://runtime/status, speak://runtime/configuration
                    - drafting help: draft_profile_voice_description, draft_profile_source_text, draft_text_profile, draft_text_replacement, draft_voice_design_instruction, draft_queue_playback_notice
                    Return concise JSON with keys action_type, target_name, why, and suggested_follow_up. action_type must be one of tool, resource, or prompt.
                    """
                    return .init(
                        description: "Reusable routing prompt for choosing the right SpeakSwiftly MCP action.",
                        messages: [.user(.text(text: compactPrompt(body)))],
                    )

                default:
                    throw MCPError.methodNotFound(
                        "Prompt '\(params.name)' is not registered on this embedded SpeakSwiftly MCP surface.",
                    )
            }
        }
    }
}

// MARK: - Prompt Helpers

private func requiredPromptString(_ key: String, in arguments: [String: String]) throws -> String {
    guard let value = textIfPresent(key, in: arguments) else {
        throw MCPError.invalidParams(
            "Prompt arguments are missing the required string field '\(key)'.",
        )
    }

    return value
}

private func textIfPresent(_ key: String, in arguments: [String: String]) -> String? {
    guard let value = arguments[key]?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
        return nil
    }

    return value
}

private func compactPrompt(_ raw: String) -> String {
    raw
        .split(separator: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { $0.isEmpty == false }
        .joined(separator: "\n")
}
