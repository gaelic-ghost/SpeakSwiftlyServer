import Foundation

package struct ServerRuntimeEntrypointOptions {
    package let runtimeProfileRootPath: String?

    package init(runtimeProfileRootPath: String? = nil) {
        let trimmedPath = runtimeProfileRootPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedPath, !trimmedPath.isEmpty {
            self.runtimeProfileRootPath = trimmedPath
        } else {
            self.runtimeProfileRootPath = nil
        }
    }
}

/// Starts the standalone SpeakSwiftly server runtime using the package's default embedded bootstrap path.
package enum ServerRuntimeEntrypoint {
    /// Builds and runs an embedded session, then waits until that session stops.
    package static func run(
        options: ServerRuntimeEntrypointOptions = .init(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) async throws {
        let server = await MainActor.run {
            EmbeddedServer(
                options: .init(
                    runtimeProfileRootURL: options.runtimeProfileRootPath.map {
                        URL(fileURLWithPath: $0, isDirectory: true)
                    },
                ),
            )
        }
        try await server.liftoff(
            environment: effectiveEnvironment(environment: environment, options: options),
            defaultProfile: .standaloneExecutable,
        )
        try await server.waitUntilStopped()
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
