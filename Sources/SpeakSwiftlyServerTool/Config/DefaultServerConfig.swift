import Foundation

enum DefaultServerConfig {
    static let resourceName = "default-server"
    static let resourceExtension = "yaml"

    static func seedIfMissing(at configURL: URL, fileManager: FileManager = .default) throws -> Bool {
        let destinationURL = configURL.standardizedFileURL
        guard fileManager.fileExists(atPath: destinationURL.path) == false else {
            return false
        }
        guard let defaultConfigURL = Bundle.module.url(
            forResource: resourceName,
            withExtension: resourceExtension,
        ) else {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not seed the default LaunchAgent config because the bundled resource '\(resourceName).\(resourceExtension)' is missing.
                Likely cause: the package resources were not included in the built SpeakSwiftlyServer module.
                """,
            )
        }

        do {
            try fileManager.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try fileManager.copyItem(at: defaultConfigURL, to: destinationURL)
            return true
        } catch {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not seed the default LaunchAgent config at '\(destinationURL.path)'.
                Likely cause: \(error.localizedDescription)
                """,
            )
        }
    }
}
