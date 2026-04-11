import Foundation
import MCP
import SpeakSwiftlyCore
import TextForSpeech

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
            case "generate_speech":
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

            case "generate_audio_file":
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

            case "generate_batch":
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

            case "update_voice_profile_name":
                let requestID = try await host.submitRenameVoiceProfile(
                    profileName: requiredString("profile_name", in: arguments),
                    to: requiredString("new_profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile rename request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache."
                    )
                )

            case "reroll_voice_profile":
                let requestID = try await host.submitRerollVoiceProfile(
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the voice-profile reroll request. Read the returned request resource for progress or read speak://voices to monitor the refreshed cache."
                    )
                )

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

            case "get_staged_runtime_config":
                return try toolResult(await host.runtimeConfigurationSnapshot())

            case "set_staged_config":
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

            case "get_text_normalizer_snapshot":
                return try toolResult(await host.textProfilesSnapshot())

            case "get_text_profile_style":
                return try toolResult(await host.textProfileStyleSnapshot())

            case "set_text_profile_style":
                let result = try await host.setTextProfileStyle(
                    try requiredBuiltInTextProfileStyle("built_in_style", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "create_text_profile":
                let result = try await host.createTextProfile(
                    id: requiredString("id", in: arguments),
                    name: requiredString("name", in: arguments),
                    replacements: try decodeOptionalArgument("replacements", in: arguments, default: [TextReplacementSnapshot]())
                        .map { try $0.model() }
                )
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "load_text_profiles":
                let result = try await host.loadTextProfiles()
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "save_text_profiles":
                let result = try await host.saveTextProfiles()
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "store_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                let result = try await host.storeTextProfile(try profile.model())
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "use_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                let result = try await host.useTextProfile(try profile.model())
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "delete_text_profile":
                let result = try await host.removeTextProfile(id: requiredString("profile_id", in: arguments))
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "reset_active_text_profile":
                let result = try await host.resetTextProfile()
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "add_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                let result = try await host.addTextReplacement(
                    try replacement.model(),
                    toStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "replace_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                let result = try await host.replaceTextReplacement(
                    try replacement.model(),
                    inStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
                return try toolResult(result)

            case "remove_text_replacement":
                let result = try await host.removeTextReplacement(
                    id: requiredString("replacement_id", in: arguments),
                    fromStoredTextProfileID: optionalString("profile_id", in: arguments)
                )
                await subscriptionBroker.notifyResourceChanges(for: .textProfiles, using: server)
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

            case "list_active_requests":
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
