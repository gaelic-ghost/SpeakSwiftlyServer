import Foundation
import Hummingbird
import HTTPTypes
import MCP
import NIOCore
import TextForSpeech

// MARK: - MCP Surface

struct MCPSurface {
    private let configuration: MCPConfig
    private let host: ServerHost
    private let transport: StatefulHTTPServerTransport
    private let server: Server
    private let subscriptionBroker: MCPSubscriptionBroker

    // MARK: - Construction

    static func build(
        configuration: MCPConfig,
        host: ServerHost
    ) async -> MCPSurface? {
        guard configuration.enabled else {
            return nil
        }

        let transport = StatefulHTTPServerTransport()
        let subscriptionBroker = MCPSubscriptionBroker()
        let server = await buildServer(
            configuration: configuration,
            host: host,
            subscriptionBroker: subscriptionBroker
        )
        return .init(
            configuration: configuration,
            host: host,
            transport: transport,
            server: server,
            subscriptionBroker: subscriptionBroker
        )
    }

    // MARK: - Lifecycle

    func mount(on router: Router<BasicRequestContext>) {
        let mcpPath = RouterPath(configuration.path)

        router.get(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.post(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }

        router.delete(mcpPath) { request, _ in
            let httpRequest = try await MCPHTTPBridge.makeHTTPRequest(from: request)
            let response = await transport.handleRequest(httpRequest)
            return try MCPHTTPBridge.makeResponse(from: response)
        }
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

    // MARK: - Server Assembly

    private static func buildServer(
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
            case "queue_speech_live":
                let jobID = try await host.submitSpeak(
                    text: requiredString("text", in: arguments),
                    profileName: requiredString("profile_name", in: arguments),
                    textProfileName: optionalString("text_profile_name", in: arguments),
                    normalizationContext: normalizationContext(in: arguments)
                )
                return try toolResult(
                    acceptedJobResult(
                        jobID: jobID,
                        message: "SpeakSwiftlyServer accepted the speech request. Read the returned job resource for request progress or read speak://status to monitor generation, playback, and transport state."
                    )
                )

            case "create_profile":
                let jobID = try await host.submitCreateProfile(
                    profileName: requiredString("profile_name", in: arguments),
                    text: requiredString("text", in: arguments),
                    voiceDescription: requiredString("voice_description", in: arguments),
                    outputPath: optionalString("output_path", in: arguments)
                )
                return try toolResult(
                    acceptedJobResult(
                        jobID: jobID,
                        message: "SpeakSwiftlyServer accepted the profile-creation request. Read the returned job resource for request progress or read speak://status to monitor worker state and the refreshed profile cache."
                    )
                )

            case "create_clone":
                let jobID = try await host.submitCreateClone(
                    profileName: requiredString("profile_name", in: arguments),
                    referenceAudioPath: requiredString("reference_audio_path", in: arguments),
                    transcript: optionalString("transcript", in: arguments)
                )
                return try toolResult(
                    acceptedJobResult(
                        jobID: jobID,
                        message: "SpeakSwiftlyServer accepted the clone-creation request. Read the returned job resource for request progress or read speak://status to monitor worker state and the refreshed profile cache."
                    )
                )

            case "list_profiles":
                return try toolResult(await host.cachedProfiles())

            case "list_text_profiles":
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

            case "store_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                return try toolResult(try await host.storeTextProfile(try profile.model()))

            case "use_text_profile":
                let profile: TextProfileSnapshot = try decodeArgument("profile", in: arguments)
                return try toolResult(try await host.useTextProfile(try profile.model()))

            case "remove_text_profile":
                return try toolResult(
                    try await host.removeTextProfile(named: requiredString("profile_id", in: arguments))
                )

            case "reset_text_profile":
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

            case "remove_profile":
                let jobID = try await host.submitRemoveProfile(
                    profileName: requiredString("profile_name", in: arguments)
                )
                return try toolResult(
                    acceptedJobResult(
                        jobID: jobID,
                        message: "SpeakSwiftlyServer accepted the profile-removal request. Read the returned job resource for request progress or read speak://status to monitor worker state and the refreshed profile cache."
                    )
                )

            case "list_queue_generation":
                return try toolResult(try await host.queueSnapshot(queueType: .generation))

            case "list_queue_playback":
                return try toolResult(try await host.queueSnapshot(queueType: .playback))

            case "playback_pause":
                return try toolResult(try await host.pausePlayback())

            case "playback_resume":
                return try toolResult(try await host.resumePlayback())

            case "playback_state":
                return try toolResult(try await host.playbackStateSnapshot())

            case "clear_queue":
                return try toolResult(try await host.clearQueue())

            case "cancel_request":
                return try toolResult(
                    try await host.cancelQueuedOrActiveRequest(
                        requestID: requiredString("request_id", in: arguments)
                    )
                )

            case "status":
                return try toolResult(await host.statusSnapshot())

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
            case "speak://status":
                return try resourceResult(uri: params.uri, payload: await host.statusSnapshot())

            case "speak://profiles":
                return try resourceResult(uri: params.uri, payload: await host.cachedProfiles())

            case "speak://profiles/guide":
                return .init(
                    contents: [
                        .text(
                            voiceProfilesGuideMarkdown(),
                            uri: params.uri,
                            mimeType: "text/markdown"
                        ),
                    ]
                )

            case "speak://text-profiles":
                return try resourceResult(uri: params.uri, payload: await host.textProfilesSnapshot())

            case "speak://text-profiles/guide":
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

            case "speak://text-profiles/base":
                return try resourceResult(uri: params.uri, payload: (await host.textProfilesSnapshot()).baseProfile)

            case "speak://text-profiles/active":
                return try resourceResult(uri: params.uri, payload: (await host.textProfilesSnapshot()).activeProfile)

            case "speak://text-profiles/effective":
                return try resourceResult(uri: params.uri, payload: await host.effectiveTextProfile(nil))

            case "speak://jobs":
                return try resourceResult(uri: params.uri, payload: await host.jobSnapshots())

            case "speak://runtime":
                return try resourceResult(uri: params.uri, payload: await host.hostStateSnapshot())

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
                            "No stored SpeakSwiftly text profile matched that profile id. Read speak://text-profiles first to inspect the current stored profile set."
                        )
                    }
                    return try resourceResult(uri: params.uri, payload: profile)
                }

