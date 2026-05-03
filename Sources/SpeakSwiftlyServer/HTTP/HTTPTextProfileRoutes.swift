import Hummingbird
import SpeakSwiftly

private func mapTextProfileRouteError(_ error: any Error) -> any Error {
    if error is HTTPError {
        return error
    }

    if let error = error as? SpeakSwiftly.Error {
        return HTTPError(
            .internalServerError,
            message: error.message,
        )
    }

    return HTTPError(
        .internalServerError,
        message: "SpeakSwiftlyServer could not complete the text-profile request. Likely cause: \(error.localizedDescription)",
    )
}

func registerHTTPTextProfileRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("text-profiles") { _, _ -> TextProfileListResponse in
        do {
            let snapshot = try await host.textProfilesSnapshot()
            return .init(textProfiles: snapshot)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.get("text-profiles/style") { _, _ -> TextProfileStyleResponse in
        await .init(textProfileStyle: host.textProfileStyleSnapshot())
    }

    router.get("text-profiles/base") { _, _ -> TextProfileResponse in
        do {
            let snapshot = try await host.textProfilesSnapshot()
            return .init(profile: snapshot.baseProfile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.get("text-profiles/active") { _, _ -> TextProfileResponse in
        do {
            let snapshot = try await host.textProfilesSnapshot()
            return .init(profile: snapshot.activeProfile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.get("text-profiles/effective") { _, _ -> TextProfileResponse in
        do {
            let profile = try await host.effectiveTextProfile(nil)
            return .init(profile: profile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.get("text-profiles/effective/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        do {
            let profile = try await host.effectiveTextProfile(profileID)
            return .init(profile: profile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.get("text-profiles/stored/:profile_id") { _, context -> TextProfileResponse in
        let profileID = try context.parameters.require("profile_id")
        do {
            guard let profile = try await host.storedTextProfile(profileID) else {
                throw HTTPError(
                    .notFound,
                    message: "Text profile '\(profileID)' was not found in the persisted SpeakSwiftly text-profile set.",
                )
            }

            return .init(profile: profile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/stored") { request, context -> TextProfileResponse in
        do {
            let payload = try await request.decode(as: CreateTextProfileRequestPayload.self, context: context)
            let profile = try await host.createTextProfile(
                name: payload.name,
                replacements: (payload.replacements ?? []).map { try $0.model() },
            )
            return .init(profile: profile)
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/load") { _, _ -> TextProfileListResponse in
        do {
            return try await .init(textProfiles: host.loadTextProfiles())
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/save") { _, _ -> TextProfileListResponse in
        do {
            return try await .init(textProfiles: host.saveTextProfiles())
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/style") { request, context -> TextProfileListResponse in
        do {
            let payload = try await request.decode(as: SetTextProfileStyleRequestPayload.self, context: context)
            return try await .init(textProfiles: host.setTextProfileStyle(payload.styleModel()))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/stored/:profile_id/name") { request, context -> TextProfileResponse in
        do {
            let profileID = try context.parameters.require("profile_id")
            let payload = try await request.decode(as: RenameTextProfileRequestPayload.self, context: context)
            return try await .init(profile: host.renameTextProfile(id: profileID, to: payload.name))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/active") { request, context -> TextProfileResponse in
        do {
            let payload = try await request.decode(as: SetActiveTextProfileRequestPayload.self, context: context)
            return try await .init(profile: host.setActiveTextProfile(id: payload.profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/factory-reset") { _, _ -> TextProfileListResponse in
        do {
            return try await .init(textProfiles: host.factoryResetTextProfiles())
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/stored/:profile_id/reset") { _, context -> TextProfileResponse in
        do {
            let profileID = try context.parameters.require("profile_id")
            return try await .init(profile: host.resetTextProfile(id: profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.delete("text-profiles/stored/:profile_id") { _, context -> TextProfileListResponse in
        do {
            let profileID = try context.parameters.require("profile_id")
            return try await .init(textProfiles: host.removeTextProfile(id: profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/replacements") { request, context -> TextProfileResponse in
        do {
            let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
            return try await .init(
                profile: host.addTextReplacement(
                    payload.replacement.model(),
                    toStoredTextProfileID: payload.targetProfileID,
                ),
            )
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/replacements/:replacement_id") { request, context -> TextProfileResponse in
        do {
            let replacementID = try context.parameters.require("replacement_id")
            let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
            guard payload.replacement.id == replacementID else {
                throw HTTPError(
                    .badRequest,
                    message: "Text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'.",
                )
            }

            return try await .init(
                profile: host.replaceTextReplacement(
                    payload.replacement.model(),
                    inStoredTextProfileID: payload.targetProfileID,
                ),
            )
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.delete("text-profiles/replacements/:replacement_id") { request, context -> TextProfileResponse in
        do {
            let replacementID = try context.parameters.require("replacement_id")
            let profileID = TextReplacementRequestPayload.normalizedTargetProfileID(
                request.uri.queryParameters["profile_id"].map(String.init),
            )
            return try await .init(profile: host.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/active/replacements") { request, context -> TextProfileResponse in
        do {
            let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
            return try await .init(profile: host.addTextReplacement(payload.replacement.model()))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.post("text-profiles/stored/:profile_id/replacements") { request, context -> TextProfileResponse in
        do {
            let profileID = try context.parameters.require("profile_id")
            let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
            return try await .init(profile: host.addTextReplacement(payload.replacement.model(), toStoredTextProfileID: profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/active/replacements/:replacement_id") { request, context -> TextProfileResponse in
        do {
            let replacementID = try context.parameters.require("replacement_id")
            let payload = try await request.decode(as: TextReplacementRequestPayload.self, context: context)
            guard payload.replacement.id == replacementID else {
                throw HTTPError(
                    .badRequest,
                    message: "Active text replacement route id '\(replacementID)' did not match body replacement id '\(payload.replacement.id)'.",
                )
            }

            return try await .init(profile: host.replaceTextReplacement(payload.replacement.model()))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.put("text-profiles/stored/:profile_id/replacements/:replacement_id") { request, context -> TextProfileResponse in
        do {
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
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.delete("text-profiles/active/replacements/:replacement_id") { _, context -> TextProfileResponse in
        do {
            let replacementID = try context.parameters.require("replacement_id")
            return try await .init(profile: host.removeTextReplacement(id: replacementID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }

    router.delete("text-profiles/stored/:profile_id/replacements/:replacement_id") { _, context -> TextProfileResponse in
        do {
            let profileID = try context.parameters.require("profile_id")
            let replacementID = try context.parameters.require("replacement_id")
            return try await .init(profile: host.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID))
        } catch {
            throw mapTextProfileRouteError(error)
        }
    }
}
