import Foundation
import MCP

enum MCPToolCatalog {
    static let definitions: [Tool] = [
        Tool(
            name: "generate_speech",
            description: "Queue live speech playback with a stored SpeakSwiftly voice profile. Use this when the user wants audible output now, and optionally provide profile_name to override the server's configured default voice profile plus text_profile_id, request_context, and explicit normalization-format arguments when the input should not rely on automatic format detection.",
            inputSchema: [
                "type": "object",
                "required": ["text"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                    "text_profile_id": ["type": "string"],
                    "request_context": ["type": "object"],
                    "cwd": ["type": "string"],
                    "repo_root": ["type": "string"],
                    "text_format": ["type": "string"],
                    "nested_source_format": ["type": "string"],
                    "source_format": ["type": "string"],
                    "qwen_pre_model_text_chunking": ["type": "boolean"],
                ],
            ],
        ),
        Tool(
            name: "generate_audio_file",
            description: "Queue one retained generated-audio file instead of live playback. Use this when the user wants a saved artifact they can inspect or reuse later, and optionally provide profile_name to override the server's configured default voice profile plus request_context when the downstream artifact should retain caller metadata.",
            inputSchema: [
                "type": "object",
                "required": ["text"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                    "text_profile_id": ["type": "string"],
                    "request_context": ["type": "object"],
                    "cwd": ["type": "string"],
                    "repo_root": ["type": "string"],
                    "text_format": ["type": "string"],
                    "nested_source_format": ["type": "string"],
                    "source_format": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "generate_batch",
            description: "Queue a retained generated-audio batch from multiple items under one voice profile. Use this when the user wants several output files produced together, and optionally provide profile_name to override the server's configured default voice profile. Each item may carry its own request_context payload.",
            inputSchema: [
                "type": "object",
                "required": ["items"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "items": ["type": "array"],
                ],
            ],
        ),
        Tool(
            name: "create_voice_profile_from_description",
            description: "Create a new stored SpeakSwiftly voice profile from source text, an explicit vibe, and a voice description.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "vibe", "text", "voice_description"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "vibe": ["type": "string", "enum": ["masc", "femme"]],
                    "text": ["type": "string"],
                    "voice_description": ["type": "string"],
                    "output_path": ["type": "string"],
                    "cwd": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "create_voice_profile_from_audio",
            description: "Create a new stored SpeakSwiftly voice clone from local reference audio with an explicit vibe.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "vibe", "reference_audio_path"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "vibe": ["type": "string", "enum": ["masc", "femme"]],
                    "reference_audio_path": ["type": "string"],
                    "transcript": ["type": "string"],
                    "cwd": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "list_voice_profiles",
            description: "Return the current in-memory snapshot of cached SpeakSwiftly voice profiles.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "update_voice_profile_name",
            description: "Rename one stored SpeakSwiftly voice profile and refresh the cached profile list.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "new_profile_name"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "new_profile_name": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "reroll_voice_profile",
            description: "Rebuild one stored SpeakSwiftly voice profile from its persisted source inputs without changing its profile name.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name"],
                "properties": [
                    "profile_name": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "delete_voice_profile",
            description: "Remove one stored SpeakSwiftly voice profile by profile_name.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name"],
                "properties": [
                    "profile_name": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "get_runtime_overview",
            description: "Return the shared-host runtime overview with readiness, queues, playback state, transports, and recent errors. This is the best first read when an agent needs orientation.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_runtime_status",
            description: "Return the underlying SpeakSwiftly runtime status event, including stage, resident model state, and active speech backend.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_staged_runtime_config",
            description: "Return the staged persisted runtime-configuration snapshot that will apply on the next runtime start, including active and next-start backend, Qwen resident model, Marvis resident policy, and environment overrides.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "set_staged_config",
            description: "Persist runtime startup choices for the next runtime start without hot-swapping the current worker. speech_backend stays required for compatibility; qwen_resident_model and marvis_resident_policy are optional startup-only refinements.",
            inputSchema: [
                "type": "object",
                "required": ["speech_backend"],
                "properties": [
                    "speech_backend": ["type": "string", "enum": stringEnum(exposedSpeechBackendIdentifiers())],
                    "qwen_resident_model": ["type": "string", "enum": stringEnum(exposedQwenResidentModelIdentifiers())],
                    "marvis_resident_policy": ["type": "string", "enum": stringEnum(exposedMarvisResidentPolicyIdentifiers())],
                ],
            ],
        ),
        Tool(
            name: "switch_speech_backend",
            description: "Queue an ordered switch for the already-running SpeakSwiftly runtime to move to a different active speech backend. The returned request can be observed while the runtime waits for active work to settle.",
            inputSchema: [
                "type": "object",
                "required": ["speech_backend"],
                "properties": [
                    "speech_backend": ["type": "string", "enum": stringEnum(exposedSpeechBackendIdentifiers())],
                ],
            ],
        ),
        Tool(
            name: "reload_models",
            description: "Ask the already-running SpeakSwiftly runtime to reload its resident models.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "unload_models",
            description: "Ask the already-running SpeakSwiftly runtime to unload its resident models.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "get_text_normalizer_snapshot",
            description: "Return the full SpeakSwiftly text-normalizer snapshot, including built-in style plus base, active, stored, and effective profiles.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_text_profile_style",
            description: "Return the current built-in SpeakSwiftly text-profile style that shapes normalization before custom profile merges.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "set_text_profile_style",
            description: "Set the built-in SpeakSwiftly text-profile style. This changes the base normalization behavior used alongside custom profiles.",
            inputSchema: [
                "type": "object",
                "required": ["built_in_style"],
                "properties": [
                    "built_in_style": ["type": "string", "enum": ["balanced", "compact", "explicit"]],
                ],
            ],
        ),
        Tool(
            name: "create_text_profile",
            description: "Create a stored SpeakSwiftly text profile with the provided name and optional replacement rules.",
            inputSchema: [
                "type": "object",
                "required": ["name"],
                "properties": [
                    "name": ["type": "string"],
                    "replacements": ["type": "array"],
                ],
            ],
        ),
        Tool(
            name: "load_text_profiles",
            description: "Reload persisted SpeakSwiftly text profiles from disk and return the refreshed text-profile state.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "save_text_profiles",
            description: "Persist the current SpeakSwiftly text-profile state to disk and return the refreshed text-profile state.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "rename_text_profile",
            description: "Rename one stored SpeakSwiftly text profile by profile_id.",
            inputSchema: [
                "type": "object",
                "required": ["profile_id", "name"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "name": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "set_active_text_profile",
            description: "Set one stored SpeakSwiftly text profile as the active custom profile by profile_id.",
            inputSchema: [
                "type": "object",
                "required": ["profile_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "delete_text_profile",
            description: "Remove one stored SpeakSwiftly text profile by profile_id.",
            inputSchema: [
                "type": "object",
                "required": ["profile_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "factory_reset_text_profiles",
            description: "Delete all stored SpeakSwiftly text profiles and restore the library default active profile state.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "reset_text_profile",
            description: "Reset one stored SpeakSwiftly text profile back to its library default contents by profile_id.",
            inputSchema: [
                "type": "object",
                "required": ["profile_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "add_text_replacement",
            description: "Add one text replacement rule to the active custom text profile or to a stored text profile when profile_id is provided.",
            inputSchema: [
                "type": "object",
                "required": ["replacement"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement": ["type": "object"],
                ],
            ],
        ),
        Tool(
            name: "replace_text_replacement",
            description: "Replace one existing text replacement rule in the active custom text profile or in a stored text profile when profile_id is provided.",
            inputSchema: [
                "type": "object",
                "required": ["replacement"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement": ["type": "object"],
                ],
            ],
        ),
        Tool(
            name: "remove_text_replacement",
            description: "Remove one text replacement rule from the active custom text profile or from a stored text profile when profile_id is provided.",
            inputSchema: [
                "type": "object",
                "required": ["replacement_id"],
                "properties": [
                    "profile_id": ["type": "string"],
                    "replacement_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "list_generation_queue",
            description: "Return the current generation queue snapshot for the shared SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "list_playback_queue",
            description: "Return the current playback queue snapshot for the shared SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_playback_state",
            description: "Return the current SpeakSwiftly playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "pause_playback",
            description: "Pause the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "resume_playback",
            description: "Resume the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "clear_playback_queue",
            description: "Cancel all currently queued SpeakSwiftly playback work without interrupting the active request.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false),
        ),
        Tool(
            name: "cancel_request",
            description: "Cancel one queued or active SpeakSwiftly request by request_id.",
            inputSchema: [
                "type": "object",
                "required": ["request_id"],
                "properties": [
                    "request_id": ["type": "string"],
                ],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false),
        ),
        Tool(
            name: "list_active_requests",
            description: "Return the shared-host retained request snapshots for active and recently tracked live server operations such as generation, voice creation, and playback control.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "list_generation_jobs",
            description: "Return the retained v2 generation jobs known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_generation_job",
            description: "Return one retained v2 generation job by job_id.",
            inputSchema: [
                "type": "object",
                "required": ["job_id"],
                "properties": [
                    "job_id": ["type": "string"],
                ],
            ],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "expire_generation_job",
            description: "Expire one retained v2 generation job by job_id.",
            inputSchema: [
                "type": "object",
                "required": ["job_id"],
                "properties": [
                    "job_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "list_generated_files",
            description: "Return retained generated audio files known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_generated_file",
            description: "Return one retained generated audio file by artifact_id.",
            inputSchema: [
                "type": "object",
                "required": ["artifact_id"],
                "properties": [
                    "artifact_id": ["type": "string"],
                ],
            ],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "list_generated_batches",
            description: "Return retained generated audio batches known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
        Tool(
            name: "get_generated_batch",
            description: "Return one retained generated audio batch by batch_id.",
            inputSchema: [
                "type": "object",
                "required": ["batch_id"],
                "properties": [
                    "batch_id": ["type": "string"],
                ],
            ],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false),
        ),
    ]

    private static func stringEnum(_ values: [String]) -> Value {
        .array(values.map { .string($0) })
    }
}
