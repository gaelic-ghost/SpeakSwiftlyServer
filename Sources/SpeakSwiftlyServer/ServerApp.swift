import Foundation
import Hummingbird
import SpeakSwiftlyCore

// MARK: - Server App

func makeApplication(
    configuration: ServerConfiguration,
    state: ServerState
) -> Application<Router<BasicRequestContext>.Responder> {
    let router = Router()

    router.get("healthz") { _, _ -> HealthSnapshot in
        await state.healthSnapshot()
    }

    router.get("readyz") { _, _ -> Response in
        let (ready, snapshot) = await state.readinessSnapshot()
        let status: HTTPResponse.Status = ready ? .ok : .serviceUnavailable
        return try encodeJSONResponse(snapshot, status: status)
    }

    router.get("status") { _, _ -> StatusSnapshot in
        await state.statusSnapshot()
    }

    router.get("profiles") { _, _ -> ProfileListResponse in
        .init(profiles: await state.cachedProfiles())
    }

    router.get("queue/generation") { _, _ -> QueueSnapshotResponse in
        try await state.queueSnapshot(queueType: .generation)
    }

    router.get("queue/playback") { _, _ -> QueueSnapshotResponse in
        try await state.queueSnapshot(queueType: .playback)
    }

    router.delete("queue") { _, _ -> QueueClearedResponse in
        try await state.clearQueue()
    }

    router.delete("queue/:request_id") { _, context -> QueueCancellationResponse in
        let requestID = try context.parameters.require("request_id")
        return try await state.cancelQueuedOrActiveRequest(requestID: requestID)
    }

    router.post("profiles") { request, context -> Response in
        let payload = try await request.decode(as: CreateProfileRequestPayload.self, context: context)
        let jobID = try await state.submitCreateProfile(
            profileName: payload.profileName,
            text: payload.text,
            voiceDescription: payload.voiceDescription,
            outputPath: payload.outputPath
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.delete("profiles/:profile_name") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let jobID = try await state.submitRemoveProfile(profileName: profileName)
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.get("playback") { _, _ -> PlaybackStateResponse in
        try await state.playbackStateSnapshot()
    }

    router.post("playback/pause") { _, _ -> PlaybackStateResponse in
        try await state.pausePlayback()
    }

    router.post("playback/resume") { _, _ -> PlaybackStateResponse in
        try await state.resumePlayback()
    }

    router.post("speak") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        let jobID = try await state.submitSpeak(
            text: payload.text,
            profileName: payload.profileName
        )
        return try buildAcceptedJobResponse(request: request, configuration: configuration, jobID: jobID)
    }

    router.get("jobs/:job_id") { _, context -> JobSnapshot in
        let jobID = try context.parameters.require("job_id")
        return try await state.jobSnapshot(id: jobID)
    }

    router.get("jobs/:job_id/events") { _, context -> Response in
        let jobID = try context.parameters.require("job_id")
        let body = ResponseBody(
            asyncSequence: try await state.sseStream(for: jobID)
        )
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: body)
    }

    return Application(
        router: router,
        configuration: .init(address: .hostname(configuration.host, port: configuration.port))
    )
}

private func buildAcceptedJobResponse(
    request: Request,
    configuration: ServerConfiguration,
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

private func absoluteURL(for request: Request, configuration: ServerConfiguration, path: String) -> String {
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
