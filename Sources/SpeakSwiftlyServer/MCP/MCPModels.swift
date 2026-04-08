import Foundation
import MCP

// MARK: - MCP Models

struct MCPAcceptedJobResult: Codable, Sendable {
    let jobID: String
    let jobResourceURI: String
    let statusResourceURI: String
    let message: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case jobResourceURI = "job_resource_uri"
        case statusResourceURI = "status_resource_uri"
        case message
    }
}

enum MCPToolCatalog {
    static let definitions: [Tool] = [
        Tool(
            name: "queue_speech_live",
            description: "Queue live speech playback with a stored SpeakSwiftly voice profile. Use this after choosing or creating a voice profile, optionally pass text_profile_name for one-shot normalization, and optionally provide text_format, nested_source_format, or source_format when the input should be normalized as a specific textual or whole-source lane before speech generation.",
            inputSchema: [
                "type": "object",
                "required": ["text", "profile_name"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                    "text_profile_name": ["type": "string"],
                    "cwd": ["type": "string"],
                    "repo_root": ["type": "string"],
                    "text_format": ["type": "string"],
                    "nested_source_format": ["type": "string"],
                    "source_format": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "create_profile",
            description: "Create a new stored SpeakSwiftly voice profile from source text, an explicit vibe, and a voice description. Prefer drafting the text and voice description first when the user is still exploring voice direction, and use output_path when a downstream app wants the generated reference audio file preserved.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "vibe", "text", "voice_description"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "vibe": ["type": "string", "enum": ["masc", "femme", "androgenous"]],
                    "text": ["type": "string"],
                    "voice_description": ["type": "string"],
                    "output_path": ["type": "string"],
                    "cwd": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "create_clone",
            description: "Create a new stored SpeakSwiftly voice clone from local reference audio with an explicit vibe. Provide transcript when the user already knows the spoken text to avoid unnecessary transcription work, otherwise omit it and let SpeakSwiftly infer the transcript internally.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "vibe", "reference_audio_path"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "vibe": ["type": "string", "enum": ["masc", "femme", "androgenous"]],
                    "reference_audio_path": ["type": "string"],
                    "transcript": ["type": "string"],
                    "cwd": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "list_profiles",
            description: "Return the current in-memory snapshot of cached SpeakSwiftly voice profiles. Read this before queueing speech if the user needs help choosing among existing profiles or before deleting a profile by name.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "list_text_profiles",
            description: "Return the current SpeakSwiftly text-profile state, including the base, active, stored, and effective profiles. Read this first when the user wants normalization help or before mutating replacements so the agent can see the current state.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "create_text_profile",
            description: "Create a stored SpeakSwiftly text profile with the provided id, display name, and optional replacement rules. Prefer this when the user needs a reusable named normalization policy rather than a temporary active override.",
            inputSchema: [
                "type": "object",
                "required": ["id", "name"],
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"],
                    "replacements": ["type": "array"],
                ],
            ]
        ),
        Tool(
            name: "load_text_profiles",
            description: "Reload persisted SpeakSwiftly text profiles from the configured persistence file and return the refreshed text-profile snapshot. Use this when another process edited the persistence file or when the operator wants to discard in-memory drift and re-read the saved source of truth.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ]
        ),
        Tool(
            name: "save_text_profiles",
            description: "Persist the current SpeakSwiftly text-profile state to disk and return the latest text-profile snapshot. Use this after a batch of text-profile edits when the operator wants an explicit save step instead of relying on later persistence hooks.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ]
        ),
        Tool(
            name: "store_text_profile",
            description: "Store or replace one persisted SpeakSwiftly text profile by passing the full profile payload. Use this when the agent has already drafted or edited the complete profile shape and wants one full-write operation instead of incremental edits.",
            inputSchema: [
                "type": "object",
                "required": ["profile"],
                "properties": [
                    "profile": ["type": "object"],
                ],
            ]
        ),
        Tool(
            name: "use_text_profile",
            description: "Replace the active SpeakSwiftly custom text profile with the provided full profile payload. Use this for a temporary current-session normalization override when the caller does not want to queue speech with text_profile_name on each request.",
            inputSchema: [
                "type": "object",
                "required": ["profile"],
                "properties": [
                    "profile": ["type": "object"],
                ],
            ]
        ),
        Tool(
            name: "remove_text_profile",
            description: "Remove one stored SpeakSwiftly text profile by profile id. Read speak://text-profiles or list_text_profiles first if the agent needs to confirm the available ids with the user.",
            inputSchema: [
                "type": "object",
                "required": ["profile_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "reset_text_profile",
            description: "Reset the active SpeakSwiftly custom text profile back to the library default. Use this when the user wants to discard temporary active normalization changes without deleting stored text profiles.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ]
        ),
        Tool(
            name: "add_text_replacement",
            description: "Add one text replacement rule to the active custom text profile or to a stored text profile when profile_id is provided. Prefer reading the text-profile guide or using the drafting prompts first when the right match mode, phase, or format scope is unclear.",
            inputSchema: [
                "type": "object",
                "required": ["replacement"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement": ["type": "object"],
                ],
            ]
        ),
        Tool(
            name: "replace_text_replacement",
            description: "Replace one existing text replacement rule in the active custom text profile or in a stored text profile when profile_id is provided. Use this when the replacement id already exists and the user wants to revise its behavior rather than add a second competing rule.",
            inputSchema: [
                "type": "object",
                "required": ["replacement"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement": ["type": "object"],
                ],
            ]
        ),
        Tool(
            name: "remove_text_replacement",
            description: "Remove one text replacement rule from the active custom text profile or from a stored text profile when profile_id is provided. Read the current profile first if the user needs help identifying the replacement id to remove.",
            inputSchema: [
                "type": "object",
                "required": ["replacement_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement_id": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "remove_profile",
            description: "Remove a stored SpeakSwiftly voice profile through the shared server host. Read list_profiles first when the agent needs to confirm profile names or avoid deleting the wrong voice profile.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name"],
                "properties": [
                    "profile_name": ["type": "string"],
                ],
            ]
        ),
        Tool(
            name: "list_queue_generation",
            description: "Return the active SpeakSwiftly generation request plus the currently queued generation work, if any. Use this when the user asks what is still generating or whether a request is waiting behind another one.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "list_queue_playback",
            description: "Return the active SpeakSwiftly playback request plus the currently queued playback work, if any. Use this when the user wants to understand audible playback backlog separately from model generation backlog.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "playback_pause",
            description: "Pause the current SpeakSwiftly playback stream and return the resulting playback state snapshot. Use this only for operator intent to halt audible output temporarily; it does not delete queued work.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ]
        ),
        Tool(
            name: "playback_resume",
            description: "Resume the current SpeakSwiftly playback stream and return the resulting playback state snapshot after a previous pause.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ]
        ),
        Tool(
            name: "playback_state",
            description: "Return the current SpeakSwiftly playback state snapshot, including the active playback request when one exists. Read this before pause or resume if the user first wants to know whether anything is currently playing.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
        Tool(
            name: "clear_queue",
            description: "Cancel all currently queued SpeakSwiftly requests without interrupting the active request. Use this for a broad queue cleanup when the user wants to drop backlog but preserve anything already running.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "cancel_request",
            description: "Cancel one queued or active SpeakSwiftly request by request id. Use this when the user wants to stop one specific request instead of clearing the whole queue.",
            inputSchema: [
                "type": "object",
                "required": ["request_id"],
                "properties": [
                    "request_id": ["type": "string"],
                ],
            ],
            annotations: .init(
                readOnlyHint: false,
                destructiveHint: true,
                idempotentHint: false,
                openWorldHint: false
            )
        ),
        Tool(
            name: "status",
            description: "Report worker readiness, cached profiles, queue state, playback state, recent errors, and transport status from the shared server host. This is the best first read when an agent needs orientation before choosing other tools.",
            inputSchema: [
                "type": "object",
                "properties": [:],
            ],
            annotations: .init(
                readOnlyHint: true,
                destructiveHint: false,
                idempotentHint: true,
                openWorldHint: false
            )
        ),
    ]
}

enum MCPResourceCatalog {
    static let resourceURIs = Set([
        "speak://status",
        "speak://profiles",
        "speak://profiles/guide",
        "speak://text-profiles",
        "speak://text-profiles/guide",
        "speak://playback/guide",
        "speak://text-profiles/base",
        "speak://text-profiles/active",
        "speak://text-profiles/effective",
        "speak://jobs",
        "speak://runtime",
    ])

    static let resources: [Resource] = [
        Resource(
            name: "Speak Status",
            uri: "speak://status",
            description: "Operational summary from the shared SpeakSwiftly server host.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Cached Profiles",
            uri: "speak://profiles",
            description: "Current cached SpeakSwiftly profile snapshot from the shared server host.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Voice Profile Guide",
            uri: "speak://profiles/guide",
            description: "Operator-facing guidance for choosing between creating, cloning, listing, removing, and using SpeakSwiftly voice profiles.",
            mimeType: "text/markdown"
        ),
        Resource(
            name: "Text Profiles",
            uri: "speak://text-profiles",
            description: "Current SpeakSwiftly text-profile state, including the base, active, stored, and effective profiles.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Text Profile Guide",
            uri: "speak://text-profiles/guide",
            description: "Operator-facing guidance for when to use base, active, effective, and stored SpeakSwiftly text profiles.",
            mimeType: "text/markdown"
        ),
        Resource(
            name: "Playback And Queue Guide",
            uri: "speak://playback/guide",
            description: "Operator-facing guidance for reading job status, inspecting queues, and choosing between pause, resume, cancel, and clear operations.",
            mimeType: "text/markdown"
        ),
        Resource(
            name: "Base Text Profile",
            uri: "speak://text-profiles/base",
            description: "The immutable base text profile that SpeakSwiftly merges into every effective text profile.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Active Text Profile",
            uri: "speak://text-profiles/active",
            description: "The current active custom text profile that SpeakSwiftly uses for default normalization.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Effective Text Profile",
            uri: "speak://text-profiles/effective",
            description: "The effective text profile SpeakSwiftly applies by default after merging the base and active custom text profiles.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Tracked Jobs",
            uri: "speak://jobs",
            description: "Current and recently retained SpeakSwiftly job snapshots from the shared server host.",
            mimeType: "application/json"
        ),
        Resource(
            name: "Runtime Summary",
            uri: "speak://runtime",
            description: "Shared host runtime summary, including queue, playback, transport, and recent-error state.",
            mimeType: "application/json"
        ),
    ]

    static let templates: [Resource.Template] = [
        Resource.Template(
            uriTemplate: "speak://profiles/{profile_name}/detail",
            name: "Profile Detail",
            description: "Detailed cached SpeakSwiftly profile information for one profile.",
            mimeType: "application/json"
        ),
        Resource.Template(
            uriTemplate: "speak://text-profiles/stored/{profile_id}",
            name: "Stored Text Profile",
            description: "One persisted SpeakSwiftly text profile by profile id.",
            mimeType: "application/json"
        ),
        Resource.Template(
            uriTemplate: "speak://text-profiles/effective/{profile_id}",
            name: "Effective Stored Text Profile",
            description: "The effective SpeakSwiftly text profile produced by merging the base profile with one stored profile.",
            mimeType: "application/json"
        ),
        Resource.Template(
            uriTemplate: "speak://jobs/{job_id}",
            name: "Job Detail",
            description: "Detailed shared-host state for one tracked SpeakSwiftly job.",
            mimeType: "application/json"
        ),
    ]
}

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
            description: "Create a reusable natural-language voice description suitable for SpeakSwiftly profile creation and Qwen3-TTS-style instruction control.",
            arguments: [
                .init(name: "profile_goal", required: true),
                .init(name: "voice_traits", required: true),
                .init(name: "language"),
                .init(name: "delivery_style"),
                .init(name: "constraints"),
            ]
        ),
        Prompt(
            name: "draft_profile_source_text",
            title: "Draft Profile Source Text",
            description: "Create a spoken sample text that works well as source text for SpeakSwiftly profile creation.",
            arguments: [
                .init(name: "language", required: true),
                .init(name: "persona_or_context", required: true),
                .init(name: "length_hint"),
                .init(name: "style_notes"),
            ]
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
            ]
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
            ]
        ),
        Prompt(
            name: "draft_voice_design_instruction",
            title: "Draft Voice Design Instruction",
            description: "Create a natural-language voice-direction instruction aligned with Qwen3-TTS-style voice design inputs.",
            arguments: [
                .init(name: "spoken_text", required: true),
                .init(name: "emotion", required: true),
                .init(name: "delivery_style", required: true),
                .init(name: "language"),
                .init(name: "constraints"),
            ]
        ),
        Prompt(
            name: "draft_queue_playback_notice",
            title: "Draft Queued Playback Notice",
            description: "Create a short acknowledgement that spoken playback has been queued and tell the operator where to check job status.",
            arguments: [
                .init(name: "spoken_text_summary", required: true),
                .init(name: "job_id", required: true),
                .init(name: "status_resource_uri", required: true),
                .init(name: "tone"),
            ]
        ),
        Prompt(
            name: "choose_surface_action",
            title: "Choose Surface Action",
            description: "Choose the most appropriate SpeakSwiftly MCP tool, resource, or prompt for the user’s request before taking action.",
            arguments: [
                .init(name: "user_goal", required: true),
                .init(name: "current_context"),
                .init(name: "constraints"),
            ]
        ),
    ]
}
