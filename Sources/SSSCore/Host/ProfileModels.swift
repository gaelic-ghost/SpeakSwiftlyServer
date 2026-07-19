import Foundation
import SpeakSwiftly

/// Summary of one cached voice profile known to the shared runtime.
public struct ProfileSnapshot: Codable, Sendable, Equatable {
    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case createdAt = "created_at"
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
        case author
        case seedID = "seed_id"
        case seedVersion = "seed_version"
    }

    public let profileName: String
    public let vibe: String
    public let createdAt: String
    public let voiceDescription: String
    public let sourceText: String
    public let author: String
    public let seedID: String?
    public let seedVersion: String?

    public var isSystemAuthored: Bool {
        author == SpeakSwiftly.ProfileAuthor.system.rawValue
    }

    init(
        profileName: String,
        vibe: String,
        createdAt: String,
        voiceDescription: String,
        sourceText: String,
        author: String = SpeakSwiftly.ProfileAuthor.user.rawValue,
        seedID: String? = nil,
        seedVersion: String? = nil,
    ) {
        self.profileName = profileName
        self.vibe = vibe
        self.createdAt = createdAt
        self.voiceDescription = voiceDescription
        self.sourceText = sourceText
        self.author = author
        self.seedID = seedID
        self.seedVersion = seedVersion
    }

    init(profile: SpeakSwiftly.ProfileSummary) {
        profileName = profile.profileName
        vibe = profile.vibe.rawValue
        createdAt = TimestampFormatter.string(from: profile.createdAt)
        voiceDescription = profile.voiceDescription
        sourceText = profile.sourceText
        author = profile.author.rawValue
        seedID = profile.seedID
        seedVersion = profile.seedVersion
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileName, forKey: .profileName)
        try container.encode(vibe, forKey: .vibe)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(author, forKey: .author)
        try container.encodeIfPresent(seedID, forKey: .seedID)
        try container.encodeIfPresent(seedVersion, forKey: .seedVersion)

        if isSystemAuthored {
            try container.encode(
                "System-authored built-in voice profile. Deep seed source text is available only through maintainer/tool surfaces.",
                forKey: .sourceText,
            )
            try container.encode(
                "System-authored built-in voice profile. Deep voice-design prompt is available only through maintainer/tool surfaces.",
                forKey: .voiceDescription,
            )
        } else {
            try container.encode(sourceText, forKey: .sourceText)
            try container.encode(voiceDescription, forKey: .voiceDescription)
        }
    }
}

package struct ProfileListResponse: Encodable {
    package let profiles: [ProfileSnapshot]

    package init(profiles: [ProfileSnapshot]) {
        self.profiles = profiles
    }
}

package struct RenameVoiceProfileRequestPayload: Decodable {
    package let newProfileName: String

    enum CodingKeys: String, CodingKey {
        case newProfileName = "new_profile_name"
    }
}

