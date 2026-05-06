import Foundation
import SpeakSwiftlyServer

enum DefaultServerConfig {
    static let resourceName = "default-server"
    static let resourceExtension = "yaml"

    static func seedIfMissing(at configURL: URL, fileManager: FileManager = .default) throws -> Bool {
        do {
            return try ServerConfigPersistence(
                configurationURL: configURL,
                fileManager: fileManager,
            )
            .seedIfMissing()
        } catch {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not seed the default LaunchAgent config at '\(configURL.standardizedFileURL.path)'.
                Likely cause: \(error)
                """,
            )
        }
    }
}
