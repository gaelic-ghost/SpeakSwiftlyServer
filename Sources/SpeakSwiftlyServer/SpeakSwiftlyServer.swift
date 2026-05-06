import Foundation

public struct ServerRuntimeEntrypointOptions: Sendable {
    public let configurationPath: String?
    public let runtimeProfileRootPath: String?
    public let defaultProfile: ServerConfigDefaultProfile?

    public init(
        configurationPath: String? = nil,
        runtimeProfileRootPath: String? = nil,
        defaultProfile: ServerConfigDefaultProfile? = nil,
    ) {
        let trimmedConfigPath = configurationPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedConfigPath, !trimmedConfigPath.isEmpty {
            self.configurationPath = trimmedConfigPath
        } else {
            self.configurationPath = nil
        }

        let trimmedPath = runtimeProfileRootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPath, !trimmedPath.isEmpty {
            self.runtimeProfileRootPath = trimmedPath
        } else {
            self.runtimeProfileRootPath = nil
        }
        self.defaultProfile = defaultProfile
    }
}

/// Starts the standalone SpeakSwiftly server runtime using the package's default embedded bootstrap path.
public enum ServerRuntimeEntrypoint {
    /// Builds and runs an embedded session, then waits until that session stops.
    public static func run(
        options: ServerRuntimeEntrypointOptions = .init(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) async throws {
        let defaultPersistence = ServerConfigPersistence.defaultForCurrentUser()
        let configurationURL = options.configurationPath.map {
            URL(fileURLWithPath: $0, isDirectory: false)
        } ?? defaultPersistence.configurationURL
        let profileRootURL = options.runtimeProfileRootPath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? defaultPersistence.profileRootURL
        let server = await MainActor.run {
            EmbeddedServer(
                options: .init(
                    runtimeProfileRootURL: profileRootURL,
                    configurationURL: configurationURL,
                ),
            )
        }
        try await server.liftoff(
            environment: environment,
            defaultProfile: options.defaultProfile ?? .standaloneExecutable,
        )
        try await server.waitUntilStopped()
    }
}
