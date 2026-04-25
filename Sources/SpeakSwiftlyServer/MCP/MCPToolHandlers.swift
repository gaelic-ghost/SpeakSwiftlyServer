import Foundation
import MCP
import SpeakSwiftly
import TextForSpeech

private func mapTextProfileToolError(_ error: any Error) -> MCPError {
    if let error = error as? MCPError {
        return error
    }

    if let error = error as? SpeakSwiftly.Error {
        return .internalError(error.message)
    }

    return .internalError(
        "SpeakSwiftlyServer could not complete the text-profile MCP tool request. Likely cause: \(error.localizedDescription)",
    )
}

private func acceptedRequestToolResult(
    requestID: String,
    message: String,
) throws -> CallTool.Result {
    try toolResult(
        acceptedRequestResult(
            requestID: requestID,
            message: message,
        ),
    )
}

private func mappedTextProfileToolResult(
    _ operation: () async throws -> some Encodable,
) async throws -> CallTool.Result {
    do {
        return try await toolResult(operation())
    } catch {
        throw mapTextProfileToolError(error)
    }
}

private func notifyingTextProfileToolResult(
    on server: Server,
    subscriptionBroker: MCPSubscriptionBroker,
    _ operation: () async throws -> some Encodable,
) async throws -> CallTool.Result {
    do {
        let result = try await operation()
        await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
        return try toolResult(result)
    } catch {
        throw mapTextProfileToolError(error)
    }
}

extension MCPSurface {
    static func registerToolHandlers(
        on server: Server,
        host: ServerHost,
        subscriptionBroker: MCPSubscriptionBroker,
    ) async {
        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]

            switch params.name {
                case "generate_speech":
                    guard let profileName = await host.resolvedRequestedVoiceProfileName(optionalString("profile_name", in: arguments)) else {
                        throw await MCPError.invalidParams(
                            host.missingVoiceProfileNameMessage(for: "the live speech request"),
                        )
                    }

                    let requestID = try await host.queueSpeechLive(
                        text: requiredString("text", in: arguments),
                        profileName: profileName,
                        textProfileID: optionalString("text_profile_id", in: arguments),
                        normalizationContext: normalizationContext(in: arguments),
                        sourceFormat: sourceFormat(in: arguments),
                        requestContext: requestContext(in: arguments),
                        qwenPreModelTextChunking: decodeOptionalArgument(
                            "qwen_pre_model_text_chunking",
                            in: arguments,
                            default: false,
                        ),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the live speech request. Read the returned request resource for progress or read speak://runtime/overview to monitor generation, playback, and transport state.",
                    )

                case "generate_audio_file":
                    guard let profileName = await host.resolvedRequestedVoiceProfileName(optionalString("profile_name", in: arguments)) else {
                        throw await MCPError.invalidParams(
                            host.missingVoiceProfileNameMessage(for: "the retained audio-file request"),
                        )
                    }

                    let requestID = try await host.queueSpeechFile(
                        text: requiredString("text", in: arguments),
                        profileName: profileName,
                        textProfileID: optionalString("text_profile_id", in: arguments),
                        normalizationContext: normalizationContext(in: arguments),
                        sourceFormat: sourceFormat(in: arguments),
                        requestContext: requestContext(in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the retained audio-file generation request. Read the returned request resource for progress, then inspect speak://generation/files or speak://generation/jobs.",
                    )

                case "generate_batch":
                    let items: [BatchItemRequestPayload] = try decodeArgument("items", in: arguments)
                    guard let profileName = await host.resolvedRequestedVoiceProfileName(optionalString("profile_name", in: arguments)) else {
                        throw await MCPError.invalidParams(
                            host.missingVoiceProfileNameMessage(for: "the retained audio-batch request"),
                        )
                    }

                    let requestID = try await host.queueSpeechBatch(
                        items: items.map { try $0.model() },
                        profileName: profileName,
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the retained audio-batch generation request. Read the returned request resource for progress, then inspect speak://generation/batches or speak://generation/jobs.",
                    )

                case "create_voice_profile_from_description":
                    let requestID = try await host.createVoiceProfileFromDescription(
                        profileName: requiredString("profile_name", in: arguments),
                        vibe: requiredVibe("vibe", in: arguments),
                        text: requiredString("text", in: arguments),
                        voiceDescription: requiredString("voice_description", in: arguments),
                        outputPath: optionalString("output_path", in: arguments),
                        cwd: optionalString("cwd", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile creation request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache.",
                    )

                case "create_voice_profile_from_audio":
                    let requestID = try await host.createVoiceProfileFromAudio(
                        profileName: requiredString("profile_name", in: arguments),
                        vibe: requiredVibe("vibe", in: arguments),
                        referenceAudioPath: requiredString("reference_audio_path", in: arguments),
                        transcript: optionalString("transcript", in: arguments),
                        cwd: optionalString("cwd", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-clone creation request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache.",
                    )

                case "list_voice_profiles":
                    return try await toolResult(host.cachedProfiles())

                case "update_voice_profile_name":
                    let requestID = try await host.submitRenameVoiceProfile(
                        profileName: requiredString("profile_name", in: arguments),
                        to: requiredString("new_profile_name", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile rename request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache.",
                    )

                case "reroll_voice_profile":
                    let requestID = try await host.submitRerollVoiceProfile(
                        profileName: requiredString("profile_name", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile reroll request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache.",
                    )

                case "delete_voice_profile":
                    let requestID = try await host.submitDeleteVoiceProfile(
                        profileName: requiredString("profile_name", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile deletion request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache.",
                    )

                case "get_runtime_overview":
                    return try await toolResult(host.statusSnapshot())

                case "get_runtime_status":
                    return try await toolResult(host.runtimeStatus())

                case "get_staged_runtime_config":
                    return try await toolResult(host.runtimeConfigurationSnapshot())

                case "set_staged_config":
                    return try await toolResult(
                        host.saveRuntimeConfiguration(
                            speechBackend: requiredSpeechBackend("speech_backend", in: arguments),
                            qwenResidentModel: optionalQwenResidentModel("qwen_resident_model", in: arguments),
                            marvisResidentPolicy: optionalMarvisResidentPolicy("marvis_resident_policy", in: arguments),
                        ),
                    )

                case "switch_speech_backend":
                    let requestID = try await host.submitSpeechBackendSwitch(
                        to: requiredSpeechBackend("speech_backend", in: arguments),
                    )
                    return try acceptedRequestToolResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the speech-backend switch request. Read the returned request resource for progress or read speak://runtime/overview to observe the pending and active backend state.",
                    )

                case "reload_models":
                    return try await toolResult(host.reloadModels())

                case "unload_models":
                    return try await toolResult(host.unloadModels())

                case "get_text_normalizer_snapshot":
                    return try await mappedTextProfileToolResult {
                        try await host.textProfilesSnapshot()
                    }

                case "get_text_profile_style":
                    return try await toolResult(host.textProfileStyleSnapshot())

                case "set_text_profile_style":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.setTextProfileStyle(
                            requiredBuiltInTextProfileStyle("built_in_style", in: arguments),
                        )
                    }

                case "create_text_profile":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.createTextProfile(
                            name: requiredString("name", in: arguments),
                            replacements: decodeOptionalArgument("replacements", in: arguments, default: [TextReplacementSnapshot]())
                                .map { try $0.model() },
                        )
                    }

                case "load_text_profiles":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.loadTextProfiles()
                    }

                case "save_text_profiles":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.saveTextProfiles()
                    }

                case "rename_text_profile":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.renameTextProfile(
                            id: requiredString("profile_id", in: arguments),
                            to: requiredString("name", in: arguments),
                        )
                    }

                case "delete_text_profile":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.removeTextProfile(id: requiredString("profile_id", in: arguments))
                    }

