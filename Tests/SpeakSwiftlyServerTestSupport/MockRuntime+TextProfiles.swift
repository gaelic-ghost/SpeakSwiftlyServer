import Foundation
import SpeakSwiftly

// MARK: - Mock Runtime Text Profiles

@available(macOS 14, *)
package extension MockRuntime {
    private func throwConfiguredTextProfileTransportErrorIfNeeded() throws {
        if let textProfileTransportError {
            throw textProfileTransportError
        }
    }

    func builtInTextProfileStyle() async -> SpeakSwiftly.TextProfileStyle {
        await textRuntime.style.getActive()
    }

    func setBuiltInTextProfileStyle(
        _ style: SpeakSwiftly.TextProfileStyle,
    ) async throws -> SpeakSwiftly.TextProfileStyle {
        try await textRuntime.style.setActive(to: style)
        return await textRuntime.style.getActive()
    }

    func activeTextProfile() async throws -> SpeakSwiftly.TextProfileDetails {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        return await textRuntime.profiles.getActive()
    }

    func baseTextProfile() async -> SpeakSwiftly.TextProfile {
        let style = await textRuntime.style.getActive()
        return .builtInBase(style: style)
    }

    func textProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails? {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        guard let details = try? await textRuntime.profiles.get(id: profileID) else {
            return nil
        }

        return details
    }

    func textProfiles() async throws -> [SpeakSwiftly.TextProfileSummary] {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        return await textRuntime.profiles.list()
    }

    func effectiveTextProfile(id profileID: String?) async throws -> SpeakSwiftly.TextProfileDetails {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        if let profileID,
           let details = try? await textRuntime.profiles.get(id: profileID) {
            return details
        }

        return await textRuntime.profiles.getEffective()
    }

    func loadTextProfiles() async throws {
        loadTextProfilesCallCount += 1
    }

    func saveTextProfiles() async throws {
        saveTextProfilesCallCount += 1
    }

    func createTextProfile(named name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.create(name: name)
    }

    func renameTextProfile(id profileID: String, to name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.rename(profile: profileID, to: name)
    }

    func setActiveTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.setActive(id: profileID)
        return await textRuntime.profiles.getActive()
    }

    func removeTextProfile(id profileID: String) async throws {
        try await textRuntime.profiles.delete(id: profileID)
    }

    func factoryResetTextProfiles() async throws {
        try await textRuntime.profiles.factoryReset()
    }

    func resetTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.reset(id: profileID)
        return try await textRuntime.profiles.get(id: profileID)
    }

    func addTextReplacement(_ replacement: SpeakSwiftly.TextReplacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        toStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.addReplacement(replacement, toProfile: profileID)
    }

    func replaceTextReplacement(_ replacement: SpeakSwiftly.TextReplacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.patchReplacement(replacement)
    }

    func replaceTextReplacement(
        _ replacement: SpeakSwiftly.TextReplacement,
        inStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.patchReplacement(replacement, inProfile: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await textRuntime.profiles.removeReplacement(id: replacementID, fromProfile: profileID)
    }
}
