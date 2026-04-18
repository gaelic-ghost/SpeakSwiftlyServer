import Hummingbird

func registerHTTPTextProfileRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("text-profiles") { _, _ -> TextProfileListResponse in
        await .init(textProfiles: host.textProfilesSnapshot())
    }

    router.get("text-profiles/style") { _, _ -> TextProfileStyleResponse in
        await .init(textProfileStyle: host.textProfileStyleSnapshot())
    }

    router.get("text-profiles/base") { _, _ -> TextProfileResponse in
        await .init(profile: (host.textProfilesSnapshot()).baseProfile)
    }

    router.get("text-profiles/active") { _, _ -> TextProfileResponse in
        await .init(profile: (host.textProfilesSnapshot()).activeProfile)
    }

    router.get("text-profiles/effective") { _, _ -> TextProfileResponse in
        await .init(profile: host.effectiveTextProfile(nil))
    }

    router.get("text-profiles/effective/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        return await .init(profile: host.effectiveTextProfile(profileID))
    }

    router.get("text-profiles/stored/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        guard let profile = await host.storedTextProfile(profileID) else {
            throw HTTPError(
                .notFound,
                message: "Text profile '\(profileID)' was not found in the persisted SpeakSwiftly text-profile set.",
            )
        }

        return .init(profile: profile)
    }

    router.post("text-profiles/stored") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: CreateTextProfileRequestPayload.self, context: context)
        let profile = try await host.createTextProfile(
            id: payload.id,
            name: payload.name,
            replacements: payload.replacements.map { try $0.model() },
        )
        return .init(profile: profile)
    }

    router.post("text-profiles/load") { _, _ -> TextProfileListResponse in
        try await .init(textProfiles: host.loadTextProfiles())
    }

    router.post("text-profiles/save") { _, _ -> TextProfileListResponse in
        try await .init(textProfiles: host.saveTextProfiles())
    }

    router.put("text-profiles/style") { request, context -> TextProfileListResponse in
        let payload = try await request.decode(as: SetTextProfileStyleRequestPayload.self, context: context)
        return try await .init(textProfiles: host.setTextProfileStyle(payload.styleModel()))
    }

    router.put("text-profiles/stored/:profile_id") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let payload = try await request.decode(as: StoreTextProfileRequestPayload.self, context: context)
        guard payload.profile.id == profileID else {
            throw HTTPError(
                .badRequest,
                message: "Stored text profile route id '\(profileID)' did not match body profile id '\(payload.profile.id)'.",
            )
        }

        return try await .init(profile: host.storeTextProfile(payload.profile.model()))
    }

    router.put("text-profiles/active") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: UseTextProfileRequestPayload.self, context: context)
        return try await .init(profile: host.useTextProfile(payload.profile.model()))
    }

    router.post("text-profiles/active/reset") { _, _ -> TextProfileResponse in
        try await .init(profile: host.resetTextProfile())
    }

    router.delete("text-profiles/stored/:profile_id") { _, context -> TextProfileListResponse in
        let profileID = try context.parameters.require("profile_id")
        return try await .init(textProfiles: host.removeTextProfile(id: profileID))
    }

    router.post("text-profiles/active/replacements") { request, context -> TextProfileResponse in
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return try await .init(profile: host.addTextReplacement(payload.replacement.model()))
    }

    router.post("text-profiles/stored/:profile_id/replacements") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        return try await .init(profile: host.addTextReplacement(payload.replacement.model(), toStoredTextProfileID: profileID))
    }

    router.put("text-profiles/active/replacements/:replacement_id") { request, context -> TextProfileResponse in
        let replacementID = try context.parameters.require("replacement_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        guard payload.replacement.id == replacementID else {
            throw HTTPError(
                .badRequest,
                message: "Active text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'.",
            )
        }

        return try await .init(profile: host.replaceTextReplacement(payload.replacement.model()))
    }

    router.put("text-profiles/stored/:profile_id/replacements/:replacement_id") { request, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let replacementID = try context.parameters.require("replacement_id")
        let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
        guard payload.replacement.id == replacementID else {
            throw HTTPError(
                .badRequest,
                message: "Stored text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'.",
            )
        }

        return try await .init(profile: host.replaceTextReplacement(payload.replacement.model(), inStoredTextProfileID: profileID))
    }

    router.delete("text-profiles/active/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let replacementID = try context.parameters.require("replacement_id")
        return try await .init(profile: host.removeTextReplacement(id: replacementID))
    }

    router.delete("text-profiles/stored/:profile_id/replacements/:replacement_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        let replacementID = try context.parameters.require("replacement_id")
        return try await .init(profile: host.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID))
    }
}