                case "set_active_text_profile":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.setActiveTextProfile(
                            id: requiredString("profile_id", in: arguments),
                        )
                    }

                case "factory_reset_text_profiles":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.factoryResetTextProfiles()
                    }

                case "reset_text_profile":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.resetTextProfile(
                            id: requiredString("profile_id", in: arguments),
                        )
                    }

                case "add_text_replacement":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                        return try await host.addTextReplacement(
                            replacement.model(),
                            toStoredTextProfileID: optionalString("profile_id", in: arguments),
                        )
                    }

                case "replace_text_replacement":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                        return try await host.replaceTextReplacement(
                            replacement.model(),
                            inStoredTextProfileID: optionalString("profile_id", in: arguments),
                        )
                    }

                case "remove_text_replacement":
                    return try await notifyingTextProfileToolResult(
                        on: server,
                        subscriptionBroker: subscriptionBroker,
                    ) {
                        try await host.removeTextReplacement(
                            id: requiredString("replacement_id", in: arguments),
                            fromStoredTextProfileID: optionalString("profile_id", in: arguments),
                        )
                    }

                case "list_generation_queue":
                    return try await toolResult(host.generationQueueSnapshot())

                case "list_playback_queue":
                    return try await toolResult(host.playbackQueueSnapshot())

                case "get_playback_state":
                    return try await toolResult(host.playbackStateSnapshot())

                case "pause_playback":
                    return try await toolResult(host.pausePlayback())

                case "resume_playback":
                    return try await toolResult(host.resumePlayback())

                case "clear_playback_queue":
                    return try await toolResult(host.clearQueue())

                case "cancel_request":
                    return try await toolResult(
                        host.cancelQueuedOrActiveRequest(
                            requestID: requiredString("request_id", in: arguments),
                        ),
                    )

                case "list_active_requests":
                    return try await toolResult(host.jobSnapshots())

                case "list_generation_jobs":
                    return try await toolResult(host.listGenerationJobs())

                case "get_generation_job":
                    return try await toolResult(host.generationJob(id: requiredString("job_id", in: arguments)))

                case "expire_generation_job":
                    return try await toolResult(host.expireGenerationJob(id: requiredString("job_id", in: arguments)))

                case "list_generated_files":
                    return try await toolResult(host.listGeneratedFiles())

                case "get_generated_file":
                    return try await toolResult(host.generatedFile(id: requiredString("artifact_id", in: arguments)))

                case "list_generated_batches":
                    return try await toolResult(host.listGeneratedBatches())

                case "get_generated_batch":
                    return try await toolResult(host.generatedBatch(id: requiredString("batch_id", in: arguments)))

                default:
                    throw MCPError.methodNotFound(
                        "Tool '\(params.name)' is not registered on this embedded SpeakSwiftly MCP surface.",
                    )
            }
        }
    }
}
