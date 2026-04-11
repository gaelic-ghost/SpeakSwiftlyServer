import Foundation
import Hummingbird
import SpeakSwiftlyCore
import TextForSpeech

// MARK: - Profile Models

public struct ProfileSnapshot: Codable, Sendable, Equatable {
    public let profileName: String
    public let vibe: String
    public let createdAt: String
    public let voiceDescription: String
    public let sourceText: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case createdAt = "created_at"
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }

    init(profile: SpeakSwiftly.ProfileSummary) {
        self.profileName = profile.profileName
        self.vibe = profile.vibe.rawValue
        self.createdAt = TimestampFormatter.string(from: profile.createdAt)
        self.voiceDescription = profile.voiceDescription
        self.sourceText = profile.sourceText
    }
}

struct ProfileListResponse: ResponseEncodable, Sendable {
    let profiles: [ProfileSnapshot]
}

struct RenameVoiceProfileRequestPayload: Decodable {
    let newProfileName: String

    enum CodingKeys: String, CodingKey {
        case newProfileName = "new_profile_name"
    }
}

// MARK: - Text Profile Models

public struct TextReplacementSnapshot: Codable, Sendable, Equatable {
    let id: String
    let text: String
    let replacement: String
    let match: String
    let phase: String
    let isCaseSensitive: Bool
    let formats: [String]
    let priority: Int

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

    init(replacement: TextForSpeech.Replacement) {
        self.id = replacement.id
        self.text = replacement.text
        self.replacement = replacement.replacement ?? Self.describe(transform: replacement.transform)
        self.match = Self.describe(match: replacement.match)
        self.phase = replacement.phase.rawValue
        self.isCaseSensitive = replacement.isCaseSensitive
        self.formats = (
            replacement.textFormats.map(\.rawValue)
            + replacement.sourceFormats.map(\.rawValue)
        ).sorted()
        self.priority = replacement.priority
    }

    func model() throws -> TextForSpeech.Replacement {
        let match = try Self.resolve(match: match, replacementID: id)
        guard let phase = TextForSpeech.Replacement.Phase(rawValue: phase) else {
            throw HTTPError(
                .badRequest,
                message: "Text replacement '\(id)' used unsupported phase '\(phase)'. Expected one of: before_built_ins, after_built_ins."
            )
        }

        let resolvedFormats = try formats.map(resolveNormalizationFormat(_:))
        let textFormats: Set<TextForSpeech.TextFormat> = Set(resolvedFormats.compactMap { format in
            guard case .text(let textFormat) = format else {
                return nil
            }
            return textFormat
        })
        let sourceFormats: Set<TextForSpeech.SourceFormat> = Set(resolvedFormats.compactMap { format in
            guard case .source(let sourceFormat) = format else {
                return nil
            }
            return sourceFormat
        })
        return TextForSpeech.Replacement(
            text,
            with: replacement,
            id: id,
            matching: match,
            during: phase,
            caseSensitive: isCaseSensitive,
            forTextFormats: textFormats,
            forSourceFormats: sourceFormats,
            priority: priority
        )
    }

    private static func describe(match: TextForSpeech.Replacement.Match) -> String {
        switch match {
        case .exactPhrase:
            "exact_phrase"
        case .wholeToken:
            "whole_token"
        case .token(let kind):
            "token:\(kind.rawValue)"
        case .line(let kind):
            "line:\(kind.rawValue)"
        }
    }

    private static func describe(transform: TextForSpeech.Replacement.Transform) -> String {
        switch transform {
        case .literal(let replacement):
            replacement
        case .spokenPath:
            "spoken_path"
        case .spokenURL:
            "spoken_url"
        case .spokenIdentifier:
            "spoken_identifier"
        case .spokenCode:
            "spoken_code"
        case .spokenFunctionCall(let style):
            "spoken_function_call:\(style.rawValue)"
        case .spokenIssueReference(let style):
            "spoken_issue_reference:\(style.rawValue)"
        case .spokenFileReference(let style):
            "spoken_file_reference:\(style.rawValue)"
        case .spokenCLIFlag(let style):
            "spoken_cli_flag:\(style.rawValue)"
        case .spellOut:
            "spell_out"
        }
    }

