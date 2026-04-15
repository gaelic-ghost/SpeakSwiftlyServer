import Hummingbird

// MARK: - Speech Submission Routes

func registerHTTPSpeechRoutes(
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
            textProfileName: payload.textProfileName,
            normalizationContext: payload.normalizationContext(),
            sourceFormat: payload.sourceFormatModel(),
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
            textProfileName: payload.textProfileName,
            normalizationContext: payload.normalizationContext(),
            sourceFormat: payload.sourceFormatModel(),
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
            items: payload.items.map { try $0.model() },
            profileName: profileName,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }
}
