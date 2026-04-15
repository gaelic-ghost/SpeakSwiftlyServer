import Foundation

// MARK: - ServerRuntimeEntrypointOptions

public struct ServerRuntimeEntrypointOptions: Sendable {
    public let runtimeProfileRootPath: String?

    public init(runtimeProfileRootPath: String? = nil) {
        let trimmedPath = runtimeProfileRootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPath, !trimmedPath.isEmpty {
            self.runtimeProfileRootPath = trimmedPath
        } else {
            self.runtimeProfileRootPath = nil
        }
    }
}

// MARK: - ServerRuntimeEntrypoint

/// Starts the standalone SpeakSwiftly server runtime using the package's default embedded bootstrap path.
public enum ServerRuntimeEntrypoint {
    /// Builds and runs an embedded session, then waits until that session stops.
    public static func run(
        options: ServerRuntimeEntrypointOptions = .init(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) async throws {
        let session = try await EmbeddedServerSession.start(
            environment: effectiveEnvironment(environment: environment, options: options),
            options: .init(
                runtimeProfileRootURL: options.runtimeProfileRootPath.map {
                    URL(fileURLWithPath: $0, isDirectory: true)
                },
            ),
            defaultProfile: .standaloneExecutable,
            bootstrap: EmbeddedServerSession.liveBootstrap,
        )
        try await session.waitUntilStopped()
    }

    private static func effectiveEnvironment(
        environment: [String: String],
        options: ServerRuntimeEntrypointOptions,
    ) -> [String: String] {
        var resolvedEnvironment = environment
        if let runtimeProfileRootPath = options.runtimeProfileRootPath {
            resolvedEnvironment["SPEAKSWIFTLY_PROFILE_ROOT"] = runtimeProfileRootPath
        }
        return resolvedEnvironment
    }
}