    private static func resolve(
        match rawMatch: String,
        replacementID: String
    ) throws -> TextForSpeech.Replacement.Match {
        switch rawMatch {
        case "exact_phrase":
            return .exactPhrase
        case "whole_token":
            return .wholeToken
        default:
            if rawMatch.hasPrefix("token:") {
                let tokenKind = String(rawMatch.dropFirst("token:".count))
                if let kind = TextForSpeech.Replacement.TokenKind(rawValue: tokenKind) {
                    return .token(kind)
                }
            }
            if rawMatch.hasPrefix("line:") {
                let lineKind = String(rawMatch.dropFirst("line:".count))
                if let kind = TextForSpeech.Replacement.LineKind(rawValue: lineKind) {
                    return .line(kind)
                }
            }
            throw HTTPError(
                .badRequest,
                message: "Text replacement '\(replacementID)' used unsupported match '\(rawMatch)'. Expected one of: exact_phrase, whole_token, token:<kind>, line:<kind>."
            )
        }
    }
}

public struct TextProfileSnapshot: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let replacements: [TextReplacementSnapshot]

    init(profile: TextForSpeech.Profile) {
        self.id = profile.id
        self.name = profile.name
        self.replacements = profile.replacements.map(TextReplacementSnapshot.init(replacement:))
    }

    func model() throws -> TextForSpeech.Profile {
        try .init(
            id: id,
            name: name,
            replacements: replacements.map { try $0.model() }
        )
    }
}

struct TextProfileStyleSnapshot: Codable, Sendable, Equatable {
    let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }

    init(style: TextForSpeech.BuiltInProfileStyle) {
        builtInStyle = style.rawValue
    }
}

struct TextProfilesSnapshot: ResponseEncodable, Sendable, Equatable {
    let builtInStyle: String
    let baseProfile: TextProfileSnapshot
    let activeProfile: TextProfileSnapshot
    let storedProfiles: [TextProfileSnapshot]
    let effectiveProfile: TextProfileSnapshot

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
        case baseProfile = "base_profile"
        case activeProfile = "active_profile"
        case storedProfiles = "stored_profiles"
        case effectiveProfile = "effective_profile"
    }
}

struct TextProfileListResponse: ResponseEncodable, Sendable {
    let textProfiles: TextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }
}

struct TextProfileResponse: ResponseEncodable, Sendable {
    let profile: TextProfileSnapshot
}

struct TextProfileStyleResponse: ResponseEncodable, Sendable {
    let textProfileStyle: TextProfileStyleSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfileStyle = "text_profile_style"
    }
}

struct CreateTextProfileRequestPayload: Decodable {
    let id: String
    let name: String
    let replacements: [TextReplacementSnapshot]
}

struct StoreTextProfileRequestPayload: Decodable {
    let profile: TextProfileSnapshot
}

struct UseTextProfileRequestPayload: Decodable {
    let profile: TextProfileSnapshot
}

struct TextReplacementRequestPayload: Decodable {
    let replacement: TextReplacementSnapshot
}

struct SetTextProfileStyleRequestPayload: Decodable {
    let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }

    func styleModel() throws -> TextForSpeech.BuiltInProfileStyle {
        guard let style = TextForSpeech.BuiltInProfileStyle(rawValue: builtInStyle) else {
            let acceptedValues = TextForSpeech.BuiltInProfileStyle.allCases.map(\.rawValue).joined(separator: ", ")
            throw HTTPError(
                .badRequest,
                message: "Text-profile built_in_style '\(builtInStyle)' is not supported. Expected one of: \(acceptedValues)."
            )
        }
        return style
    }
}
