import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

// MARK: - Profile Query Surface

extension ServerHost {
    // MARK: - Voice Profile Queries

    func cachedProfiles() -> [ProfileSnapshot] {
        profileCache
    }

    func cachedProfile(_ profileName: String) -> ProfileSnapshot? {
        profileCache.first { $0.profileName == profileName }
    }

    func resolvedRequestedVoiceProfileName(_ requestedProfileName: String?) -> String? {
        let explicitProfileName = requestedProfileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitProfileName, !explicitProfileName.isEmpty {
            return explicitProfileName
        }
        return activeDefaultVoiceProfileName
    }

    func missingVoiceProfileNameMessage(for operation: String) -> String {
        "SpeakSwiftlyServer could not queue \(operation) because the request did not include 'profile_name' and the server does not have 'app.defaultVoiceProfileName' configured."
    }

    func defaultVoiceProfileName() -> SpeakSwiftly.Name? {
        activeDefaultVoiceProfileName
    }

    func setDefaultVoiceProfileName(_ profileName: SpeakSwiftly.Name) async throws -> SpeakSwiftly.Name {
        let normalizedProfileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProfileName.isEmpty else {
            throw ServerConfigurationError(
                "SpeakSwiftlyServer could not set the default voice profile because the requested profile name was empty.",
            )
        }

        activeDefaultVoiceProfileName = normalizedProfileName
        let runtimeConfigurationSnapshot = try runtimeConfigurationStore.saveDefaultVoiceProfileName(
            normalizedProfileName,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return normalizedProfileName
    }

    func clearDefaultVoiceProfileName() async throws -> SpeakSwiftly.Name? {
        let fallbackProfileName = configuration.defaultVoiceProfileName
        activeDefaultVoiceProfileName = fallbackProfileName
        let runtimeConfigurationSnapshot = try runtimeConfigurationStore.saveDefaultVoiceProfileName(
            nil,
            activeRuntimeSpeechBackend: activeRuntimeSpeechBackend,
            configuredDefaultVoiceProfileName: configuration.defaultVoiceProfileName,
        )
        emitRuntimeConfigurationChanged(runtimeConfigurationSnapshot)
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return fallbackProfileName
    }

    func refreshVoiceProfiles() async throws -> [ProfileSnapshot] {
        try await refreshProfiles(reason: "app_consumer")
    }

    // MARK: - Text Profile Queries

    func textProfilesSnapshot() async -> TextProfilesSnapshot {
        let builtInStyle = await runtime.builtInTextProfileStyle()
        return await .init(
            builtInStyle: builtInStyle.rawValue,
            baseProfile: .init(profile: runtime.baseTextProfile()),
            activeProfile: .init(profile: runtime.activeTextProfile()),
            storedProfiles: (runtime.textProfiles()).map(TextProfileSnapshot.init(profile:)),
            effectiveProfile: .init(profile: runtime.effectiveTextProfile(id: nil)),
        )
    }

    func textProfileStyleSnapshot() async -> TextProfileStyleSnapshot {
        await .init(style: runtime.builtInTextProfileStyle())
    }

    func storedTextProfile(_ profileID: String) async -> TextProfileSnapshot? {
        await runtime.textProfile(id: profileID).map(TextProfileSnapshot.init(profile:))
    }

    func effectiveTextProfile(_ profileID: String?) async -> TextProfileSnapshot {
        await .init(profile: runtime.effectiveTextProfile(id: profileID))
    }

    func createTextProfile(
        id: String,
        name: String,
        replacements: [TextForSpeech.Replacement],
    ) async throws -> TextProfileSnapshot {
        let profile = try await runtime.createTextProfile(id: id, named: name, replacements: replacements)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func loadTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.loadTextProfiles()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func saveTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.saveTextProfiles()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func setTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws -> TextProfilesSnapshot {
        _ = try await runtime.setBuiltInTextProfileStyle(style)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws -> TextProfileSnapshot {
        try await runtime.storeTextProfile(profile)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws -> TextProfileSnapshot {
        try await runtime.useTextProfile(profile)
        let activeProfile = await runtime.activeTextProfile()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: activeProfile)
    }

    func removeTextProfile(id profileID: String) async throws -> TextProfilesSnapshot {
        try await runtime.removeTextProfile(id: profileID)
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return await textProfilesSnapshot()
    }

    func resetTextProfile() async throws -> TextProfileSnapshot {
        try await runtime.resetTextProfile()
        let activeProfile = await runtime.activeTextProfile()
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: activeProfile)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile = if let profileID {
            try await runtime.addTextReplacement(replacement, toStoredTextProfileID: profileID)
        } else {
            try await runtime.addTextReplacement(replacement)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile = if let profileID {
            try await runtime.replaceTextReplacement(replacement, inStoredTextProfileID: profileID)
        } else {
            try await runtime.replaceTextReplacement(replacement)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: TextForSpeech.Profile = if let profileID {
            try await runtime.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID)
        } else {
            try await runtime.removeTextReplacement(id: replacementID)
        }
        await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(profile: profile)
    }
}
