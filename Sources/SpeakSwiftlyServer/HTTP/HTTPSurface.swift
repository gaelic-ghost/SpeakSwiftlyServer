import Foundation
import Hummingbird
import ServiceLifecycle
import SpeakSwiftlyCore

// MARK: - HTTP Surface

func assembleHBApp(
    configuration: HTTPConfig,
    host: ServerHost,
    mcpSurface: MCPSurface? = nil,
    services: [any Service] = []
) -> Application<Router<BasicRequestContext>.Responder> {
    let router = Router()
    if configuration.enabled {
        registerHTTPRoutes(on: router, configuration: configuration, host: host)
    }
    mcpSurface?.mount(on: router)

    return Application(
        router: router,
        configuration: .init(address: .hostname(configuration.host, port: configuration.port)),
        services: services,
        onServerRunning: { _ in
            if configuration.enabled {
                await host.markTransportListening(name: "http")
            }
            if mcpSurface != nil {
                await host.markTransportListening(name: "mcp")
            }
        }
    )
}

private func registerHTTPRoutes(
    on router: Router<BasicRequestContext>,
    configuration: HTTPConfig,
    host: ServerHost
) {
    router.get("healthz") { _, _ -> HealthSnapshot in
        await host.healthSnapshot()
    }

    router.get("readyz") { _, _ -> Response in
        let (ready, snapshot) = await host.readinessSnapshot()
        let status: HTTPResponse.Status = ready ? .ok : .serviceUnavailable
        return try encodeJSONResponse(snapshot, status: status)
    }

    router.get("runtime/host") { _, _ -> StatusSnapshot in
        await host.statusSnapshot()
    }

    router.get("runtime/status") { _, _ -> RuntimeStatusResponse in
        try await host.runtimeStatus()
    }

    router.get("runtime/configuration") { _, _ -> RuntimeConfigurationSnapshot in
        await host.runtimeConfigurationSnapshot()
    }

    router.put("runtime/configuration") { request, context -> RuntimeConfigurationSnapshot in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        return try await host.saveRuntimeConfiguration(speechBackend: payload.speechBackendModel())
    }

    router.post("runtime/backend") { request, context -> RuntimeBackendResponse in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        return try await host.switchSpeechBackend(to: payload.speechBackendModel())
    }

    router.post("runtime/models/reload") { _, _ -> RuntimeStatusResponse in
        try await host.reloadModels()
    }

    router.post("runtime/models/unload") { _, _ -> RuntimeStatusResponse in
        try await host.unloadModels()
    }

    router.get("voices") { _, _ -> ProfileListResponse in
        .init(profiles: await host.cachedProfiles())
    }

    router.post("voices/from-description") { request, context -> Response in
        let payload = try await request.decode(as: CreateProfileRequestPayload.self, context: context)
        let requestID = try await host.createVoiceProfileFromDescription(
            profileName: payload.profileName,
            vibe: try payload.vibeModel(),
            text: payload.text,
            voiceDescription: payload.voiceDescription,
            outputPath: payload.outputPath,
            cwd: payload.cwd
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("voices/from-audio") { request, context -> Response in
        let payload = try await request.decode(as: CreateCloneRequestPayload.self, context: context)
        let requestID = try await host.createVoiceProfileFromAudio(
            profileName: payload.profileName,
            vibe: try payload.vibeModel(),
            referenceAudioPath: payload.referenceAudioPath,
            transcript: payload.transcript,
            cwd: payload.cwd
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.delete("voices/:profile_name") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let requestID = try await host.submitDeleteVoiceProfile(profileName: profileName)
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.get("text-profiles") { _, _ -> TextProfileListResponse in
        .init(textProfiles: await host.textProfilesSnapshot())
    }

    router.get("text-profiles/base") { _, _ -> TextProfileResponse in
        .init(profile: (await host.textProfilesSnapshot()).baseProfile)
    }

    router.get("text-profiles/active") { _, _ -> TextProfileResponse in
        .init(profile: (await host.textProfilesSnapshot()).activeProfile)
    }

    router.get("text-profiles/effective") { _, _ -> TextProfileResponse in
        .init(profile: await host.effectiveTextProfile(nil))
    }

    router.get("text-profiles/effective/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        return .init(profile: await host.effectiveTextProfile(profileID))
    }

    router.get("text-profiles/stored/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        guard let profile = await host.storedTextProfile(profileID) else {
            throw HTTPError(
                .notFound,
                message: "Text profile '\(profileID)' was not found in the persisted SpeakSwiftly text-profile set."
            )
        }
        return .init(profile: profile)
    }

    router.post("text-profiles/stored") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: CreateTextProfileRequestPayload.self, context: context)
        let profile = try await host.createTextProfile(
            id: payload.id,
            name: payload.name,
            replacements: try payload.replacements.map { try $0.model() }
        )
        return .init(profile: profile)
    }

    router.post("text-profiles/load") { _, _ -> TextProfileListResponse in
        .init(textProfiles: try await host.loadTextProfiles())
    }

    router.post("text-profiles/save") { _, _ -> TextProfileListResponse in
        .init(textProfiles: try await host.saveTextProfiles())
    }

    router.put("text-profiles/stored/:profile_id") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let payload = try await request.decode(as: StoreTextProfileRequestPayload.self, context: context)
        guard payload.profile.id == profileID else {
            throw HTTPError(
                .badRequest,
                message: "Stored text profile route id '\(profileID)' did not match body profile id '\(payload.profile.id)'."
            )
        }
        return .init(profile: try await host.storeTextProfile(try payload.profile.model()))
    }

    router.put("text-profiles/active") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: UseTextProfileRequestPayload.self, context: context)
        return .init(profile: try await host.useTextProfile(try payload.profile.model()))
    }

    router.post("text-profiles/active/reset") { _, _ -> TextProfileResponse in
        .init(profile: try await host.resetTextProfile())
    }

    router.delete("text-profiles/stored/:profile_id") { _, context -> TextProfileListResponse in
        let profileID = try context.parameters.require("profile_id")
        return .init(textProfiles: try await host.removeTextProfile(id: profileID))
    }

    router.post("text-profiles/active/replacements") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return .init(profile: try await host.addTextReplacement(try payload.replacement.model()))
    }

    router.post("text-profiles/stored/:profile_id/replacements") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return .init(profile: try await host.addTextReplacement(try payload.replacement.model(), toStoredTextProfileID: profileID))
    }

    router.put("text-profiles/active/replacements/:replacement_id") { request, context -> TextProfileResponse in
        let replacementID = try context.parameters.require("replacement_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        guard payload.replacement.id == replacementID else {
            throw HTTPError(
                .badRequest,
                message: "Active text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'."
            )
        }
        return .init(profile: try await host.replaceTextReplacement(try payload.replacement.model()))
    }

    router.put("text-profiles/stored/:profile_id/replacements/:replacement_id") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let replacementID = try context.parameters.require("replacement_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        guard payload.replacement.id == replacementID else {
            throw HTTPError(
                .badRequest,
                message: "Stored text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'."
            )
        }
        return .init(profile: try await host.replaceTextReplacement(try payload.replacement.model(), inStoredTextProfileID: profileID))
    }

    router.delete("text-profiles/active/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let replacementID = try context.parameters.require("replacement_id")
        return .init(profile: try await host.removeTextReplacement(id: replacementID))
    }

    router.delete("text-profiles/stored/:profile_id/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let replacementID = try context.parameters.require("replacement_id")
        return .init(profile: try await host.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID))
    }

    router.post("speech/live") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        let requestID = try await host.queueSpeechLive(
            text: payload.text,
            profileName: payload.profileName,
            textProfileName: payload.textProfileName,
            normalizationContext: try payload.normalizationContext(),
            sourceFormat: try payload.sourceFormatModel()
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("speech/files") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        let requestID = try await host.queueSpeechFile(
            text: payload.text,
            profileName: payload.profileName,
            textProfileName: payload.textProfileName,
            normalizationContext: try payload.normalizationContext(),
            sourceFormat: try payload.sourceFormatModel()
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("speech/batches") { request, context -> Response in
        let payload = try await request.decode(as: GenerateBatchRequestPayload.self, context: context)
        let requestID = try await host.queueSpeechBatch(
            items: try payload.items.map { try $0.model() },
            profileName: payload.profileName
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.get("generation/queue") { _, _ -> QueueSnapshotResponse in
        try await host.generationQueueSnapshot()
    }

    router.get("generation/jobs") { request, _ -> Response in
        try encodeJSONResponse(try await host.listGenerationJobs(), status: .ok)
    }

    router.get("generation/jobs/:job_id") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        return try encodeJSONResponse(try await host.generationJob(id: jobID), status: .ok)
    }

    router.delete("generation/jobs/:job_id") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        return try encodeJSONResponse(try await host.expireGenerationJob(id: jobID), status: .ok)
    }

    router.get("generation/files") { _, _ -> Response in
        try encodeJSONResponse(try await host.listGeneratedFiles(), status: .ok)
    }

    router.get("generation/files/:artifact_id") { _, context -> Response in
        let artifactID = try context.parameters.require("artifact_id")
        return try encodeJSONResponse(try await host.generatedFile(id: artifactID), status: .ok)
    }

    router.get("generation/batches") { _, _ -> Response in
        try encodeJSONResponse(try await host.listGeneratedBatches(), status: .ok)
    }

    router.get("generation/batches/:batch_id") { _, context -> Response in
        let batchID = try context.parameters.require("batch_id")
        return try encodeJSONResponse(try await host.generatedBatch(id: batchID), status: .ok)
    }

    router.get("playback/state") { _, _ -> PlaybackStateResponse in
        try await host.playbackStateSnapshot()
    }

    router.get("playback/queue") { _, _ -> QueueSnapshotResponse in
        try await host.playbackQueueSnapshot()
    }

    router.post("playback/pause") { _, _ -> PlaybackStateResponse in
        try await host.pausePlayback()
    }

    router.post("playback/resume") { _, _ -> PlaybackStateResponse in
        try await host.resumePlayback()
    }

    router.delete("playback/queue") { _, _ -> QueueClearedResponse in
        try await host.clearQueue()
    }

    router.delete("playback/requests/:request_id") { _, context -> QueueCancellationResponse in
        let requestID = try context.parameters.require("request_id")
        return try await host.cancelQueuedOrActiveRequest(requestID: requestID)
    }

    router.get("requests") { _, _ -> RequestListResponse in
        .init(requests: await host.jobSnapshots())
    }

    router.get("requests/:request_id") { _, context -> JobSnapshot in
        let requestID = try context.parameters.require("request_id")
        return try await host.jobSnapshot(id: requestID)
    }

    router.get("requests/:request_id/events") { _, context -> Response in
        let requestID = try context.parameters.require("request_id")
        let body = ResponseBody(
            asyncSequence: try await host.sseStream(for: requestID)
        )
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: body)
    }
}

private func buildAcceptedRequestResponse(
    request: Request,
    configuration: HTTPConfig,
    requestID: String
) throws -> Response {
    try encodeJSONResponse(
        RequestAcceptedResponse(
            requestID: requestID,
            requestURL: absoluteURL(for: request, configuration: configuration, path: "/requests/\(requestID)"),
            eventsURL: absoluteURL(for: request, configuration: configuration, path: "/requests/\(requestID)/events")
        ),
        status: .accepted
    )
}

private func absoluteURL(for request: Request, configuration: HTTPConfig, path: String) -> String {
    let scheme = request.head.scheme ?? "http"
    let authority = request.head.authority ?? "\(configuration.host):\(configuration.port)"
    return "\(scheme)://\(authority)\(path)"
}

private func encodeJSONResponse<T: Encodable>(_ value: T, status: HTTPResponse.Status) throws -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    var headers = HTTPFields()
    headers[.contentType] = "application/json; charset=utf-8"
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
}
