import Foundation
import SpeakSwiftly

extension ServerHost {
    func installMissingDefaultVoices(after profiles: [ProfileSnapshot]) async throws -> [ProfileSnapshot] {
        var currentProfiles = profiles
        let seeds = try DefaultVoiceCatalog.load()

        for seed in seeds {
            guard let targetProfileName = defaultVoiceInstallName(for: seed, in: currentProfiles) else {
                recordRecentError(
                    source: "voices:default-install",
                    code: "default_voice_seed_conflict",
                    message: """
                    SpeakSwiftlyServer skipped built-in default voice seed '\(seed.seedID)' because both '\(seed.profileName)' and '\(seed.fallbackProfileName)' already exist and neither profile matches the bundled seed text and voice description.
                    """,
                )
                continue
            }

            if let targetProfile = currentProfiles.first(where: { $0.profileName == targetProfileName }),
               profileMatchesDefaultVoiceSeed(targetProfile, seed: seed) {
                continue
            }

            try await createDefaultVoice(seed, profileName: targetProfileName)
            currentProfiles = try await refreshProfiles(reason: "default_voice_seed:\(seed.seedID)")
        }

        return currentProfiles
    }

    private func defaultVoiceInstallName(
        for seed: DefaultVoiceSeed,
        in profiles: [ProfileSnapshot],
    ) -> String? {
        if let existingProfile = profiles.first(where: { $0.profileName == seed.profileName }) {
            if profileMatchesDefaultVoiceSeed(existingProfile, seed: seed) {
                return seed.profileName
            }
            if let fallbackProfile = profiles.first(where: { $0.profileName == seed.fallbackProfileName }) {
                return profileMatchesDefaultVoiceSeed(fallbackProfile, seed: seed) ? seed.fallbackProfileName : nil
            }
            return seed.fallbackProfileName
        }

        if let fallbackProfile = profiles.first(where: { $0.profileName == seed.fallbackProfileName }),
           profileMatchesDefaultVoiceSeed(fallbackProfile, seed: seed) {
            return seed.fallbackProfileName
        }

        return seed.profileName
    }

    private func profileMatchesDefaultVoiceSeed(
        _ profile: ProfileSnapshot,
        seed: DefaultVoiceSeed,
    ) -> Bool {
        profile.vibe == seed.vibe.rawValue
            && profile.voiceDescription == seed.voiceDescription
            && profile.sourceText == seed.sourceText
    }

    private func createDefaultVoice(
        _ seed: DefaultVoiceSeed,
        profileName: String,
    ) async throws {
        let handle = await runtime.createVoiceProfileFromDescription(
            profileName: profileName,
            vibe: seed.vibe,
            from: seed.sourceText,
            voice: seed.voiceDescription,
            outputPath: nil,
            cwd: nil,
        )
        let success = try await awaitImmediateSuccess(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the built-in default voice install request for '\(profileName)' without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while installing built-in default voice '\(profileName)'.",
        )
        guard success.profileName == profileName else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly installed built-in default voice '\(profileName)', but the success payload reported '\(success.profileName ?? "<missing>")' instead.",
            )
        }
    }
}
