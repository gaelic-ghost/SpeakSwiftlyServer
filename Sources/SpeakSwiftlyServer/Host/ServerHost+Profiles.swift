import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

extension ServerHost {
    // MARK: - Voice Profile Queries

    func cachedProfiles() -> [ProfileSnapshot] {
        profileCache
    }

    func cachedProfile(_ profileName: String) -> ProfileSnapshot? {
        profileCache.first { $0.profileName == profileName }
    }

    func resolvedRequestedVoiceProfileName(_ requestedProfileName: String?) async -> String? {
        let explicitProfileName = requestedProfileName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let explicitProfileName, !explicitProfileName.isEmpty {
            return explicitProfileName
        }

        if let activeDefaultVoiceProfileName {
            return activeDefaultVoiceProfileName
        }

        let runtimeDefaultVoiceProfile = await runtime.runtimeSnapshot()
            .defaultVoiceProfile
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return runtimeDefaultVoiceProfile.isEmpty ? nil : runtimeDefaultVoiceProfile
    }

    func missingVoiceProfileNameMessage(for operation: String) -> String {
        "SpeakSwiftlyServer could not queue \(operation) because the request did not include 'profile_name', the server does not have 'app.defaultVoiceProfileName' configured, and the runtime did not report a default voice profile."
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
        let runtimeConfigurationSnapshot = try runtimeStartupConfigurationStore.saveDefaultVoiceProfileName(
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
        let runtimeConfigurationSnapshot = try runtimeStartupConfigurationStore.saveDefaultVoiceProfileName(
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

    func textProfilesSnapshot() async throws -> TextProfilesSnapshot {
        let builtInStyle = await runtime.builtInTextProfileStyle()
        let baseProfile = await runtime.baseTextProfile()
        let activeProfile = try await runtime.activeTextProfile()
        let storedProfiles = try await runtime.textProfiles()
        let effectiveProfile = try await runtime.effectiveTextProfile(id: nil)
        return .init(
            builtInStyle: builtInStyle.rawValue,
            baseProfile: .init(profile: baseProfile),
            activeProfile: .init(details: activeProfile),
            storedProfiles: storedProfiles.map(TextProfileSnapshot.init(summary:)),
            effectiveProfile: .init(details: effectiveProfile),
        )
    }

    func textProfileStyleSnapshot() async -> TextProfileStyleSnapshot {
        await .init(style: runtime.builtInTextProfileStyle())
    }

    func storedTextProfile(_ profileID: String) async throws -> TextProfileSnapshot? {
        let profile = try await runtime.textProfile(id: profileID)
        return profile.map(TextProfileSnapshot.init(details:))
    }

    func effectiveTextProfile(_ profileID: String?) async throws -> TextProfileSnapshot {
        let profile = try await runtime.effectiveTextProfile(id: profileID)
        return .init(details: profile)
    }

    func createTextProfile(
        name: String,
        replacements: [TextForSpeech.Replacement],
    ) async throws -> TextProfileSnapshot {
        let profile = try await runtime.createTextProfile(named: name)
        if replacements.isEmpty == false {
            for replacement in replacements {
                _ = try await runtime.addTextReplacement(replacement, toStoredTextProfileID: profile.profileID)
            }
        }

        let refreshedProfile = try await runtime.textProfile(id: profile.profileID) ?? profile
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: refreshedProfile)
    }

    func loadTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.loadTextProfiles()
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return try await textProfilesSnapshot()
    }

    func saveTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.saveTextProfiles()
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return try await textProfilesSnapshot()
    }

    func setTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws -> TextProfilesSnapshot {
        _ = try await runtime.setBuiltInTextProfileStyle(style)
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return try await textProfilesSnapshot()
    }

    func renameTextProfile(id profileID: String, to name: String) async throws -> TextProfileSnapshot {
        let profile = try await runtime.renameTextProfile(id: profileID, to: name)
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }

    func setActiveTextProfile(id profileID: String) async throws -> TextProfileSnapshot {
        let profile = try await runtime.setActiveTextProfile(id: profileID)
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }

    func removeTextProfile(id profileID: String) async throws -> TextProfilesSnapshot {
        try await runtime.removeTextProfile(id: profileID)
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return try await textProfilesSnapshot()
    }

    func factoryResetTextProfiles() async throws -> TextProfilesSnapshot {
        try await runtime.factoryResetTextProfiles()
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return try await textProfilesSnapshot()
    }

    func resetTextProfile(id profileID: String) async throws -> TextProfileSnapshot {
        let profile = try await runtime.resetTextProfile(id: profileID)
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: SpeakSwiftly.TextProfileDetails = if let profileID {
            try await runtime.addTextReplacement(replacement, toStoredTextProfileID: profileID)
        } else {
            try await runtime.addTextReplacement(replacement)
        }
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: SpeakSwiftly.TextProfileDetails = if let profileID {
            try await runtime.replaceTextReplacement(replacement, inStoredTextProfileID: profileID)
        } else {
            try await runtime.replaceTextReplacement(replacement)
        }
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String? = nil,
    ) async throws -> TextProfileSnapshot {
        let profile: SpeakSwiftly.TextProfileDetails = if let profileID {
            try await runtime.removeTextReplacement(id: replacementID, fromStoredTextProfileID: profileID)
        } else {
            try await runtime.removeTextReplacement(id: replacementID)
        }
        try await emitTextProfilesChanged()
        await requestPublish(mode: .immediate, refreshRuntimeState: false)
        return .init(details: profile)
    }
}
