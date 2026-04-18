import Foundation

/// App-facing path contract for a per-user SpeakSwiftlyServer install.
///
/// The forthcoming macOS app should treat these paths as the owned install surface for the
/// standalone LaunchAgent-backed server instead of guessing at ad hoc filesystem locations.
public struct ServerInstallLayout: Codable, Sendable, Equatable {
    /// The LaunchAgent label the app-managed install uses for `launchctl` operations.
    public let launchAgentLabel: String
    /// The working directory the standalone process should use when launched as an installed service.
    public let workingDirectoryURL: URL
    /// The application support root that owns config, runtime state, and other durable install files.
    public let applicationSupportDirectoryURL: URL
    /// The cache root the installed service can use for disposable support files.
    public let cacheDirectoryURL: URL
    /// The directory that owns the retained stdout and stderr log files.
    public let logsDirectoryURL: URL
    /// The per-user `LaunchAgents` directory that owns the installed property list.
    public let launchAgentsDirectoryURL: URL
    /// The property list URL for the installed LaunchAgent definition.
    public let launchAgentPlistURL: URL
    /// The durable server config file an app should manage for the standalone server.
    public let serverConfigFileURL: URL
    /// The alias config file path used when the real config path is not LaunchAgent-friendly.
    public let launchAgentConfigAliasURL: URL
    /// The runtime state root used by the installed server process.
    public let runtimeBaseDirectoryURL: URL
    /// The profile storage root exposed to the installed speech runtime.
    public let runtimeProfileRootURL: URL
    /// The persisted runtime configuration file used for next-start state.
    public let runtimeConfigurationFileURL: URL
    /// The retained stdout log file for the installed service.
    public let standardOutLogURL: URL
    /// The retained stderr log file for the installed service.
    public let standardErrorLogURL: URL

    /// Creates a fully resolved install-layout contract for one app-managed server install.
    public init(
        launchAgentLabel: String,
        workingDirectoryURL: URL,
        applicationSupportDirectoryURL: URL,
        cacheDirectoryURL: URL,
        logsDirectoryURL: URL,
        launchAgentsDirectoryURL: URL,
        launchAgentPlistURL: URL,
        serverConfigFileURL: URL,
        launchAgentConfigAliasURL: URL,
        runtimeBaseDirectoryURL: URL,
        runtimeProfileRootURL: URL,
        runtimeConfigurationFileURL: URL,
        standardOutLogURL: URL,
        standardErrorLogURL: URL,
    ) {
        self.launchAgentLabel = launchAgentLabel
        self.workingDirectoryURL = workingDirectoryURL
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.cacheDirectoryURL = cacheDirectoryURL
        self.logsDirectoryURL = logsDirectoryURL
        self.launchAgentsDirectoryURL = launchAgentsDirectoryURL
        self.launchAgentPlistURL = launchAgentPlistURL
        self.serverConfigFileURL = serverConfigFileURL
        self.launchAgentConfigAliasURL = launchAgentConfigAliasURL
        self.runtimeBaseDirectoryURL = runtimeBaseDirectoryURL
        self.runtimeProfileRootURL = runtimeProfileRootURL
        self.runtimeConfigurationFileURL = runtimeConfigurationFileURL
        self.standardOutLogURL = standardOutLogURL
        self.standardErrorLogURL = standardErrorLogURL
    }

    /// Returns the package's default per-user install layout for the current account.
    public static func defaultForCurrentUser(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchAgentLabel: String = "com.gaelic-ghost.speak-swiftly-server",
    ) -> ServerInstallLayout {
        let applicationSupportDirectoryURL = fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakSwiftlyServer", isDirectory: true)
        let cacheDirectoryURL = fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SpeakSwiftlyServer", isDirectory: true)
        let logsDirectoryURL = fileManager
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("SpeakSwiftlyServer", isDirectory: true)
        let launchAgentsDirectoryURL = homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
        let launchAgentPlistURL = launchAgentsDirectoryURL
            .appendingPathComponent("\(launchAgentLabel).plist", isDirectory: false)
        let runtimeBaseDirectoryURL = applicationSupportDirectoryURL
            .appendingPathComponent("runtime", isDirectory: true)
        let runtimeProfileRootURL = runtimeBaseDirectoryURL
            .appendingPathComponent("profiles", isDirectory: true)
        let runtimeConfigurationFileURL = runtimeBaseDirectoryURL
            .appendingPathComponent("configuration.json", isDirectory: false)

        return .init(
            launchAgentLabel: launchAgentLabel,
            workingDirectoryURL: homeDirectoryURL,
            applicationSupportDirectoryURL: applicationSupportDirectoryURL,
            cacheDirectoryURL: cacheDirectoryURL,
            logsDirectoryURL: logsDirectoryURL,
            launchAgentsDirectoryURL: launchAgentsDirectoryURL,
            launchAgentPlistURL: launchAgentPlistURL,
            serverConfigFileURL: applicationSupportDirectoryURL.appendingPathComponent("server.yaml", isDirectory: false),
            launchAgentConfigAliasURL: cacheDirectoryURL.appendingPathComponent("launch-agent-server.yaml", isDirectory: false),
            runtimeBaseDirectoryURL: runtimeBaseDirectoryURL,
            runtimeProfileRootURL: runtimeProfileRootURL,
            runtimeConfigurationFileURL: runtimeConfigurationFileURL,
            standardOutLogURL: logsDirectoryURL.appendingPathComponent("stdout.log", isDirectory: false),
            standardErrorLogURL: logsDirectoryURL.appendingPathComponent("stderr.log", isDirectory: false),
        )
    }