/// One text-normalization replacement rule exposed through the server surfaces.
package struct TextReplacementSnapshot: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case id
        case text
        case replacement
        case match
        case phase
        case isCaseSensitive = "is_case_sensitive"
        case formats
        case priority
    }

    package let id: String
    package let text: String
    package let replacement: String
    package let match: String
    package let phase: String
    package let isCaseSensitive: Bool
    package let formats: [String]
    package let priority: Int

    init(replacement: SpeakSwiftly.TextReplacement) {
        id = replacement.id
        text = replacement.text
        self.replacement = replacement.replacement ?? Self.describe(transform: replacement.transform)
        match = Self.describe(match: replacement.match)
        phase = replacement.phase.rawValue
        isCaseSensitive = replacement.isCaseSensitive
        formats = (
            replacement.textFormats.map(\.rawValue)
                + replacement.sourceFormats.map(\.rawValue),
        ).sorted()
        priority = replacement.priority
    }

    private static func describe(match: SpeakSwiftly.TextReplacement.Match) -> String {
        switch match {
            case .exactPhrase:
                "exact_phrase"
            case .wholeToken:
                "whole_token"
            case let .token(kind):
                "token:\(kind.rawValue)"
            case let .line(kind):
                "line:\(kind.rawValue)"
        }
    }

    private static func describe(transform: SpeakSwiftly.TextReplacement.Transform) -> String {
        switch transform {
            case let .literal(replacement):
                replacement
            case .spokenPath:
                "spoken_path"
            case .spokenURL:
                "spoken_url"
            case .spokenIdentifier:
                "spoken_identifier"
            case .spokenCode:
                "spoken_code"
            case let .spokenFunctionCall(style):
                "spoken_function_call:\(style.rawValue)"
            case let .spokenIssueReference(style):
                "spoken_issue_reference:\(style.rawValue)"
            case let .spokenFileReference(style):
                "spoken_file_reference:\(style.rawValue)"
            case let .spokenCLIFlag(style):
                "spoken_cli_flag:\(style.rawValue)"
            case .spokenCurrencyAmount:
                "spoken_currency_amount"
            case .spokenMeasuredValue:
                "spoken_measured_value"
            case .spellOut:
                "spell_out"
        }
    }

    private static func resolve(
        match rawMatch: String,
        replacementID: String,
    ) throws -> SpeakSwiftly.TextReplacement.Match {
        switch rawMatch {
            case "exact_phrase":
                return .exactPhrase
            case "whole_token":
                return .wholeToken
            default:
                if rawMatch.hasPrefix("token:") {
                    let tokenKind = String(rawMatch.dropFirst("token:".count))
                    if let kind = SpeakSwiftly.TextReplacement.TokenKind(rawValue: tokenKind) {
                        return .token(kind)
                    }
                }
                if rawMatch.hasPrefix("line:") {
                    let lineKind = String(rawMatch.dropFirst("line:".count))
                    if let kind = SpeakSwiftly.TextReplacement.LineKind(rawValue: lineKind) {
                        return .line(kind)
                    }
                }
                throw ServerRequestError(
                    .badRequest,
                    message: "Text replacement '\(replacementID)' used unsupported match '\(rawMatch)'. Expected one of: exact_phrase, whole_token, token:<kind>, line:<kind>.",
                )
        }
    }

    package func model() throws -> SpeakSwiftly.TextReplacement {
        let match = try Self.resolve(match: match, replacementID: id)
        guard let phase = SpeakSwiftly.TextReplacement.Phase(rawValue: phase) else {
            throw ServerRequestError(
                .badRequest,
                message: "Text replacement '\(id)' used unsupported phase '\(phase)'. Expected one of: before_built_ins, after_built_ins.",
            )
        }

        let resolvedFormats = try formats.map(resolveNormalizationFormat(_:))
        let textFormats: Set<SpeakSwiftly.TextFormat> = Set(resolvedFormats.compactMap { format in
            guard case let .text(textFormat) = format else {
                return nil
            }

            return textFormat
        })
        let sourceFormats: Set<SpeakSwiftly.SourceFormat> = Set(resolvedFormats.compactMap { format in
            guard case let .source(sourceFormat) = format else {
                return nil
            }

            return sourceFormat
        })
        return SpeakSwiftly.TextReplacement(
            text,
            with: replacement,
            id: id,
            matching: match,
            during: phase,
            caseSensitive: isCaseSensitive,
            forTextFormats: textFormats,
            forSourceFormats: sourceFormats,
            priority: priority,
        )
    }
}

