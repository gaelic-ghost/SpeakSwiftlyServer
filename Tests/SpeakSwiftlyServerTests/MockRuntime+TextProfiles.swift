import Foundation
import SpeakSwiftly
import TextForSpeech

// MARK: - Mock Runtime Text Profiles

@available(macOS 14, *)
extension MockRuntime {
    private func throwConfiguredTextProfileTransportErrorIfNeeded() throws {
        if let textProfileTransportError {
            throw textProfileTransportError
        }
    }

    func builtInTextProfileStyle() async -> TextForSpeech.BuiltInProfileStyle {
        textRuntime.style.getActive()
    }

    func setBuiltInTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws -> TextForSpeech.BuiltInProfileStyle {
        try textRuntime.style.setActive(to: style)
        return textRuntime.style.getActive()
    }

    func activeTextProfile() async throws -> SpeakSwiftly.TextProfileDetails {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        return transportDetails(textRuntime.profiles.getActive())
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        .builtInBase(style: textRuntime.style.getActive())
    }

    func textProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails? {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        guard let details = try? textRuntime.profiles.get(id: profileID) else {
            return nil
        }

        return transportDetails(details)
    }

    func textProfiles() async throws -> [SpeakSwiftly.TextProfileSummary] {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        return textRuntime.profiles.list().map(transportSummary)
    }

    func effectiveTextProfile(id profileID: String?) async throws -> SpeakSwiftly.TextProfileDetails {
        try throwConfiguredTextProfileTransportErrorIfNeeded()
        if let profileID,
           let details = try? textRuntime.profiles.get(id: profileID) {
            return transportDetails(details)
        }

        return transportDetails(textRuntime.profiles.getEffective())
    }

    func loadTextProfiles() async throws {
        loadTextProfilesCallCount += 1
    }

    func saveTextProfiles() async throws {
        saveTextProfilesCallCount += 1
    }

    func createTextProfile(named name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.create(name: name))
    }

    func renameTextProfile(id profileID: String, to name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.rename(profile: profileID, to: name))
    }

    func setActiveTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try textRuntime.profiles.setActive(id: profileID)
        return transportDetails(textRuntime.profiles.getActive())
    }

    func removeTextProfile(id profileID: String) async throws {
        try textRuntime.profiles.delete(id: profileID)
    }

    func factoryResetTextProfiles() async throws {
        try textRuntime.profiles.factoryReset()
    }

    func resetTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try textRuntime.profiles.reset(id: profileID)
        return try transportDetails(textRuntime.profiles.get(id: profileID))
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.addReplacement(replacement))
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.addReplacement(replacement, toProfile: profileID))
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.patchReplacement(replacement))
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.patchReplacement(replacement, inProfile: profileID))
    }

    func removeTextReplacement(id replacementID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.removeReplacement(id: replacementID))
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try transportDetails(textRuntime.profiles.removeReplacement(id: replacementID, fromProfile: profileID))
    }

    private func transportSummary(
        _ summary: TextForSpeech.Runtime.Profiles.Summary,
    ) -> SpeakSwiftly.TextProfileSummary {
        requireFixture("mock text-profile summary transport fixture") {
            try fixtureDecode(
                TextProfileSummaryFixture(
                    id: summary.id,
                    name: summary.name,
                    replacementCount: summary.replacementCount,
                ),
                as: SpeakSwiftly.TextProfileSummary.self,
            )
        }
    }

    private func transportDetails(
        _ details: TextForSpeech.Runtime.Profiles.Details,
    ) -> SpeakSwiftly.TextProfileDetails {
        requireFixture("mock text-profile details transport fixture") {
            try fixtureDecode(
                TextProfileDetailsFixture(
                    profileID: details.id,
                    summary: TextProfileSummaryFixture(
                        id: details.summary.id,
                        name: details.summary.name,
                        replacementCount: details.summary.replacementCount,
                    ),
                    replacements: details.replacements,
                ),
                as: SpeakSwiftly.TextProfileDetails.self,
            )
        }
    }
}

private struct TextProfileSummaryFixture: Codable {
    let id: String
    let name: String
    let replacementCount: Int

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case replacementCount = "replacement_count"
    }
}

private struct TextProfileDetailsFixture: Codable {
    let profileID: String
    let summary: TextProfileSummaryFixture
    let replacements: [TextForSpeech.Replacement]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case summary
        case replacements
    }
}
