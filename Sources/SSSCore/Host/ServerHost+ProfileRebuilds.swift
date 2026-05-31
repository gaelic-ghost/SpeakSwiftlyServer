import Foundation
import SpeakSwiftly

package extension ServerHost {
    func rebuildOutdatedUserProfiles(after profiles: [ProfileSnapshot]) async throws -> [ProfileSnapshot] {
        let scanner = ProfileManifestVersionScanner(rootURL: runtimeStartupConfigurationStore.profileStoreRootURL())
        let outdatedProfiles = scanner.profilesNeedingRebuild(from: profiles)
        guard !outdatedProfiles.isEmpty else {
            return profiles
        }

        var currentProfiles = profiles
        for profile in outdatedProfiles {
            guard !profile.isSystemAuthored else {
                recordRecentError(
                    source: "voices:profile-rebuild",
                    code: "system_profile_rebuild_skipped",
                    message: "SpeakSwiftlyServer found system-authored voice profile '\(profile.profileName)' with a pre-v7.1 manifest, but system profiles are not rerolled in place. Likely cause: the profile was installed before SpeakSwiftly v7.1.0; recreate the bundled seed if this profile sounds stale.",
                )
                continue
            }

            try await rerollOutdatedUserProfile(profile.profileName)
            currentProfiles = try await refreshProfiles(reason: "profile_rebuild:\(profile.profileName)")
        }

        return currentProfiles
    }

    private func rerollOutdatedUserProfile(_ profileName: String) async throws {
        let handle = await runtime.rerollVoiceProfile(profileName: profileName)
        let completion = try await awaitImmediateCompletion(
            handle: handle,
            missingTerminalMessage: "SpeakSwiftly finished the automatic profile rebuild request for '\(profileName)' without yielding a terminal success payload.",
            unexpectedFailureMessagePrefix: "SpeakSwiftly failed while automatically rebuilding voice profile '\(profileName)'.",
        )
        guard case let .voiceProfile(name: name?, path: _) = completion, name == profileName else {
            throw SpeakSwiftly.Error(
                code: .internalError,
                message: "SpeakSwiftly rebuilt voice profile '\(profileName)', but the completion payload reported a different or missing profile name.",
            )
        }
    }
}
