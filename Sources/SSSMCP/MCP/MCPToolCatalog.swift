import Foundation
import MCP
import SpeakSwiftly
import SSSCore

package enum MCPToolCatalog {
    package static let definitions: [Tool] = [
        Tool(
            name: "generate_speech",
            description: "Queue live speech playback with a stored SpeakSwiftly voice profile. Use this when the user wants audible output now. The server applies live-speech purpose plus MCP client and tool provenance by default; optionally provide profile_name to override the server's configured default voice profile plus text_profile_id, request_context, cwd, and repo_root when the input needs richer caller metadata. request_context.prefacePolicy may be default, always, or never.",
            inputSchema: [
                "type": "object",
                "required": ["text"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                    "text_profile_id": ["type": "string"],
                    "request_context": requestContextInputSchema,
                    "cwd": ["type": "string"],
                    "repo_root": ["type": "string"],
                    "qwen_pre_model_text_chunking": ["type": "boolean"],
                    "generation_location": generationLocationInputSchema,
                ],
            ],
        ),
        Tool(
            name: "generate_audio_file",
            description: "Queue one retained generated-audio file instead of live playback. Use this when the user wants a saved artifact they can inspect or reuse later. The server applies retained-audio purpose plus MCP client and tool provenance by default; optionally provide profile_name to override the server's configured default voice profile plus request_context when the downstream artifact should retain richer caller metadata. request_context.prefacePolicy may be default, always, or never.",
            inputSchema: [
                "type": "object",
                "required": ["text"],
                "properties": [
                    "text": ["type": "string"],
                    "profile_name": ["type": "string"],
                    "text_profile_id": ["type": "string"],
                    "request_context": requestContextInputSchema,
                    "cwd": ["type": "string"],
                    "repo_root": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "generate_batch",
            description: "Queue a retained generated-audio batch from multiple items under one voice profile. Use this when the user wants several output files produced together. The server applies retained-audio purpose plus MCP client and tool provenance to each item by default; optionally provide profile_name to override the server's configured default voice profile. Each item may carry its own request_context payload, including optional prefacePolicy.",
            inputSchema: [
                "type": "object",
                "required": ["items"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "items": [
                        "type": "array",
                        "items": batchItemInputSchema,
                    ],
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
            name: "set_runtime_configuration",
            description: "Persist next-start runtime settings without hot-swapping the current worker. speech_backend is required. duck_media_volume is optional and may be off, a_little, default, or a_lot.",
            inputSchema: [
                "type": "object",
                "required": ["speech_backend"],
                "properties": [
                    "speech_backend": ["type": "string", "enum": stringEnum(exposedSpeechBackendIdentifiers())],
                    "duck_media_volume": ["type": "string", "enum": stringEnum(SpeakSwiftly.DuckMediaVolume.allCases.map(\.rawValue))],
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
            name: "pause_playback",
            description: "Pause the current SpeakSwiftly playback stream and return the resulting playback snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "resume_playback",
            description: "Resume the current SpeakSwiftly playback stream and return the resulting playback snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "select_network_audio_receiver",
            description: "Select one Bonjour-discovered SpeakSwiftly LAN audio receiver by destination_id. Remote generation requests route returned audio chunks to the selected receiver when LAN output readiness is true.",
            inputSchema: [
                "type": "object",
                "required": ["destination_id"],
                "properties": [
                    "destination_id": ["type": "string"],
                ],
            ],
        ),
        Tool(
            name: "clear_network_audio_receiver",
            description: "Clear the selected SpeakSwiftly LAN audio receiver destination.",
            inputSchema: ["type": "object", "properties": [:]],
        ),
        Tool(
            name: "clear_generation_queue",
            description: "Cancel all currently queued SpeakSwiftly generation work without interrupting the active generation request.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false),
        ),
        Tool(
            name: "clear_playback_queue",
            description: "Cancel all currently queued SpeakSwiftly playback work without interrupting the active request.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false),
        ),
        Tool(
            name: "cancel_request",
            description: "Cancel one queued or active SpeakSwiftly request by request_id. Optionally set scope to generation or playback when the caller needs queue-specific protection.",
            inputSchema: [
                "type": "object",
                "required": ["request_id"],
                "properties": [
                    "request_id": ["type": "string"],
                    "scope": [
                        "type": "string",
                        "enum": stringEnum(RequestCancellationScope.allCases.map(\.rawValue)),
                        "description": "Optional queue scope. Omit scope to cancel the request wherever it currently lives.",
                    ],
                ],
            ],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false),
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
    ]

    private static let requestContextInputSchema: Value = .object([
        "type": "object",
        "properties": .object([
            "source": ["type": "string"],
            "topic": ["type": "string"],
            "cwd": ["type": "string"],
            "repo_root": ["type": "string"],
            "attributes": [
                "type": "object",
                "additionalProperties": ["type": "string"],
            ],
            "prefacePolicy": [
                "type": "string",
                "enum": ["default", "always", "never"],
            ],
        ]),
        "additionalProperties": false,
    ])

    private static let generationLocationInputSchema: Value = .object([
        "oneOf": .array([
            .object([
                "type": "string",
                "enum": ["local"],
            ]),
            .object([
                "type": "object",
                "required": ["kind"],
                "properties": .object([
                    "kind": [
                        "type": "string",
                        "enum": ["local", "remote"],
                    ],
                    "remote": [
                        "type": "object",
                        "required": ["base_url"],
                        "properties": [
                            "base_url": ["type": "string"],
                            "service_name": ["type": "string"],
                        ],
                    ],
                ]),
            ]),
        ]),
    ])

    private static let batchItemInputSchema: Value = .object([
        "type": "object",
        "required": ["text"],
        "properties": .object([
            "artifact_id": ["type": "string"],
            "text": ["type": "string"],
            "text_profile_id": ["type": "string"],
            "cwd": ["type": "string"],
            "repo_root": ["type": "string"],
            "request_context": requestContextInputSchema,
        ]),
    ])

    private static func stringEnum(_ values: [String]) -> Value {
        .array(values.map { .string($0) })
    }
}
