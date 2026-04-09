import Foundation
import Hummingbird
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - MCP Surface

struct MCPSurface {
    private let sessions: MCPSessionRegistry

    // MARK: - Construction

    static func build(
        configuration: MCPConfig,
        host: ServerHost
    ) async -> MCPSurface? {
        guard configuration.enabled else {
            return nil
        }

        return .init(
            sessions: .init(
                configuration: configuration,
                host: host
            )
        )
    }

    // MARK: - Lifecycle

    func mount(on router: Router<BasicRequestContext>) {
        let mcpPath = RouterPath(sessions.path)

        router.get(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.post(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.delete(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await sessions.handle(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }
    }

    func start() async throws {
        await sessions.start()
    }

    func stop() async {
        await sessions.stop()
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        await sessions.handle(request)
    }

    // MARK: - Server Assembly

    fileprivate static func buildServer(
        configuration: MCPConfig,
        host: ServerHost,
        subscriptionBroker: MCPSubscriptionBroker
    ) async -> Server {
        let server = Server(
            name: configuration.serverName,
            version: "0.1.0",
            title: configuration.title,
            instructions: """
            Shared-process SpeakSwiftly MCP surface backed by the same ServerHost used by the app-facing HTTP API. Read status, job, profile, text-profile, and runtime resources for operator-visible state, use the tools to queue speech, inspect queues, control playback, and manage both voice and text profiles, and use the built-in prompts for reusable voice-design, text-normalization authoring, and operator acknowledgement workflows without starting a second runtime owner.
            """,
            capabilities: .init(
                prompts: .init(listChanged: false),
                resources: .init(subscribe: true, listChanged: false),
                tools: .init(listChanged: false)
            )
        )

        // MARK: - Tool Methods

        await server.withMethodHandler(ListTools.self) { _ in
            .init(tools: MCPToolCatalog.definitions)
        }

        await server.withMethodHandler(CallTool.self) { params in
            let arguments = params.arguments ?? [:]

            switch params.name {
            case "generate_speech_live":
                let requestID = try await host.submitGenerateSpeechLive(
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
                let requestID = try await host.submitGenerateAudioFile(
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

            case "generate_audio_batch":
                let items: [BatchItemRequestPayload] = try decodeArgument("items", in: arguments)
                let requestID = try await host.submitGenerateAudioBatch(
                    items: try items.map { try $0.model() },
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedRequestResult(
                        requestID: requestID,
                        message: "SpeakSwiftlyServer accepted the retained audio-batch generation request. Read the returned request resource for progress, then inspect speak://generation/batches or speak://generation/jobs."
                    )
                )

            case "create_voice_profile":
                let requestID = try await host.submitCreateVoiceProfile(
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

            case "clone_voice_profile":
                let requestID = try await host.submitCloneVoiceProfile(
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

            case "get_normalizer_state":
                return try toolResult(await host.textProfilesSnapshot())

            case "create_text_profile":
                return try toolResult(
                    try await host.createTextProfile(
                        id: requiredString("id", in: arguments),
                        name: requiredString("name", in: arguments),
                        replacements: try decodeOptionalArgument("replacements", in: arguments, default: [TextReplacementSnapshot]())
                            .map { try $0.model() }
                    )
                )

            case "load_text_profiles":
                return try toolResult(try await host.loadTextProfiles())

            case "save_text_profiles":
                return try toolResult(try await host.saveTextProfiles())

            case "store_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                return try toolResult(try await host.storeTextProfile(try profile.model()))

            case "use_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                return try toolResult(try await host.useTextProfile(try profile.model()))

            case "delete_text_profile":
                return try toolResult(
                    try await host.removeTextProfile(named: requiredString("profile_id", in: arguments))
                )

            case "reset_active_text_profile":
                return try toolResult(try await host.resetTextProfile())

            case "add_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                return try toolResult(
                    try await host.addTextReplacement(
                        try replacement.model(),
                        toStoredTextProfileNamed: optionalString("profile_id", in: arguments)
                    )
                )

            case "replace_text_replacement":
                let replacement: TextReplacementSnapshot = try decodeArgument("replacement", in: arguments)
                return try toolResult(
                    try await host.replaceTextReplacement(
                        try replacement.model(),
                        inStoredTextProfileNamed: optionalString("profile_id", in: arguments)
                    )
                )

            case "remove_text_replacement":
                return try toolResult(
                    try await host.removeTextReplacement(
                        id: requiredString("replacement_id", in: arguments),
                        fromStoredTextProfileNamed: optionalString("profile_id", in: arguments)
                    )
                )

            case "list_generation_queue":
                return try toolResult(try await host.queueSnapshot(queueType: .generation))

            case "list_playback_queue":
                return try toolResult(try await host.queueSnapshot(queueType: .playback))

            case "get_playback_state":
                return try toolResult(try await host.playbackStateSnapshot())

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
                return try toolResult(try await host.generationJobs())

            case "get_generation_job":
                return try toolResult(try await host.generationJob(id: requiredString("job_id", in: arguments)))

            case "expire_generation_job":
                return try toolResult(try await host.expireGenerationJob(id: requiredString("job_id", in: arguments)))

            case "list_generated_files":
                return try toolResult(try await host.generatedFiles())

            case "get_generated_file":
                return try toolResult(try await host.generatedFile(id: requiredString("artifact_id", in: arguments)))

            case "list_generated_batches":
                return try toolResult(try await host.generatedBatches())

            case "get_generated_batch":
                return try toolResult(try await host.generatedBatch(id: requiredString("batch_id", in: arguments)))

            default:
                throw MCPError.methodNotFound(
                    "Tool '\(params.name)' is not registered on this embedded SpeakSwiftly MCP surface."
                )
            }
        }

        // MARK: - Resource Methods

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
            case "speak://runtime/overview":
                return try resourceResult(uri: params.uri, payload: await host.statusSnapshot())

            case "speak://runtime/status":
                return try resourceResult(uri: params.uri, payload: try await host.runtimeStatus())

            case "speak://runtime/configuration":
                return try resourceResult(uri: params.uri, payload: await host.runtimeConfigurationSnapshot())

            case "speak://voices":
                return try resourceResult(uri: params.uri, payload: await host.cachedProfiles())

            case "speak://voices/guide":
                return .init(
                    contents: [
                        .text(
                            voiceProfilesGuideMarkdown(),
                            uri: params.uri,
                            mimeType: "text/markdown"
                        ),
                    ]
                )

            case "speak://normalizer":
                return try resourceResult(uri: params.uri, payload: await host.textProfilesSnapshot())

            case "speak://normalizer/guide":
                return .init(
                    contents: [
                        .text(
                            textProfilesGuideMarkdown(),
                            uri: params.uri,
                            mimeType: "text/markdown"
                        ),
                    ]
                )

            case "speak://playback/guide":
                return .init(
                    contents: [
                        .text(
                            playbackGuideMarkdown(),
                            uri: params.uri,
                            mimeType: "text/markdown"
                        ),
                    ]
                )

            case "speak://normalizer/base-profile":
                return try resourceResult(uri: params.uri, payload: (await host.textProfilesSnapshot()).baseProfile)

            case "speak://normalizer/active-profile":
                return try resourceResult(uri: params.uri, payload: (await host.textProfilesSnapshot()).activeProfile)

            case "speak://normalizer/effective-profile":
                return try resourceResult(uri: params.uri, payload: await host.effectiveTextProfile(nil))

            case "speak://requests":
                return try resourceResult(uri: params.uri, payload: await host.jobSnapshots())

            case "speak://generation/jobs":
                return try resourceResult(uri: params.uri, payload: try await host.generationJobs())

            case "speak://generation/files":
                return try resourceResult(uri: params.uri, payload: try await host.generatedFiles())

            case "speak://generation/batches":
                return try resourceResult(uri: params.uri, payload: try await host.generatedBatches())

            default:
                if let profileName = profileDetailName(from: params.uri) {
                    guard let profile = await host.cachedProfile(profileName) else {
                        throw MCPError.invalidRequest(
                            "No cached SpeakSwiftly profile matched that profile name. Refresh or recreate the profile before requesting detail."
                        )
                    }
                    return try resourceResult(uri: params.uri, payload: profile)
                }

                if let profileID = storedTextProfileID(from: params.uri) {
                    guard let profile = await host.storedTextProfile(profileID) else {
                        throw MCPError.invalidRequest(
                            "No stored SpeakSwiftly text profile matched that profile id. Read speak://normalizer first to inspect the current stored profile set."
                        )
                    }
                    return try resourceResult(uri: params.uri, payload: profile)
                }

                if let profileID = effectiveTextProfileID(from: params.uri) {
                    return try resourceResult(uri: params.uri, payload: await host.effectiveTextProfile(profileID))
                }

                if let requestID = requestID(from: params.uri) {
                    do {
                        return try resourceResult(uri: params.uri, payload: try await host.jobSnapshot(id: requestID))
                    } catch {
                        throw MCPError.invalidRequest(
                            "No tracked SpeakSwiftly request matched that request id. Submit work first, or read speak://requests to inspect retained request state."
                        )
                    }
                }

                if let jobID = generationJobID(from: params.uri) {
                    return try resourceResult(uri: params.uri, payload: try await host.generationJob(id: jobID))
                }

                if let artifactID = generatedFileID(from: params.uri) {
                    return try resourceResult(uri: params.uri, payload: try await host.generatedFile(id: artifactID))
                }

                if let batchID = generatedBatchID(from: params.uri) {
                    return try resourceResult(uri: params.uri, payload: try await host.generatedBatch(id: batchID))
                }

                throw MCPError.invalidRequest(
                    "Resource '\(params.uri)' is not available on this embedded SpeakSwiftly MCP surface."
                )
            }
        }

        // MARK: - Prompt Methods

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
                    messages: [.user(.text(text: compactPrompt(body)))]
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
                    messages: [.user(.text(text: compactPrompt(body)))]
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
                    messages: [.user(.text(text: compactPrompt(body)))]
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
                    messages: [.user(.text(text: compactPrompt(body)))]
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
                    messages: [.user(.text(text: compactPrompt(body)))]
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
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            case "choose_surface_action":
                let userGoal = try requiredPromptString("user_goal", in: arguments)
                let body = """
                Choose the most appropriate SpeakSwiftly MCP next step for the user request below.
                User goal: \(userGoal)
                Current context: \(textIfPresent("current_context", in: arguments) ?? "unknown")
                \(textIfPresent("constraints", in: arguments).map { "Constraints: \($0)" } ?? "")
                Available action families:
                - voice profile work: create_voice_profile, clone_voice_profile, list_voice_profiles, delete_voice_profile, speak://voices, speak://voices/guide
                - speech and retained generation: generate_speech_live, generate_audio_file, generate_audio_batch, speak://requests/{request_id}, speak://generation/jobs, speak://generation/files, speak://generation/batches
                - text normalization: get_normalizer_state, load_text_profiles, save_text_profiles, create_text_profile, store_text_profile, use_text_profile, reset_active_text_profile, add_text_replacement, replace_text_replacement, remove_text_replacement, speak://normalizer, speak://normalizer/guide
                - playback and queue control: list_generation_queue, list_playback_queue, get_playback_state, pause_playback, resume_playback, clear_playback_queue, cancel_request, speak://playback/guide
                - runtime controls: get_runtime_overview, get_runtime_status, get_runtime_configuration, set_runtime_configuration, switch_speech_backend, reload_models, unload_models, speak://runtime/overview, speak://runtime/status, speak://runtime/configuration
                - drafting help: draft_profile_voice_description, draft_profile_source_text, draft_text_profile, draft_text_replacement, draft_voice_design_instruction, draft_queue_playback_notice
                Return concise JSON with keys action_type, target_name, why, and suggested_follow_up. action_type must be one of tool, resource, or prompt.
                """
                return .init(
                    description: "Reusable routing prompt for choosing the right SpeakSwiftly MCP action.",
                    messages: [.user(.text(text: compactPrompt(body)))]
                )

            default:
                throw MCPError.methodNotFound(
                    "Prompt '\(params.name)' is not registered on this embedded SpeakSwiftly MCP surface."
                )
            }
        }

        return server
    }
}

// MARK: - Session Registry

private actor MCPSessionRegistry {
    let path: String

    private let configuration: MCPConfig
    private let host: ServerHost
    private var sessions = [String: MCPSession]()
    private var started = false

    init(configuration: MCPConfig, host: ServerHost) {
        self.path = configuration.path
        self.configuration = configuration
        self.host = host
    }

    func start() {
        started = true
    }

    func stop() async {
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        started = false

        for session in activeSessions {
            await session.stop()
        }
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        guard started else {
            return .error(
                statusCode: 503,
                .internalError("SpeakSwiftly MCP is not ready yet. Likely cause: the shared MCP surface has not finished starting.")
            )
        }

        if isInitializeRequest(request) {
            return await createSession(for: request)
        }

        guard let sessionID = request.header(HTTPHeaderName.sessionID), sessionID.isEmpty == false else {
            return .error(
                statusCode: 400,
                .invalidRequest(
                    "Bad Request: Session not initialized. Start a new MCP session with an initialize request before sending follow-up requests."
                )
            )
        }

        guard let session = sessions[sessionID] else {
            return .error(
                statusCode: 404,
                .invalidRequest(
                    "Not Found: No active MCP session matched '\(sessionID)'. Initialize a new session before retrying this request."
                ),
                sessionID: sessionID
            )
        }

        let response = await session.handle(request)
        if request.method.uppercased() == "DELETE", (200...299).contains(response.statusCode) {
            sessions.removeValue(forKey: sessionID)
            await session.stop()
        }
        return response
    }

    private func createSession(for request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        let session = await MCPSession.make(
            configuration: configuration,
            host: host
        )

        do {
            try await session.start()
        } catch {
            return .error(
                statusCode: 500,
                .internalError(
                    "SpeakSwiftly MCP could not start a new session transport. Likely cause: \(error.localizedDescription)"
                )
            )
        }

        let response = await session.handle(request)

        guard (200...299).contains(response.statusCode) else {
            await session.stop()
            return response
        }

        guard let sessionID = mcpSessionID(from: response.headers) else {
            await session.stop()
            return .error(
                statusCode: 500,
                .internalError(
                    "SpeakSwiftly MCP accepted an initialize request, but the session response was missing the required MCP-Session-Id header."
                )
            )
        }

        sessions[sessionID] = session
        return response
    }

    private func isInitializeRequest(_ request: MCP.HTTPRequest) -> Bool {
        guard request.method.uppercased() == "POST", let body = request.body else {
            return false
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return json["method"] as? String == "initialize"
    }
}

private actor MCPSession {
    private let host: ServerHost
    private let transport: StatefulHTTPServerTransport
    private let server: Server
    private let subscriptionBroker: MCPSubscriptionBroker

    static func make(
        configuration: MCPConfig,
        host: ServerHost
    ) async -> MCPSession {
        let transport = StatefulHTTPServerTransport()
        let subscriptionBroker = MCPSubscriptionBroker()
        let server = await MCPSurface.buildServer(
            configuration: configuration,
            host: host,
            subscriptionBroker: subscriptionBroker
        )
        return .init(
            host: host,
            transport: transport,
            server: server,
            subscriptionBroker: subscriptionBroker
        )
    }

    init(
        host: ServerHost,
        transport: StatefulHTTPServerTransport,
        server: Server,
        subscriptionBroker: MCPSubscriptionBroker
    ) {
        self.host = host
        self.transport = transport
        self.server = server
        self.subscriptionBroker = subscriptionBroker
    }

    func start() async throws {
        try await server.start(transport: transport)
        await subscriptionBroker.start(host: host, server: server)
    }

    func stop() async {
        await subscriptionBroker.stop()
        await server.stop()
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        await transport.handleRequest(request)
    }
}

// MARK: - Subscription Handling

private actor MCPSubscriptionBroker {
    private var subscribedResourceURIs = Set<String>()
    private var eventTask: Task<Void, Never>?

    func start(host: ServerHost, server: Server) {
        guard eventTask == nil else {
            return
        }

        let updates = Task { await host.eventUpdates() }
        eventTask = Task {
            let events = await updates.value
            for await event in events {
                if Task.isCancelled {
                    break
                }
                let updatedURIs = resourceURIsToNotify(for: event)
                guard updatedURIs.isEmpty == false else {
                    continue
                }
                for uri in updatedURIs {
                    do {
                        try await server.notify(ResourceUpdatedNotification.message(.init(uri: uri)))
                    } catch {
                        // The shared transport may be stopping or may not have a connected SSE stream yet.
                        continue
                    }
                }
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        subscribedResourceURIs.removeAll()
    }

    func subscribe(to uri: String) {
        subscribedResourceURIs.insert(uri)
    }

    func unsubscribe(from uri: String) {
        subscribedResourceURIs.remove(uri)
    }

    private func resourceURIsToNotify(for event: HostEvent) -> [String] {
        let candidateURIs: Set<String>
        switch event {
        case .transportChanged, .playbackChanged, .recentErrorRecorded:
            candidateURIs = ["speak://runtime/overview"]
        case .jobEvent:
            candidateURIs = []
        case .jobChanged(let snapshot):
            candidateURIs = [
                "speak://runtime/overview",
                "speak://requests",
                "speak://requests/\(snapshot.requestID)",
            ]
        case .profileCacheChanged:
            candidateURIs = Set(
                [
                    "speak://runtime/overview",
                    "speak://voices",
                ] + subscribedResourceURIs.filter(isVoiceProfileURI)
            )
        case .textProfilesChanged:
            candidateURIs = Set(
                [
                    "speak://normalizer",
                    "speak://normalizer/base-profile",
                    "speak://normalizer/active-profile",
                    "speak://normalizer/effective-profile",
                ] + subscribedResourceURIs.filter(isStoredTextProfileURI)
                    + subscribedResourceURIs.filter(isEffectiveTextProfileURI)
            )
        case .runtimeConfigurationChanged:
            candidateURIs = [
                "speak://runtime/overview",
                "speak://runtime/configuration",
            ]
        }
        return candidateURIs
            .intersection(subscribedResourceURIs)
            .sorted()
    }
}

// MARK: - Resource Validation

private func ensureKnownResourceURI(_ uri: String) throws {
    guard MCPResourceCatalog.resourceURIs.contains(uri)
        || profileDetailName(from: uri) != nil
        || storedTextProfileID(from: uri) != nil
        || effectiveTextProfileID(from: uri) != nil
        || requestID(from: uri) != nil
        || generationJobID(from: uri) != nil
        || generatedFileID(from: uri) != nil
        || generatedBatchID(from: uri) != nil
    else {
        throw MCPError.invalidRequest(
            "Resource '\(uri)' is not available on this embedded SpeakSwiftly MCP surface."
        )
    }
}

private func mcpSessionID(from headers: [String: String]) -> String? {
    for (name, value) in headers {
        if name.caseInsensitiveCompare(HTTPHeaderName.sessionID) == .orderedSame,
           value.isEmpty == false
        {
            return value
        }
    }
    return nil
}

// MARK: - HTTP Bridge

private enum MCPHTTPBridge {
    static func makeHTTPRequest(from request: Request) async throws -> MCP.HTTPRequest {
        let bodyBuffer = try await request.body.collect(upTo: 10 * 1024 * 1024)
        let bodyData = Data(bodyBuffer.readableBytesView)

        var headers = [String: String]()
        for field in request.headers {
            headers[field.name.rawName] = field.value
        }

        return MCP.HTTPRequest(
            method: request.method.rawValue,
            headers: headers,
            body: bodyData.isEmpty ? nil : bodyData,
            path: request.uri.path
        )
    }

    static func makeResponse(from response: MCP.HTTPResponse) throws -> Response {
        var headers = HTTPFields()
        for (name, value) in response.headers {
            guard let headerName = HTTPField.Name(name) else { continue }
            headers[headerName] = value
        }

        switch response {
        case .accepted:
            return Response(status: .accepted, headers: headers)

        case .ok:
            return Response(status: .ok, headers: headers)

        case .data(let data, _):
            return Response(
                status: .ok,
                headers: headers,
                body: ResponseBody(byteBuffer: byteBuffer(from: data))
            )

        case .stream(let stream, _):
            let body = ResponseBody { writer in
                for try await chunk in stream {
                    try await writer.write(byteBuffer(from: chunk))
                }
                try await writer.finish(nil)
            }
            return Response(status: .ok, headers: headers, body: body)

        case .error:
            return Response(
                status: .init(code: response.statusCode),
                headers: headers,
                body: ResponseBody(byteBuffer: byteBuffer(from: response.bodyData ?? Data()))
            )
        }
    }

    static func byteBuffer(from data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}

// MARK: - Result Encoding

private func toolResult<Output: Encodable>(_ output: Output) throws -> CallTool.Result {
    let data = try JSONEncoder().encode(output)
    let json = String(decoding: data, as: UTF8.self)
    return .init(content: [.text(text: json, annotations: nil, _meta: nil)], isError: false)
}

private func resourceResult<Output: Encodable>(
    uri: String,
    payload: Output
) throws -> ReadResource.Result {
    let data = try JSONEncoder().encode(payload)
    let json = String(decoding: data, as: UTF8.self)
    return .init(contents: [.text(json, uri: uri, mimeType: "application/json")])
}

// MARK: - Argument Parsing

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
    if let format = TextForSpeech.TextFormat(rawValue: rawValue) {
        return format
    }
    if let legacyFormat = TextForSpeech.Format(rawValue: rawValue),
       let textFormat = legacyRequestTextFormat(for: legacyFormat)
    {
        return textFormat
    }

    let supportedFormats = TextForSpeech.TextFormat.allCases.map(\.rawValue)
    let legacyFormats = TextForSpeech.Format.allCases.map(\.rawValue)
    let acceptedValues = (supportedFormats + legacyFormats).joined(separator: ", ")
    throw MCPError.invalidParams(
        "Tool argument 'text_format' used unsupported value '\(rawValue)'. Expected one of: \(acceptedValues)."
    )
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

private func legacyRequestTextFormat(for format: TextForSpeech.Format) -> TextForSpeech.TextFormat? {
    switch format {
    case .plain: .plain
    case .markdown: .markdown
    case .html: .html
    case .log: .log
    case .cli: .cli
    case .list: .list
    case .source, .swift, .python, .rust: nil
    }
}

private func acceptedRequestResult(requestID: String, message: String) -> MCPAcceptedRequestResult {
    .init(
        requestID: requestID,
        requestResourceURI: "speak://requests/\(requestID)",
        statusResourceURI: "speak://runtime/overview",
        message: message
    )
}

private func requiredPromptString(_ key: String, in arguments: [String: String]) throws -> String {
    guard let value = textIfPresent(key, in: arguments) else {
        throw MCPError.invalidParams(
            "Prompt arguments are missing the required string field '\(key)'."
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

private func textProfilesGuideMarkdown() -> String {
    """
    # SpeakSwiftly Normalizer Guide

    Use text profiles when a downstream app or agent needs to normalize phrasing before speech generation without changing the underlying voice profile.

    - `base profile`: immutable built-ins that always participate in effective normalization.
    - `active profile`: the current custom profile used by default when no explicit `text_profile_name` is provided during speech submission.
    - `stored profiles`: named reusable normalization policies that an app or agent can apply on demand.
    - `effective profile`: the merged profile SpeakSwiftly will actually apply after combining the base profile with the selected active or stored profile.

    Recommended workflow:

    1. Read `speak://normalizer` to inspect the current base, active, stored, and effective state.
    2. Draft or edit rules with the `draft_text_profile` and `draft_text_replacement` prompts when a user needs help authoring replacements.
    3. Store reusable policies with `create_text_profile` or `store_text_profile`.
    4. Use `use_text_profile` when the downstream app wants a temporary active custom profile, or pass `text_profile_name` on one speech request when the caller wants stored-profile selection without mutating the active profile.
    5. Use `save_text_profiles` when the operator wants an explicit persistence checkpoint, and `load_text_profiles` when another process changed the persistence file and the in-memory state should be refreshed from disk.
    6. Read `speak://normalizer/effective-profile/{profile_id}` before queuing speech if the user wants to verify what normalization will really happen.

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

    Use voice-profile tools when the user wants to create, import, inspect, choose, or remove reusable speaking voices.

    Recommended workflow:

    1. Read `speak://voices` or call `list_voice_profiles` to inspect the currently cached voice profiles.
    2. Use `create_voice_profile` when the user wants a new synthetic profile from source text plus a voice description.
    3. Use `clone_voice_profile` when the user already has reference audio and wants SpeakSwiftly to capture that voice.
    4. Provide `transcript` to `clone_voice_profile` when the user knows the spoken words already; omit it only when transcription is actually needed.
    5. Pass `text_format`, `nested_source_format`, or `source_format` to `generate_speech_live` when the input needs explicit format-aware normalization instead of automatic detection.
    6. Use `generate_speech_live` after the user has chosen the correct voice profile, then read `speak://requests/{request_id}` or `speak://runtime/overview` for progress.
    7. Use `delete_voice_profile` only after confirming the exact `profile_name`, especially when multiple similar profiles exist.

    Drafting guidance:

    - Use `draft_profile_voice_description` when the user is still exploring how a synthetic profile should sound.
    - Use `draft_profile_source_text` when the user needs a good source passage for profile creation.
    - Use `draft_voice_design_instruction` when the user is shaping one spoken line rather than a reusable stored profile.
    """
}

private func playbackGuideMarkdown() -> String {
    """
    # SpeakSwiftly Playback And Queue Guide

    Use queue and playback tools when the user wants to know what is running, what is waiting, or how to control audible output.

    Recommended workflow:

    1. Read `speak://runtime/overview` first for a broad overview of worker readiness, queues, playback state, and recent errors.
    2. Read `speak://requests` or `speak://requests/{request_id}` when the user is asking about one specific server-tracked request.
    3. Use `list_generation_queue` when the question is about what is still generating.
    4. Use `list_playback_queue` when the question is about what is waiting to be heard.
    5. Use `get_playback_state` before `pause_playback` or `resume_playback` if the user first needs confirmation about whether anything is currently playing.
    6. Use `cancel_request` to stop one specific request by id.
    7. Use `clear_playback_queue` only when the user wants to drop backlog broadly without interrupting the active request.

    Safety guidance:

    - Prefer the least destructive control that satisfies the user’s intent.
    - Confirm the target request id before cancelling when multiple queued requests exist.
    - Distinguish generation backlog from playback backlog so the user understands whether work is waiting on model generation or audible output.
    """
}

private func profileDetailName(from uri: String) -> String? {
    let prefix = "speak://voices/"
    guard uri.hasPrefix(prefix) else { return nil }
    let profileName = String(uri.dropFirst(prefix.count))
    return profileName.isEmpty ? nil : profileName
}

private func isVoiceProfileURI(_ uri: String) -> Bool {
    profileDetailName(from: uri) != nil
}

private func storedTextProfileID(from uri: String) -> String? {
    let prefix = "speak://normalizer/stored-profiles/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func isStoredTextProfileURI(_ uri: String) -> Bool {
    storedTextProfileID(from: uri) != nil
}

private func effectiveTextProfileID(from uri: String) -> String? {
    let prefix = "speak://normalizer/effective-profile/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func isEffectiveTextProfileURI(_ uri: String) -> Bool {
    effectiveTextProfileID(from: uri) != nil
}

private func requestID(from uri: String) -> String? {
    let prefix = "speak://requests/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func generationJobID(from uri: String) -> String? {
    let prefix = "speak://generation/jobs/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func generatedFileID(from uri: String) -> String? {
    let prefix = "speak://generation/files/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func generatedBatchID(from uri: String) -> String? {
    let prefix = "speak://generation/batches/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
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
