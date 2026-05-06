import Foundation
import SpeakSwiftly

package enum BuiltInVoiceSeedCatalog {
    package static let resourceDirectory = "DefaultVoiceProfiles"
    package static let resourceName = "catalog"
    package static let resourceExtension = "json"

    package static func load(bundle: Bundle = .module) throws -> [BuiltInVoiceSeed] {
        guard let catalogURL = bundle.url(
            forResource: resourceName,
            withExtension: resourceExtension,
            subdirectory: resourceDirectory,
        ) else {
            throw BuiltInVoiceSeedCatalogError(
                """
                SpeakSwiftlyServer could not load the built-in default voice catalog because the bundled resource '\(resourceDirectory)/\(resourceName).\(resourceExtension)' is missing.
                Likely cause: the package resource bundle was built without the default voice catalog.
                """,
            )
        }

        do {
            let data = try Data(contentsOf: catalogURL)
            let catalog = try JSONDecoder().decode(BuiltInVoiceSeedCatalogDocument.self, from: data)
            return catalog.voices
        } catch {
            throw BuiltInVoiceSeedCatalogError(
                """
                SpeakSwiftlyServer could not decode the built-in default voice catalog at '\(catalogURL.path)'.
                Likely cause: \(error.localizedDescription)
                """,
            )
        }
    }
}

package struct BuiltInVoiceSeedCatalogError: Error, CustomStringConvertible {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var description: String { message }
}

package struct BuiltInVoiceSeedCatalogDocument: Codable, Equatable {
    package let catalogVersion: Int
    package let voices: [BuiltInVoiceSeed]

    enum CodingKeys: String, CodingKey {
        case catalogVersion = "catalog_version"
        case voices
    }
}

package struct BuiltInVoiceSeed: Codable, Equatable, Identifiable {
    package let seedID: String
    package let seedVersion: String
    package let profileName: String
    package let fallbackProfileName: String
    package let author: BuiltInVoiceSeedAuthor
    package let vibe: SpeakSwiftly.Vibe
    package let voiceDescription: String
    package let sourceText: String
    package let sourceKind: BuiltInVoiceSeedSourceKind
    package let sampleMediaPath: String?

    package var id: String { seedID }

    package func profileSeed(installedProfileName: String) -> SpeakSwiftly.ProfileSeed {
        SpeakSwiftly.ProfileSeed(
            seedID: seedID,
            seedVersion: seedVersion,
            intendedProfileName: profileName,
            fallbackProfileName: installedProfileName == fallbackProfileName ? fallbackProfileName : nil,
            sourcePackage: "SpeakSwiftlyServer",
            sourceVersion: nil,
            sampleMediaPath: sampleMediaPath,
        )
    }

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

package enum BuiltInVoiceSeedAuthor: String, Codable {
    case system
}

package enum BuiltInVoiceSeedSourceKind: String, Codable {
    case generatedDesign = "generated_design"
}
