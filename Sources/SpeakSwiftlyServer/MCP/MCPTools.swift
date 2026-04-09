import Foundation
import MCP
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Tool Catalog

enum MCPToolCatalog {
    static let definitions: [Tool] = [
        Tool(
            name: "queue_speech_live",
            description: "Queue live speech playback with a stored SpeakSwiftly voice profile. Use this when the user wants audible output now, and optionally provide text_profile_name plus explicit normalization-format arguments when the input should not rely on automatic format detection.",
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
            name: "queue_speech_file",
            description: "Queue one retained generated-audio file instead of live playback. Use this when the user wants a saved artifact they can inspect or reuse later.",
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
            name: "queue_speech_batch",
            description: "Queue a retained generated-audio batch from multiple items under one voice profile. Use this when the user wants several output files produced together.",
            inputSchema: [
                "type": "object",
                "required": ["profile_name", "items"],
                "properties": [
                    "profile_name": ["type": "string"],
                    "items": ["type": "array"],
                ],
            ]
        ),
        Tool(
            name: "create_voice_profile_from_description",
            description: "Create a new stored SpeakSwiftly voice profile from source text, an explicit vibe, and a voice description.",
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
            name: "create_voice_profile_from_audio",
            description: "Create a new stored SpeakSwiftly voice clone from local reference audio with an explicit vibe.",
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
            name: "list_voice_profiles",
            description: "Return the current in-memory snapshot of cached SpeakSwiftly voice profiles.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
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
            ]
        ),
        Tool(
            name: "get_runtime_overview",
            description: "Return the shared-host runtime overview with readiness, queues, playback state, transports, and recent errors. This is the best first read when an agent needs orientation.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "get_runtime_status",
            description: "Return the underlying SpeakSwiftly runtime status event, including stage, resident model state, and active speech backend.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "get_runtime_configuration",
            description: "Return the persisted runtime-configuration snapshot, including the active backend, the next-start backend, and any environment override.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "set_runtime_configuration",
            description: "Persist one speech_backend value for the next runtime start without hot-swapping the current worker.",
            inputSchema: [
                "type": "object",
                "required": ["speech_backend"],
                "properties": [
                    "speech_backend": ["type": "string", "enum": ["qwen3", "marvis"]],
                ],
            ]
        ),
        Tool(
            name: "switch_speech_backend",
            description: "Ask the already-running SpeakSwiftly runtime to switch to a different active speech backend immediately.",
            inputSchema: [
                "type": "object",
                "required": ["speech_backend"],
                "properties": [
                    "speech_backend": ["type": "string", "enum": ["qwen3", "marvis"]],
                ],
            ]
        ),
        Tool(
            name: "reload_models",
            description: "Ask the already-running SpeakSwiftly runtime to reload its resident models.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "unload_models",
            description: "Ask the already-running SpeakSwiftly runtime to unload its resident models.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "get_text_profiles_state",
            description: "Return the full SpeakSwiftly text-profile snapshot, including base, active, stored, and effective profiles.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "create_text_profile",
            description: "Create a stored SpeakSwiftly text profile with the provided id, display name, and optional replacement rules.",
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
            description: "Reload persisted SpeakSwiftly text profiles from disk and return the refreshed text-profile state.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "save_text_profiles",
            description: "Persist the current SpeakSwiftly text-profile state to disk and return the refreshed text-profile state.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "store_text_profile",
            description: "Store or replace one persisted SpeakSwiftly text profile by passing the full profile payload.",
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
            description: "Replace the active custom SpeakSwiftly text profile with the provided full profile payload.",
            inputSchema: [
                "type": "object",
                "required": ["profile"],
                "properties": [
                    "profile": ["type": "object"],
                ],
            ]
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
            ]
        ),
        Tool(
            name: "reset_active_text_profile",
            description: "Reset the active custom SpeakSwiftly text profile back to the library default.",
            inputSchema: ["type": "object", "properties": [:]]
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
            ]
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
            ]
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
            ]
        ),
        Tool(
            name: "list_generation_queue",
            description: "Return the current generation queue snapshot for the shared SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "list_playback_queue",
            description: "Return the current playback queue snapshot for the shared SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "get_playback_state",
            description: "Return the current SpeakSwiftly playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "pause_playback",
            description: "Pause the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "resume_playback",
            description: "Resume the current SpeakSwiftly playback stream and return the resulting playback state snapshot.",
            inputSchema: ["type": "object", "properties": [:]]
        ),
        Tool(
            name: "clear_playback_queue",
            description: "Cancel all currently queued SpeakSwiftly playback work without interrupting the active request.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
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
            annotations: .init(readOnlyHint: false, destructiveHint: true, idempotentHint: false, openWorldHint: false)
        ),
        Tool(
            name: "list_requests",
            description: "Return the shared-host retained request snapshots for live server operations such as generation, voice creation, and playback control.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "list_generation_jobs",
            description: "Return the retained v2 generation jobs known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
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
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
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
            ]
        ),
        Tool(
            name: "list_generated_files",
            description: "Return retained generated audio files known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
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
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
        Tool(
            name: "list_generated_batches",
            description: "Return retained generated audio batches known to the SpeakSwiftly runtime.",
            inputSchema: ["type": "object", "properties": [:]],
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
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
            annotations: .init(readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
        ),
    ]
}

