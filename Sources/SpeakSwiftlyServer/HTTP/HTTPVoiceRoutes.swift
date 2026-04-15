import Hummingbird

// MARK: - Voice Routes

func registerHTTPVoiceRoutes(
    on router: Router<BasicRequestContext>,
    configuration: HTTPConfig,
    host: ServerHost,
) {
    router.get("voices") { _, _ -> ProfileListResponse in
        await .init(profiles: host.cachedProfiles())
    }

    router.post("voices/from-description") { request, context -> Response in
        let payload = try await request.decode(as: CreateProfileRequestPayload.self, context: context)
        let requestID = try await host.createVoiceProfileFromDescription(
            profileName: payload.profileName,
            vibe: payload.vibeModel(),
            text: payload.text,
            voiceDescription: payload.voiceDescription,
            outputPath: payload.outputPath,
            cwd: payload.cwd,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("voices/from-audio") { request, context -> Response in
        let payload = try await request.decode(as: CreateCloneRequestPayload.self, context: context)
        let requestID = try await host.createVoiceProfileFromAudio(
            profileName: payload.profileName,
            vibe: payload.vibeModel(),
            referenceAudioPath: payload.referenceAudioPath,
            transcript: payload.transcript,
            cwd: payload.cwd,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.put("voices/:profile_name/name") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let payload = try await request.decode(as: RenameVoiceProfileRequestPayload.self, context: context)
        let requestID = try await host.submitRenameVoiceProfile(
            profileName: profileName,
            to: payload.newProfileName,
        )
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("voices/:profile_name/reroll") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let requestID = try await host.submitRerollVoiceProfile(profileName: profileName)
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.delete("voices/:profile_name") { request, context -> Response in
        let profileName = try context.parameters.require("profile_name")
        let requestID = try await host.submitDeleteVoiceProfile(profileName: profileName)
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }
}
