import Foundation

// MARK: - App-Managed Install Layout

/// App-facing path contract for a per-user SpeakSwiftlyServer install.
///
/// The forthcoming macOS app should treat these paths as the owned install surface for the
/// standalone LaunchAgent-backed server instead of guessing at ad hoc filesystem locations.
public struct ServerInstallLayout: Codable, Sendable, Equatable {
    public let launchAgentLabel: String
    public let workingDirectoryURL: URL
    public let applicationSupportDirectoryURL: URL
    public let cacheDirectoryURL: URL
    public let logsDirectoryURL: URL
    public let launchAgentsDirectoryURL: URL
    public let launchAgentPlistURL: URL
    public let serverConfigFileURL: URL
    public let runtimeBaseDirectoryURL: URL
    public let runtimeProfileRootURL: URL
    public let runtimeConfigurationFileURL: URL
    public let standardOutLogURL: URL
    public let standardErrorLogURL: URL

    public init(
        launchAgentLabel: String,
        workingDirectoryURL: URL,
        applicationSupportDirectoryURL: URL,
        cacheDirectoryURL: URL,
        logsDirectoryURL: URL,
        launchAgentsDirectoryURL: URL,
        launchAgentPlistURL: URL,
        serverConfigFileURL: URL,
        runtimeBaseDirectoryURL: URL,
        runtimeProfileRootURL: URL,
        runtimeConfigurationFileURL: URL,
        standardOutLogURL: URL,
        standardErrorLogURL: URL
    ) {
        self.launchAgentLabel = launchAgentLabel
        self.workingDirectoryURL = workingDirectoryURL
        self.applicationSupportDirectoryURL = applicationSupportDirectoryURL
        self.cacheDirectoryURL = cacheDirectoryURL
        self.logsDirectoryURL = logsDirectoryURL
        self.launchAgentsDirectoryURL = launchAgentsDirectoryURL
        self.launchAgentPlistURL = launchAgentPlistURL
        self.serverConfigFileURL = serverConfigFileURL
        self.runtimeBaseDirectoryURL = runtimeBaseDirectoryURL
        self.runtimeProfileRootURL = runtimeProfileRootURL
        self.runtimeConfigurationFileURL = runtimeConfigurationFileURL
        self.standardOutLogURL = standardOutLogURL
        self.standardErrorLogURL = standardErrorLogURL
    }

    public static func defaultForCurrentUser(
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        launchAgentLabel: String = "com.gaelic-ghost.speak-swiftly-server"
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
            runtimeBaseDirectoryURL: runtimeBaseDirectoryURL,
            runtimeProfileRootURL: runtimeProfileRootURL,
            runtimeConfigurationFileURL: runtimeConfigurationFileURL,
            standardOutLogURL: logsDirectoryURL.appendingPathComponent("stdout.log", isDirectory: false),
            standardErrorLogURL: logsDirectoryURL.appendingPathComponent("stderr.log", isDirectory: false)
        )
    }

    func launchAgentEnvironmentVariables(
        configFilePath: String?,
        reloadIntervalSeconds: String?
    ) -> [String: String] {
        var environmentVariables = [String: String]()
        if let configFilePath, !configFilePath.isEmpty {
            environmentVariables["APP_CONFIG_FILE"] = configFilePath
        }
        if let reloadIntervalSeconds, !reloadIntervalSeconds.isEmpty {
            environmentVariables["APP_CONFIG_RELOAD_INTERVAL_SECONDS"] = reloadIntervalSeconds
        }
        environmentVariables["SPEAKSWIFTLY_PROFILE_ROOT"] = runtimeProfileRootURL.path
        return environmentVariables
    }
}

// MARK: - Installed Server Logs

public enum ServerInstalledLogKind: String, Codable, Sendable, Equatable, CaseIterable {
    case stdout
    case stderr
}

public struct ServerInstalledLogFileSnapshot: Codable, Sendable, Equatable {
    public let kind: ServerInstalledLogKind
    public let fileURL: URL
    public let exists: Bool
    public let text: String
    public let lines: [String]
    public let jsonLineTexts: [String]
    public let totalLineCount: Int
    public let truncatedLineCount: Int

    public func decodeJSONLines<T: Decodable & Sendable>(
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> [T] {
        try jsonLineTexts.map { line in
            try decoder.decode(T.self, from: Data(line.utf8))
        }
    }
}

public struct ServerInstalledLogsSnapshot: Codable, Sendable, Equatable {
    public let layout: ServerInstallLayout
    public let stdout: ServerInstalledLogFileSnapshot
    public let stderr: ServerInstalledLogFileSnapshot

    public func file(for kind: ServerInstalledLogKind) -> ServerInstalledLogFileSnapshot {
        switch kind {
        case .stdout:
            stdout
        case .stderr:
            stderr
        }
    }
}

public enum ServerInstalledLogs {
    public static func read(
        layout: ServerInstallLayout = .defaultForCurrentUser(),
        maximumLineCount: Int? = 400
    ) throws -> ServerInstalledLogsSnapshot {
        .init(
            layout: layout,
            stdout: try readFile(at: layout.standardOutLogURL, kind: .stdout, maximumLineCount: maximumLineCount),
            stderr: try readFile(at: layout.standardErrorLogURL, kind: .stderr, maximumLineCount: maximumLineCount)
        )
    }

    private static func readFile(
        at fileURL: URL,
        kind: ServerInstalledLogKind,
        maximumLineCount: Int?
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
                truncatedLineCount: 0
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
            truncatedLineCount: truncatedLineCount
        )
    }
}
