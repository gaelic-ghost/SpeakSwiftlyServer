import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

/// Summary of one cached voice profile known to the shared runtime.
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

    init(
        profileName: String,
        vibe: String,
        createdAt: String,
        voiceDescription: String,
        sourceText: String,
    ) {
        self.profileName = profileName
        self.vibe = vibe
        self.createdAt = createdAt
        self.voiceDescription = voiceDescription
        self.sourceText = sourceText
    }

    init(profile: SpeakSwiftly.ProfileSummary) {
        profileName = profile.profileName
        vibe = profile.vibe.rawValue
        createdAt = TimestampFormatter.string(from: profile.createdAt)
        voiceDescription = profile.voiceDescription
        sourceText = profile.sourceText
    }
}

struct ProfileListResponse: ResponseEncodable {
    let profiles: [ProfileSnapshot]
}

struct RenameVoiceProfileRequestPayload: Decodable {
    let newProfileName: String

    enum CodingKeys: String, CodingKey {
        case newProfileName = "new_profile_name"
    }
}

/// One text-normalization replacement rule exposed through the server surfaces.
struct TextReplacementSnapshot: Codable, Equatable {
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

    let id: String
    let text: String
    let replacement: String
    let match: String
    let phase: String
    let isCaseSensitive: Bool
    let formats: [String]
    let priority: Int

    init(replacement: TextForSpeech.Replacement) {
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

    private static func describe(match: TextForSpeech.Replacement.Match) -> String {
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

    private static func describe(transform: TextForSpeech.Replacement.Transform) -> String {
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
            case .spellOut:
                "spell_out"
        }
    }

    private static func resolve(
        match rawMatch: String,
        replacementID: String,
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
                    message: "Text replacement '\(replacementID)' used unsupported match '\(rawMatch)'. Expected one of: exact_phrase, whole_token, token:<kind>, line:<kind>.",
                )
        }
    }

    func model() throws -> TextForSpeech.Replacement {
        let match = try Self.resolve(match: match, replacementID: id)
        guard let phase = TextForSpeech.Replacement.Phase(rawValue: phase) else {
            throw HTTPError(
                .badRequest,
                message: "Text replacement '\(id)' used unsupported phase '\(phase)'. Expected one of: before_built_ins, after_built_ins.",
            )
        }

        let resolvedFormats = try formats.map(resolveNormalizationFormat(_:))
        let textFormats: Set<TextForSpeech.TextFormat> = Set(resolvedFormats.compactMap { format in
            guard case let .text(textFormat) = format else {
                return nil
            }

            return textFormat
        })
        let sourceFormats: Set<TextForSpeech.SourceFormat> = Set(resolvedFormats.compactMap { format in
            guard case let .source(sourceFormat) = format else {
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
            priority: priority,
        )
    }
}

/// One text profile and its replacement rules as exposed by the server.
struct TextProfileSnapshot: Codable, Equatable {
    let id: String
    let name: String
    let replacements: [TextReplacementSnapshot]

    init(profile: TextForSpeech.Profile) {
        id = profile.id
        name = profile.name
        replacements = profile.replacements.map(TextReplacementSnapshot.init(replacement:))
    }

    func model() throws -> TextForSpeech.Profile {
        try .init(
            id: id,
            name: name,
            replacements: replacements.map { try $0.model() },
        )
    }
}

struct TextProfileStyleSnapshot: Codable, Equatable {
    let builtInStyle: String

    enum CodingKeys: String, CodingKey {
        case builtInStyle = "built_in_style"
    }

    init(style: TextForSpeech.BuiltInProfileStyle) {
        builtInStyle = style.rawValue
    }
}

struct TextProfilesSnapshot: ResponseEncodable, Equatable {
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

struct TextProfileListResponse: ResponseEncodable {
    let textProfiles: TextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }
}

struct TextProfileResponse: ResponseEncodable {
    let profile: TextProfileSnapshot
}

struct TextProfileStyleResponse: ResponseEncodable {
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
                message: "Text-profile built_in_style '\(builtInStyle)' is not supported. Expected one of: \(acceptedValues).",
            )
        }

        return style
    }
}
