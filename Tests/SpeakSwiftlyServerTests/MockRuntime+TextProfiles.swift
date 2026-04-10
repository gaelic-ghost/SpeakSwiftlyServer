import Foundation
import TextForSpeech

// MARK: - Mock Runtime Text Profiles

@available(macOS 14, *)
extension MockRuntime {
    func activeTextProfile() async -> TextForSpeech.Profile {
        textRuntime.profiles.active() ?? .default
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        .init(id: "base", name: "Base")
    }

    func textProfile(id profileID: String) async -> TextForSpeech.Profile? {
        textRuntime.profiles.stored(id: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        textRuntime.profiles.list()
    }

    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile {
        textRuntime.profiles.effective(id: profileID) ?? .default
    }

    func loadTextProfiles() async throws {
        loadTextProfilesCallCount += 1
    }

    func saveTextProfiles() async throws {
        saveTextProfilesCallCount += 1
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement]
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.create(id: id, name: name, replacements: replacements)
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.profiles.store(profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.profiles.use(profile)
    }

    func removeTextProfile(id profileID: String) async throws {
        textRuntime.profiles.delete(id: profileID)
    }

    func resetTextProfile() async throws {
        textRuntime.profiles.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        textRuntime.profiles.add(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.add(replacement, toStoredProfileID: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.replace(replacement, inStoredProfileID: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.profiles.removeReplacement(id: replacementID, fromStoredProfileID: profileID)
    }
}
