import Foundation
import MCP
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
}
