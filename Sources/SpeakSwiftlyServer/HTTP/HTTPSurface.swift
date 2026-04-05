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
            text: payload.text,
            voiceDescription: payload.voiceDescription,
            outputPath: payload.outputPath
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.post("profiles/clone") { request, context -> Response in
        let payload = try await request.decode(as: CreateCloneRequestPayload.self, context: context)
        let jobID = try await host.submitCreateClone(
            profileName: payload.profileName,
            referenceAudioPath: payload.referenceAudioPath,
            transcript: payload.transcript
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
            normalizationContext: payload.normalizationContext
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
