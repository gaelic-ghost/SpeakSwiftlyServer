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

    router.get("status") { _, _ -> StatusSnapshot in
        await host.statusSnapshot()
    }

    router.get("profiles") { _, _ -> ProfileListResponse in
        .init(profiles: await host.cachedProfiles())
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
        return .init(textProfiles: try await host.removeTextProfile(named: profileID))
    }

    router.post("text-profiles/active/replacements") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return .init(profile: try await host.addTextReplacement(try payload.replacement.model()))
    }

    router.post("text-profiles/stored/:profile_id/replacements") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return .init(profile: try await host.addTextReplacement(try payload.replacement.model(), toStoredTextProfileNamed: profileID))
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
        return .init(profile: try await host.replaceTextReplacement(try payload.replacement.model(), inStoredTextProfileNamed: profileID))
    }

    router.delete("text-profiles/active/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let replacementID = try context.parameters.require("replacement_id")
        return .init(profile: try await host.removeTextReplacement(id: replacementID))
    }

    router.delete("text-profiles/stored/:profile_id/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let replacementID = try context.parameters.require("replacement_id")
        return .init(profile: try await host.removeTextReplacement(id: replacementID, fromStoredTextProfileNamed: profileID))
    }

    router.get("jobs") { _, _ -> JobListResponse in
        .init(jobs: await host.jobSnapshots())
    }

    router.get("queue/generation") { _, _ -> QueueSnapshotResponse in
        try await host.queueSnapshot(queueType: .generation)
    }

    router.get("queue/playback") { _, _ -> QueueSnapshotResponse in
        try await host.queueSnapshot(queueType: .playback)
    }

    router.delete("queue") { _, _ -> QueueClearedResponse in
        try await host.clearQueue()
    }

    router.delete("queue/:request_id") { _, context -> QueueCancellationResponse in
        let requestID = try context.parameters.require("request_id")
        return try await host.cancelQueuedOrActiveRequest(requestID: requestID)
    }

    router.post("profiles") { request, context -> Response in
        let payload = try await request.decode(as: CreateProfileRequestPayload.self, context: context)
        let jobID = try await host.submitCreateProfile(
            profileName: payload.profileName,
            vibe: try payload.vibeModel(),
            text: payload.text,
            voiceDescription: payload.voiceDescription,
            outputPath: payload.outputPath,
            cwd: payload.cwd
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.post("profiles/clone") { request, context -> Response in
        let payload = try await request.decode(as: CreateCloneRequestPayload.self, context: context)
        let jobID = try await host.submitCreateClone(
            profileName: payload.profileName,
            vibe: try payload.vibeModel(),
            referenceAudioPath: payload.referenceAudioPath,
            transcript: payload.transcript,
            cwd: payload.cwd
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.delete("profiles/:profile_name") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let jobID = try await host.submitRemoveProfile(profileName: profileName)
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.get("playback") { _, _ -> PlaybackStateResponse in
        try await host.playbackStateSnapshot()
    }

    router.post("playback/pause") { _, _ -> PlaybackStateResponse in
        try await host.pausePlayback()
    }

    router.post("playback/resume") { _, _ -> PlaybackStateResponse in
        try await host.resumePlayback()
    }

    router.post("speak") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        let jobID = try await host.submitSpeak(
            text: payload.text,
            profileName: payload.profileName,
            textProfileName: payload.textProfileName,
            normalizationContext: try payload.normalizationContext(),
            sourceFormat: try payload.sourceFormatModel()
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.get("jobs/:job_id") { _, context -> JobSnapshot in
        let jobID = try context.parameters.require("job_id")
        return try await host.jobSnapshot(id: jobID)
    }

    router.get("jobs/:job_id/events") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        let body = ResponseBody(
            asyncSequence: try await host.sseStream(for: jobID)
        )
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: body)
    }
}

private func buildAcceptedJobResponse(
    request: Request,
    configuration: HTTPConfig,
    jobID: String
) throws -> Response {
    try encodeJSONResponse(
        JobCreatedResponse(
            jobID: jobID,
            jobURL: absoluteURL(for: request, configuration: configuration, path: "/jobs/\(jobID)"),
            eventsURL: absoluteURL(for: request, configuration: configuration, path: "/jobs/\(jobID)/events")
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