/// One text profile summary or detail object as exposed by the server.
package struct TextProfileSnapshot: Codable, Equatable {
    package let profileID: String
    package let name: String
    package let replacementCount: Int?
    package let replacements: [TextReplacementSnapshot]?

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case name
        case replacementCount = "replacement_count"
        case replacements
    }

    init(profile: SpeakSwiftly.TextProfile) {
        profileID = profile.id
        name = profile.name
        replacementCount = profile.replacements.count
        replacements = profile.replacements.map(TextReplacementSnapshot.init(replacement:))
    }

    init(summary: SpeakSwiftly.TextProfileSummary) {
        profileID = summary.id
        name = summary.name
        replacementCount = summary.replacementCount
        replacements = nil
    }

    init(details: SpeakSwiftly.TextProfileDetails) {
        profileID = details.profileID
        name = details.summary.name
        replacementCount = details.summary.replacementCount
        replacements = details.replacements.map(TextReplacementSnapshot.init(replacement:))
    }

    package func replacementModels() throws -> [SpeakSwiftly.TextReplacement] {
        try (replacements ?? []).map { try $0.model() }
    }
}

package struct TextProfileStyleSnapshot: Codable, Equatable {
    package let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }

    init(style: SpeakSwiftly.TextProfileStyle) {
        builtInStyle = style.rawValue
    }
}

package struct TextProfilesSnapshot: Encodable, Equatable {
    package let builtInStyle: String
    package let baseProfile: TextProfileSnapshot
    package let activeProfile: TextProfileSnapshot
    package let storedProfiles: [TextProfileSnapshot]
    package let effectiveProfile: TextProfileSnapshot

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
        case baseProfile = "base_profile"
        case activeProfile = "active_profile"
        case storedProfiles = "stored_profiles"
        case effectiveProfile = "effective_profile"
    }

    package init(
        builtInStyle: String,
        baseProfile: TextProfileSnapshot,
        activeProfile: TextProfileSnapshot,
        storedProfiles: [TextProfileSnapshot],
        effectiveProfile: TextProfileSnapshot,
    ) {
        self.builtInStyle = builtInStyle
        self.baseProfile = baseProfile
        self.activeProfile = activeProfile
        self.storedProfiles = storedProfiles
        self.effectiveProfile = effectiveProfile
    }
}

package struct TextProfileListResponse: Encodable {
    package let textProfiles: TextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }

    package init(textProfiles: TextProfilesSnapshot) {
        self.textProfiles = textProfiles
    }
}

package struct TextProfileResponse: Encodable {
    package let profile: TextProfileSnapshot

    package init(profile: TextProfileSnapshot) {
        self.profile = profile
    }
}

package struct TextProfileStyleResponse: Encodable {
    package let textProfileStyle: TextProfileStyleSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfileStyle = "text_profile_style"
    }

    package init(textProfileStyle: TextProfileStyleSnapshot) {
        self.textProfileStyle = textProfileStyle
    }
}

package struct CreateTextProfileRequestPayload: Decodable {
    package let name: String
    package let replacements: [TextReplacementSnapshot]?
}

package struct RenameTextProfileRequestPayload: Decodable {
    package let name: String
}

package struct SetActiveTextProfileRequestPayload: Decodable {
    package let profileID: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
    }
}

package struct ResetTextProfileRequestPayload: Decodable {
    package let profileID: String

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
    }
}

package struct TextReplacementRequestPayload: Decodable {
    package let profileID: String?
    package let replacement: TextReplacementSnapshot

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case replacement
    }

    package var targetProfileID: String? {
        Self.normalizedTargetProfileID(profileID)
    }

    package static func normalizedTargetProfileID(_ profileID: String?) -> String? {
        let trimmedProfileID = profileID?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedProfileID?.isEmpty == false ? trimmedProfileID : nil
    }
}

package struct SetTextProfileStyleRequestPayload: Decodable {
    package let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }

    package func styleModel() throws -> SpeakSwiftly.TextProfileStyle {
        guard let style = SpeakSwiftly.TextProfileStyle(rawValue: builtInStyle) else {
            let acceptedValues = SpeakSwiftly.TextProfileStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw ServerRequestError(
                .badRequest,
                message: "Text-profile built_in_style '\(builtInStyle)' is not supported. Expected one of: \(acceptedValues).",
            )
        }

        return style
    }
}
