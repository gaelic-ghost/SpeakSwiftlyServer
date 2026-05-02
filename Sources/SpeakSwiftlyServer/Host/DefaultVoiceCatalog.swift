import Foundation
import SpeakSwiftly

package enum DefaultVoiceCatalog {
    package static let resourceDirectory = "DefaultVoiceProfiles"
    package static let resourceName = "catalog"
    package static let resourceExtension = "json"

    package static func load(bundle: Bundle = .module) throws -> [DefaultVoiceSeed] {
        guard let catalogURL = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceDirectory,
        ) else {
            throw DefaultVoiceCatalogError(
                """
                SpeakSwiftlyServer could not load the built-in default voice catalog because the bundled resource '\(resourceDirectory)/\(resourceName).\(resourceExtension)' is missing.
                Likely cause: the package resource bundle was built without the default voice catalog.
                """,
            )
        }

        do {
            let data = try Data(contentsOf: catalogURL)
            let catalog = try JSONDecoder().decode(DefaultVoiceSeedCatalog.self, from: data)
            return catalog.voices
        } catch {
            throw DefaultVoiceCatalogError(
                """
                SpeakSwiftlyServer could not decode the built-in default voice catalog at '\(catalogURL.path)'.
                Likely cause: \(error.localizedDescription)
                """,
            )
        }
    }
}

package struct DefaultVoiceCatalogError: Error, CustomStringConvertible {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var description: String { message }
}

package struct DefaultVoiceSeedCatalog: Codable, Sendable, Equatable {
    package let catalogVersion: Int
    package let voices: [DefaultVoiceSeed]

    enum CodingKeys: String, CodingKey {
        case catalogVersion = "catalog_version"
        case voices
    }
}

package struct DefaultVoiceSeed: Codable, Sendable, Equatable, Identifiable {
    package let seedID: String
    package let seedVersion: String
    package let profileName: String
    package let fallbackProfileName: String
    package let author: DefaultVoiceSeedAuthor
    package let vibe: SpeakSwiftly.Vibe
    package let voiceDescription: String
    package let sourceText: String
    package let sourceKind: DefaultVoiceSeedSourceKind
    package let sampleMediaPath: String?

    package var id: String { seedID }

    enum CodingKeys: String, CodingKey {
        case seedID = "seed_id"
        case seedVersion = "seed_version"
        case profileName = "profile_name"
        case fallbackProfileName = "fallback_profile_name"
        case author
        case vibe
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
        case sourceKind = "source_kind"
        case sampleMediaPath = "sample_media_path"
    }
}

package enum DefaultVoiceSeedAuthor: String, Codable, Sendable {
    case system
}

package enum DefaultVoiceSeedSourceKind: String, Codable, Sendable {
    case generatedDesign = "generated_design"
}
