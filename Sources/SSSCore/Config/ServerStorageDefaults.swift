import Foundation

package enum ServerStorageDefaults {
    static func defaultForCurrentUser(
        fileManager: FileManager = .default,
    ) -> (profileRootURL: URL, configurationURL: URL) {
        let applicationSupportDirectoryURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakSwiftlyServer", isDirectory: true)
        let runtimeBaseDirectoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("runtime", isDirectory: true)
        let runtimeProfileRootURL = runtimeBaseDirectoryURL
            .appendingPathComponent("profiles", isDirectory: true)
        let runtimeConfigurationFileURL = applicationSupportDirectoryURL
            .appendingPathComponent("server.yaml", isDirectory: false)

        return (runtimeProfileRootURL, runtimeConfigurationFileURL)
    }
}
