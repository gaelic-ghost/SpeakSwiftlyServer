import Foundation
import SpeakSwiftly

extension ServerHost {
    func installMissingBuiltInVoices(after profiles: [ProfileSnapshot]) async throws -> [ProfileSnapshot] {
        var currentProfiles = profiles
        let seeds = try BuiltInVoiceSeedCatalog.load()

        for seed in seeds {
            guard let targetProfileName = builtInVoiceInstallName(for: seed, in: currentProfiles) else {
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
               profileMatchesBuiltInVoiceSeed(targetProfile, seed: seed) {
                continue
            }

            try await createBuiltInVoice(seed, profileName: targetProfileName)
            currentProfiles = try await refreshProfiles(reason: "default_voice_seed:\(seed.seedID)")
        }

        return currentProfiles
    }

    private func builtInVoiceInstallName(
        for seed: BuiltInVoiceSeed,
        in profiles: [ProfileSnapshot],
    ) -> String? {
        if let existingProfile = profiles.first(where: { $0.profileName == seed.profileName }) {
            if profileMatchesBuiltInVoiceSeed(existingProfile, seed: seed) {
                return seed.profileName
            }
            if let fallbackProfile = profiles.first(where: { $0.profileName == seed.fallbackProfileName }) {
                return profileMatchesBuiltInVoiceSeed(fallbackProfile, seed: seed) ? seed.fallbackProfileName : nil
            }
            return seed.fallbackProfileName
        }

        if let fallbackProfile = profiles.first(where: { $0.profileName == seed.fallbackProfileName }),
           profileMatchesBuiltInVoiceSeed(fallbackProfile, seed: seed) {
            return seed.fallbackProfileName
        }

        return seed.profileName
    }

    private func profileMatchesBuiltInVoiceSeed(
        _ profile: ProfileSnapshot,
        seed: BuiltInVoiceSeed,
    ) -> Bool {
        if profile.author == SpeakSwiftly.ProfileAuthor.system.rawValue,
           profile.seedID == seed.seedID {
            return profile.seedVersion == seed.seedVersion
        }

        return profile.vibe == seed.vibe.rawValue
            && profile.voiceDescription == seed.voiceDescription
            && profile.sourceText == seed.sourceText
    }

    private func createBuiltInVoice(
        _ seed: BuiltInVoiceSeed,
        profileName: String,
    ) async throws {
        let handle = await runtime.createSystemVoiceProfileFromDescription(
            profileName: profileName,
            vibe: seed.vibe,
            from: seed.sourceText,
            voice: seed.voiceDescription,
            seed: seed.profileSeed(installedProfileName: profileName),
            outputPath: nil,
            cwd: nil,
        )
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the built-in default voice install request for '\(profileName)' without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while installing built-in default voice '\(profileName)'.",
        )
        guard case let .voiceProfile(name: name?, path: _) = completion, name == profileName else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly installed built-in default voice '\(profileName)', but the completion payload reported a different or missing profile name.",
            )
        }
    }
}