// MARK: - Tool Handlers

extension MCPSurface {
    static func registerToolHandlers(
        on server: Server,
        host: ServerHost,
        subscriptionBroker: MCPSubscriptionBroker
    ) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]

            switch params.name {
            case "queue_speech_live":
                let requestID = try await host.queueSpeechLive(
                    text: requiredString("text", in: arguments),
                    profileName: requiredString("profile_name", in: arguments),
                    textProfileName: optionalString("text_profile_name", in: arguments),
                    normalizationContext: try normalizationContext(in: arguments),
                    sourceFormat: try sourceFormat(in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the live speech request. Read the returned request resource for progress or read speak://runtime/overview to monitor generation, playback, and transport state."
                    )
                )

            case "queue_speech_file":
                let requestID = try await host.queueSpeechFile(
                    text: requiredString("text", in: arguments),
                    profileName: requiredString("profile_name", in: arguments),
                    textProfileName: optionalString("text_profile_name", in: arguments),
                    normalizationContext: try normalizationContext(in: arguments),
                    sourceFormat: try sourceFormat(in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the retained audio-file generation request. Read the returned request resource for progress, then inspect speak://generation/files or speak://generation/jobs."
                    )
                )

            case "queue_speech_batch":
                let items: [BatchItemRequestPayload] = try decodeArgument("items", in: arguments)
                let requestID = try await host.queueSpeechBatch(
                    items: try items.map { try $0.model() },
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the retained audio-batch generation request. Read the returned request resource for progress, then inspect speak://generation/batches or speak://generation/jobs."
                    )
                )

            case "create_voice_profile_from_description":
                let requestID = try await host.createVoiceProfileFromDescription(
                    profileName: requiredString("profile_name", in: arguments),
                    vibe: try requiredVibe("vibe", in: arguments),
                    text: requiredString("text", in: arguments),
                    voiceDescription: requiredString("voice_description", in: arguments),
                    outputPath: optionalString("output_path", in: arguments),
                    cwd: optionalString("cwd", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile creation request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache."
                    )
                )

            case "create_voice_profile_from_audio":
                let requestID = try await host.createVoiceProfileFromAudio(
                    profileName: requiredString("profile_name", in: arguments),
                    vibe: try requiredVibe("vibe", in: arguments),
                    referenceAudioPath: requiredString("reference_audio_path", in: arguments),
                    transcript: optionalString("transcript", in: arguments),
                    cwd: optionalString("cwd", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-clone creation request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache."
                    )
                )

            case "list_voice_profiles":
                return try toolResult(await host.cachedProfiles())

            case "delete_voice_profile":
                let requestID = try await host.submitDeleteVoiceProfile(
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile deletion request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache."
                    )
                )

            case "get_runtime_overview":
                return try toolResult(await host.statusSnapshot())

            case "get_runtime_status":
                return try toolResult(try await host.runtimeStatus())

            case "get_runtime_configuration":
                return try toolResult(await host.runtimeConfigurationSnapshot())

            case "set_runtime_configuration":
                return try toolResult(
                    try await host.saveRuntimeConfiguration(
                        speechBackend: try requiredSpeechBackend("speech_backend", in: arguments)
                    )
                )

            case "switch_speech_backend":
                return try toolResult(
                    try await host.switchSpeechBackend(
                        to: try requiredSpeechBackend("speech_backend", in: arguments)
                    )
                )

            case "reload_models":
                return try toolResult(try await host.reloadModels())

            case "unload_models":
                return try toolResult(try await host.unloadModels())

            case "get_text_profiles_state":
                return try toolResult(await host.textProfilesSnapshot())

            case "create_text_profile":
                let result = try await host.createTextProfile(
                    id: requiredString("id", in: arguments),
                    name: requiredString("name", in: arguments),
                    replacements: try decodeOptionalArgument("replacements", in: arguments, default: [TextReplacementSnapshot]())
                        .map { try $0.model() }
                )
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "load_text_profiles":
                let result = try await host.loadTextProfiles()
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "save_text_profiles":
                let result = try await host.saveTextProfiles()
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "store_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                let result = try await host.storeTextProfile(try profile.model())
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "use_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                let result = try await host.useTextProfile(try profile.model())
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "delete_text_profile":
                let result = try await host.removeTextProfile(id: requiredString("profile_id", in: arguments))
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "reset_active_text_profile":
                let result = try await host.resetTextProfile()
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "add_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                let result = try await host.addTextReplacement(
                    try replacement.model(),
                    toStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "replace_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                let result = try await host.replaceTextReplacement(
                    try replacement.model(),
                    inStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "remove_text_replacement":
                let result = try await host.removeTextReplacement(
                    id: requiredString("replacement_id", in: arguments),
                    fromStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(
                    for: .textProfiles,
                    using: server
                )
                return try toolResult(result)

            case "list_generation_queue":
                return try toolResult(await host.generationQueueSnapshot())

            case "list_playback_queue":
                return try toolResult(await host.playbackQueueSnapshot())

            case "get_playback_state":
                return try toolResult(await host.playbackStateSnapshot())

            case "pause_playback":
                return try toolResult(try await host.pausePlayback())

            case "resume_playback":
                return try toolResult(try await host.resumePlayback())

            case "clear_playback_queue":
                return try toolResult(try await host.clearQueue())

            case "cancel_request":
                return try toolResult(
                    try await host.cancelQueuedOrActiveRequest(
                        requestID: requiredString("request_id", in: arguments)
                    )
                )

            case "list_requests":
                return try toolResult(await host.jobSnapshots())

            case "list_generation_jobs":
                return try toolResult(try await host.listGenerationJobs())

            case "get_generation_job":
                return try toolResult(try await host.generationJob(id: requiredString("job_id", in: arguments)))

            case "expire_generation_job":
                return try toolResult(try await host.expireGenerationJob(id: requiredString("job_id", in: arguments)))

            case "list_generated_files":
                return try toolResult(try await host.listGeneratedFiles())

            case "get_generated_file":
                return try toolResult(try await host.generatedFile(id: requiredString("artifact_id", in: arguments)))

            case "list_generated_batches":
                return try toolResult(try await host.listGeneratedBatches())

            case "get_generated_batch":
                return try toolResult(try await host.generatedBatch(id: requiredString("batch_id", in: arguments)))

            default:
                throw MCPError.methodNotFound(
                    "Tool '\(params.name)' is not registered on this embedded SpeakSwiftly MCP surface."
                )
            }
        }
    }
}

