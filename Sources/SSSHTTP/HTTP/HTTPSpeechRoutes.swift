import Hummingbird
import SpeakSwiftly
import SSSCore

package func registerHTTPSpeechRoutes(
    on router: Router<BasicRequestContext>,
    configuration: HTTPConfig,
    host: ServerHost,
) {
    router.post("speech/live") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        guard let profileName = await host.resolvedRequestedVoiceProfileName(payload.profileName) else {
            throw await HTTPError(
                .badRequest,
                message: host.missingVoiceProfileNameMessage(for: "the live speech request"),
            )
        }

        let requestID = try await host.queueSpeechLive(
            text: payload.text,
            profileName: profileName,
            textProfileID: payload.textProfileID,
            requestContext: payload.resolvedRequestContext(
                defaults: httpSpeechRequestContextDefaults(
                    route: "/speech/live",
                    reqPurpose: .speech,
                    topic: "live-speech",
                ),
            ),
            qwenPreModelTextChunking: payload.qwenPreModelTextChunking ?? false,
            generationLocation: payload.generationLocation ?? .local,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("speech/files") { request, context -> Response in
        let payload = try await request.decode(as: SpeakRequestPayload.self, context: context)
        guard let profileName = await host.resolvedRequestedVoiceProfileName(payload.profileName) else {
            throw await HTTPError(
                .badRequest,
                message: host.missingVoiceProfileNameMessage(for: "the retained audio-file request"),
            )
        }

        let requestID = try await host.queueSpeechFile(
            text: payload.text,
            profileName: profileName,
            textProfileID: payload.textProfileID,
            requestContext: payload.resolvedRequestContext(
                defaults: httpSpeechRequestContextDefaults(
                    route: "/speech/files",
                    reqPurpose: .audioFile,
                    topic: "retained-audio-file",
                ),
            ),
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("speech/batches") { request, context -> Response in
        let payload = try await request.decode(as: GenerateBatchRequestPayload.self, context: context)
        guard let profileName = await host.resolvedRequestedVoiceProfileName(payload.profileName) else {
            throw await HTTPError(
                .badRequest,
                message: host.missingVoiceProfileNameMessage(for: "the retained audio-batch request"),
            )
        }

        let requestID = try await host.queueSpeechBatch(
            items: payload.items.map {
                $0.model(
                    requestContextDefaults: httpSpeechRequestContextDefaults(
                        route: "/speech/batches",
                        reqPurpose: .audioFile,
                        topic: "retained-audio-batch",
                    ),
                )
            },
            profileName: profileName,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }
}

private func httpSpeechRequestContextDefaults(
    route: String,
    reqPurpose: SpeakSwiftly.RequestContext.RequestPurpose,
    topic: String,
) -> SpeechRequestContextDefaults {
    .init(
        reqPurpose: reqPurpose,
        source: "http",
        topic: topic,
        attributes: [
            "surface": "http",
            "http.method": "POST",
            "http.route": route,
            "server.app": "SpeakSwiftlyServer",
        ],
    )
}