    func launchAgentEnvironmentVariables(
        configFilePath: String?,
        reloadIntervalSeconds: String?,
    ) -> [String: String] {
        var environmentVariables = [String: String]()
        if let configFilePath, !configFilePath.isEmpty {
            environmentVariables["APP_CONFIG_FILE"] = launchAgentConfigPath(for: configFilePath)
        }
        if let reloadIntervalSeconds, !reloadIntervalSeconds.isEmpty {
            environmentVariables["APP_CONFIG_RELOAD_INTERVAL_SECONDS"] = reloadIntervalSeconds
        }
        environmentVariables["SPEAKSWIFTLY_PROFILE_ROOT"] = runtimeProfileRootURL.path
        return environmentVariables
    }

    func launchAgentConfigPath(for configFilePath: String) -> String {
        let standardizedPath = URL(fileURLWithPath: configFilePath).standardizedFileURL.path
        if standardizedPath.contains(" ") {
            return launchAgentConfigAliasURL.path
        }
        return standardizedPath
    }
}

/// Identifies which retained log file from an installed server snapshot a caller wants to inspect.
public enum ServerInstalledLogKind: String, Codable, Sendable, Equatable, CaseIterable {
    case stdout
    case stderr
}

/// Captures one retained stdout or stderr file from an installed standalone server.
public struct ServerInstalledLogFileSnapshot: Codable, Sendable, Equatable {
    public let kind: ServerInstalledLogKind
    public let fileURL: URL
    public let exists: Bool
    public let text: String
    public let lines: [String]
    public let jsonLineTexts: [String]
    public let totalLineCount: Int
    public let truncatedLineCount: Int

    /// Decodes the retained JSON line texts into strongly typed values.
    public func decodeJSONLines<T: Decodable & Sendable>(
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder(),
    ) throws -> [T] {
        try jsonLineTexts.map { line in
            try decoder.decode(T.self, from: Data(line.utf8))
        }
    }
}

/// Bundles the retained stdout and stderr snapshots for one installed server layout.
public struct ServerInstalledLogsSnapshot: Codable, Sendable, Equatable {
    public let layout: ServerInstallLayout
    public let stdout: ServerInstalledLogFileSnapshot
    public let stderr: ServerInstalledLogFileSnapshot

    /// Returns the retained log snapshot for the requested stream.
    public func file(for kind: ServerInstalledLogKind) -> ServerInstalledLogFileSnapshot {
        switch kind {
            case .stdout:
                stdout
            case .stderr:
                stderr
        }
    }
}

/// Reads retained stdout and stderr files from an app-managed standalone server install.
public enum ServerInstalledLogs {
    /// Loads retained stdout and stderr content for the supplied install layout.
    public static func read(
        layout: ServerInstallLayout = .defaultForCurrentUser(),
        maximumLineCount: Int? = 400,
    ) throws -> ServerInstalledLogsSnapshot {
        try .init(
            layout: layout,
            stdout: readFile(at: layout.standardOutLogURL, kind: .stdout, maximumLineCount: maximumLineCount),
            stderr: readFile(at: layout.standardErrorLogURL, kind: .stderr, maximumLineCount: maximumLineCount),
        )
    }

    private static func readFile(
        at fileURL: URL,
        kind: ServerInstalledLogKind,
        maximumLineCount: Int?,
    ) throws -> ServerInstalledLogFileSnapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .init(
                kind: kind,
                fileURL: fileURL,
                exists: false,
                text: "",
                lines: [],
                jsonLineTexts: [],
                totalLineCount: 0,
                truncatedLineCount: 0,
            )
        }

        let text = try String(contentsOf: fileURL, encoding: .utf8)
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var allLines = normalizedText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if allLines.last == "" {
            allLines.removeLast()
        }
        let retainedLines: [String]
        let truncatedLineCount: Int
        if let maximumLineCount, maximumLineCount >= 0, allLines.count > maximumLineCount {
            retainedLines = Array(allLines.suffix(maximumLineCount))
            truncatedLineCount = allLines.count - maximumLineCount
        } else {
            retainedLines = allLines
            truncatedLineCount = 0
        }

        let retainedText = retainedLines.joined(separator: "\n")
        let jsonLineTexts = retainedLines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
        }

        return .init(
            kind: kind,
            fileURL: fileURL,
            exists: true,
            text: retainedText,
            lines: retainedLines,
            jsonLineTexts: jsonLineTexts,
            totalLineCount: allLines.count,
            truncatedLineCount: truncatedLineCount,
        )
    }
}