// MARK: - Tool Encoding

private func toolResult<Output: Encodable>(_ output: Output) throws -> CallTool.Result {
    let data = try JSONEncoder().encode(output)
    let json = String(decoding: data, as: UTF8.self)
    return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
}

private func acceptedRequestResult(requestID: String, message: String) -> MCPAcceptedRequestResult {
    .init(
        requestID: requestID,
        requestResourceURI: "speak://requests/\(requestID)",
        statusResourceURI: "speak://runtime/overview",
        message: message
    )
}

// MARK: - Tool Argument Parsing

private func requiredString(_ key: String, in arguments: [String: Value]) throws -> String {
    guard let value = arguments[key]?.stringValue, value.isEmpty == false else {
        throw MCPError.invalidParams(
            "Tool arguments are missing the required string field '\(key)'."
        )
    }
    return value
}

private func optionalString(_ key: String, in arguments: [String: Value]) -> String? {
    guard let value = arguments[key]?.stringValue, value.isEmpty == false else {
        return nil
    }
    return value
}

private func decodeArgument<T: Decodable>(
    _ key: String,
    in arguments: [String: Value]
) throws -> T {
    guard let value = arguments[key] else {
        throw MCPError.invalidParams(
            "Tool arguments are missing the required field '\(key)'."
        )
    }
    return try decodeValue(value, fieldName: key)
}