                if let profileID = effectiveTextProfileID(from: params.uri) {
                    return try resourceResult(uri: params.uri, payload: await host.effectiveTextProfile(profileID))
                }

                if let jobID = jobID(from: params.uri) {
                    do {
                        return try resourceResult(uri: params.uri, payload: try await host.jobSnapshot(id: jobID))
                    } catch {
                        throw MCPError.invalidRequest(
                            "No tracked SpeakSwiftly job matched that job id. Submit speech or profile work first, or read speak://jobs to inspect retained jobs."
                        )
                    }
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
                let jobID = try requiredPromptString("job_id", in: arguments)
                let statusResourceURI = try requiredPromptString("status_resource_uri", in: arguments)
                let body = """
                Write exactly one short operator-facing acknowledgement for a speech request that was accepted by the shared SpeakSwiftly server host.
                Spoken text summary: \(spokenTextSummary)
                Shared host job id: \(jobID)
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
                - voice profile creation: create_profile, create_clone, list_profiles, remove_profile, speak://profiles, speak://profiles/guide
                - speech submission: queue_speech_live, speak://jobs/{job_id}, speak://status
                - text normalization: list_text_profiles, create_text_profile, store_text_profile, use_text_profile, reset_text_profile, add_text_replacement, replace_text_replacement, remove_text_replacement, speak://text-profiles, speak://text-profiles/guide
                - playback and queue control: list_queue_generation, list_queue_playback, playback_state, playback_pause, playback_resume, clear_queue, cancel_request, speak://playback/guide
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
            candidateURIs = ["speak://status", "speak://runtime"]
        case .jobEvent:
            candidateURIs = []
        case .jobChanged(let snapshot):
            candidateURIs = [
                "speak://status",
                "speak://runtime",
                "speak://jobs",
                "speak://jobs/\(snapshot.jobID)",
            ]
        case .profileCacheChanged:
            candidateURIs = Set(
                [
                    "speak://status",
                    "speak://runtime",
                    "speak://profiles",
                ] + subscribedResourceURIs.filter(isProfileDetailURI)
            )
        case .textProfilesChanged:
            candidateURIs = Set(
                [
                    "speak://text-profiles",
                    "speak://text-profiles/base",
                    "speak://text-profiles/active",
                    "speak://text-profiles/effective",
                ] + subscribedResourceURIs.filter(isStoredTextProfileURI)
                    + subscribedResourceURIs.filter(isEffectiveTextProfileURI)
            )
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
        || jobID(from: uri) != nil
    else {
        throw MCPError.invalidRequest(
            "Resource '\(uri)' is not available on this embedded SpeakSwiftly MCP surface."
        )
    }
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

private func normalizationContext(in arguments: [String: Value]) -> SpeechNormalizationContext? {
    let context = SpeechNormalizationContext(
        cwd: optionalString("cwd", in: arguments),
        repoRoot: optionalString("repo_root", in: arguments)
    )
    guard context.cwd != nil || context.repoRoot != nil else {
        return nil
    }
    return context
}

private func acceptedJobResult(jobID: String, message: String) -> MCPAcceptedJobResult {
    .init(
        jobID: jobID,
        jobResourceURI: "speak://jobs/\(jobID)",
        statusResourceURI: "speak://status",
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
    # SpeakSwiftly Text Profile Guide

    Use text profiles when a downstream app or agent needs to normalize phrasing before speech generation without changing the underlying voice profile.

    - `base profile`: immutable built-ins that always participate in effective normalization.
    - `active profile`: the current custom profile used by default when no explicit `text_profile_name` is provided during speech submission.
    - `stored profiles`: named reusable normalization policies that an app or agent can apply on demand.
    - `effective profile`: the merged profile SpeakSwiftly will actually apply after combining the base profile with the selected active or stored profile.

    Recommended workflow:

    1. Read `speak://text-profiles` to inspect the current base, active, stored, and effective state.
    2. Draft or edit rules with the `draft_text_profile` and `draft_text_replacement` prompts when a user needs help authoring replacements.
    3. Store reusable policies with `create_text_profile` or `store_text_profile`.
    4. Use `use_text_profile` when the downstream app wants a temporary active custom profile, or pass `text_profile_name` on one speech request when the caller wants stored-profile selection without mutating the active profile.
    5. Read `speak://text-profiles/effective/{profile_id}` before queuing speech if the user wants to verify what normalization will really happen.

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

    1. Read `speak://profiles` or call `list_profiles` to inspect the currently cached voice profiles.
    2. Use `create_profile` when the user wants a new synthetic profile from source text plus a voice description.
    3. Use `create_clone` when the user already has reference audio and wants SpeakSwiftly to capture that voice.
    4. Provide `transcript` to `create_clone` when the user knows the spoken words already; omit it only when transcription is actually needed.
    5. Use `queue_speech_live` after the user has chosen the correct voice profile, then read `speak://jobs/{job_id}` or `speak://status` for progress.
    6. Use `remove_profile` only after confirming the exact `profile_name`, especially when multiple similar profiles exist.

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

    1. Read `speak://status` first for a broad overview of worker readiness, queues, playback state, and recent errors.
    2. Read `speak://jobs` or `speak://jobs/{job_id}` when the user is asking about one specific request.
    3. Use `list_queue_generation` when the question is about what is still generating.
    4. Use `list_queue_playback` when the question is about what is waiting to be heard.
    5. Use `playback_state` before `playback_pause` or `playback_resume` if the user first needs confirmation about whether anything is currently playing.
    6. Use `cancel_request` to stop one specific request by id.
    7. Use `clear_queue` only when the user wants to drop backlog broadly without interrupting the active request.

    Safety guidance:

    - Prefer the least destructive control that satisfies the user’s intent.
    - Confirm the target request id before cancelling when multiple queued requests exist.
    - Distinguish generation backlog from playback backlog so the user understands whether work is waiting on model generation or audible output.
    """
}

private func profileDetailName(from uri: String) -> String? {
    let prefix = "speak://profiles/"
    let suffix = "/detail"
    guard uri.hasPrefix(prefix), uri.hasSuffix(suffix) else { return nil }
    return String(uri.dropFirst(prefix.count).dropLast(suffix.count))
}

private func isProfileDetailURI(_ uri: String) -> Bool {
    profileDetailName(from: uri) != nil
}

private func storedTextProfileID(from uri: String) -> String? {
    let prefix = "speak://text-profiles/stored/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func isStoredTextProfileURI(_ uri: String) -> Bool {
    storedTextProfileID(from: uri) != nil
}

private func effectiveTextProfileID(from uri: String) -> String? {
    let prefix = "speak://text-profiles/effective/"
    guard uri.hasPrefix(prefix) else { return nil }
    return String(uri.dropFirst(prefix.count))
}

private func isEffectiveTextProfileURI(_ uri: String) -> Bool {
    effectiveTextProfileID(from: uri) != nil
}

private func jobID(from uri: String) -> String? {
    let prefix = "speak://jobs/"
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