private func decodeOptionalArgument<T: Decodable>(
    _ key: String,
    in arguments: [String: Value],
    default defaultValue: T
) throws -> T {
    guard let value = arguments[key] else {
        return defaultValue
    }
    return try decodeValue(value, fieldName: key)
}

private func normalizationContext(in arguments: [String: Value]) throws -> SpeechNormalizationContext? {
    let context = SpeechNormalizationContext(
        cwd: optionalString("cwd", in: arguments),
        repoRoot: optionalString("repo_root", in: arguments),
        textFormat: try requestTextFormat(in: arguments),
        nestedSourceFormat: try requestSourceFormat("nested_source_format", in: arguments)
    )
    guard
        context.cwd != nil
            || context.repoRoot != nil
            || context.textFormat != nil
            || context.nestedSourceFormat != nil
    else {
        return nil
    }
    return context
}

private func sourceFormat(in arguments: [String: Value]) throws -> TextForSpeech.SourceFormat? {
    try requestSourceFormat("source_format", in: arguments)
}

private func requestTextFormat(in arguments: [String: Value]) throws -> TextForSpeech.TextFormat? {
    guard let rawValue = optionalString("text_format", in: arguments) else {
        return nil
    }
    guard let format = TextForSpeech.TextFormat(rawValue: rawValue) else {
        let acceptedValues = TextForSpeech.TextFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument 'text_format' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues)."
        )
    }
    return format
}

private func requestSourceFormat(
    _ key: String,
    in arguments: [String: Value]
) throws -> TextForSpeech.SourceFormat? {
    guard let rawValue = optionalString(key, in: arguments) else {
        return nil
    }
    guard let format = TextForSpeech.SourceFormat(rawValue: rawValue) else {
        let acceptedValues = TextForSpeech.SourceFormat.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues)."
        )
    }
    return format
}

private func requiredVibe(
    _ key: String,
    in arguments: [String: Value]
) throws -> SpeakSwiftly.Vibe {
    let rawValue = try requiredString(key, in: arguments)
    guard let vibe = SpeakSwiftly.Vibe(rawValue: rawValue) else {
        let acceptedValues = SpeakSwiftly.Vibe.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues)."
        )
    }
    return vibe
}

private func requiredSpeechBackend(
    _ key: String,
    in arguments: [String: Value]
) throws -> SpeakSwiftly.SpeechBackend {
    let rawValue = try requiredString(key, in: arguments)
    guard let speechBackend = SpeakSwiftly.SpeechBackend(rawValue: rawValue) else {
        let acceptedValues = SpeakSwiftly.SpeechBackend.allCases.map(\.rawValue).joined(separator: ", ")
        throw MCPError.invalidParams(
            "Tool argument '\(key)' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues)."
        )
    }
    return speechBackend
}

private func decodeValue<T: Decodable>(_ value: Value, fieldName: String) throws -> T {
    do {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(T.self, from: data)
    } catch {
        throw MCPError.invalidParams(
            "Tool argument '\(fieldName)' could not be decoded into the expected payload shape. Likely cause: \(error.localizedDescription)"
        )
    }
}
