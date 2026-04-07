import Darwin
import Foundation

private let speakSwiftlyServerToolName = "SpeakSwiftlyServerTool"

// MARK: - CLI Command

public enum SpeakSwiftlyServerToolCommand {
    case serve
    case launchAgent(LaunchAgentCommand)

    // MARK: - Parsing

    public static func parse(
        arguments: [String],
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentExecutablePath: String = CommandLine.arguments[0]
    ) throws -> SpeakSwiftlyServerToolCommand {
        guard let first = arguments.first else {
            return .serve
        }

        switch first {
        case "serve":
            return .serve

        case "launch-agent":
            return .launchAgent(
                try LaunchAgentCommand.parse(
                    arguments: Array(arguments.dropFirst()),
                    currentDirectoryPath: currentDirectoryPath,
                    currentExecutablePath: currentExecutablePath
                )
            )

        case "-h", "--help", "help":
            throw SpeakSwiftlyServerToolCommandError(helpText)

        default:
            throw SpeakSwiftlyServerToolCommandError(
                "\(speakSwiftlyServerToolName) did not recognize command '\(first)'. Supported commands are `serve` and `launch-agent`."
            )
        }
    }

    // MARK: - Running

    public func run() async throws {
        switch self {
        case .serve:
            try await ServerRuntimeEntrypoint.run()

        case .launchAgent(let command):
            try command.run()
        }
    }

    // MARK: - Help

    static let helpText = """
    Usage:
      \(speakSwiftlyServerToolName) serve
      \(speakSwiftlyServerToolName) launch-agent print-plist [options]
      \(speakSwiftlyServerToolName) launch-agent install [options]
      \(speakSwiftlyServerToolName) launch-agent uninstall [options]
      \(speakSwiftlyServerToolName) launch-agent status [options]

    Launch-agent options:
      --label <label>
      --tool-executable-path <path>
      --plist-path <path>
      --config-file <path>
      --reload-interval-seconds <seconds>
      --working-directory <path>
      --stdout-path <path>
      --stderr-path <path>

      Without arguments, \(speakSwiftlyServerToolName) defaults to `serve`.
    """
}

public struct SpeakSwiftlyServerToolCommandError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Launch Agent Command

public struct LaunchAgentCommand {
    enum Action {
        case printPlist(LaunchAgentOptions)
        case install(LaunchAgentOptions)
        case uninstall(LaunchAgentStatusOptions)
        case status(LaunchAgentStatusOptions)
    }

    let action: Action

    // MARK: - Parsing

    static func parse(arguments: [String], currentDirectoryPath: String, currentExecutablePath: String) throws -> LaunchAgentCommand {
        guard let subcommand = arguments.first else {
            throw LaunchAgentCommandError(
                "The `launch-agent` command requires a subcommand. Supported subcommands are `print-plist`, `install`, `uninstall`, and `status`."
            )
        }

        switch subcommand {
        case "print-plist":
            return .init(action: .printPlist(try LaunchAgentOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath, currentExecutablePath: currentExecutablePath)))

        case "install":
            return .init(action: .install(try LaunchAgentOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath, currentExecutablePath: currentExecutablePath)))

        case "uninstall":
            return .init(action: .uninstall(try LaunchAgentStatusOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath)))

        case "status":
            return .init(action: .status(try LaunchAgentStatusOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath)))

        case "-h", "--help", "help":
            throw LaunchAgentCommandError(SpeakSwiftlyServerToolCommand.helpText)

        default:
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) did not recognize launch-agent subcommand '\(subcommand)'. Supported subcommands are `print-plist`, `install`, `uninstall`, and `status`."
            )
        }
    }

    // MARK: - Running

    func run() throws {
        switch action {
        case .printPlist(let options):
            let data = try options.propertyListData()
            guard let xml = String(data: data, encoding: .utf8) else {
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) rendered a LaunchAgent property list, but it could not be decoded back into UTF-8 text for printing."
                )
            }
            print(xml, terminator: "")

        case .install(let options):
            try options.install()

        case .uninstall(let options):
            try options.uninstall()

        case .status(let options):
            print(try options.statusSummary())
        }
    }
}

public struct LaunchAgentCommandError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
}

// MARK: - Launch Agent Options

struct LaunchAgentOptions {
    let label: String
    let toolExecutablePath: String
    let plistPath: String
    let configFilePath: String?
    let reloadIntervalSeconds: String?
    let workingDirectory: String
    let standardOutPath: String
    let standardErrorPath: String
    let launchctlPath: String
    let userDomain: String

    // MARK: - Parsing

    static func parse(arguments: [String], currentDirectoryPath: String, currentExecutablePath: String) throws -> LaunchAgentOptions {
        var label = LaunchAgentDefaults.label
        let _ = currentExecutablePath
        var toolExecutablePath = try resolveDefaultToolExecutablePath(currentDirectoryPath: currentDirectoryPath)
        var plistPath = LaunchAgentDefaults.plistPath(for: label)
        var configFilePath: String?
        var reloadIntervalSeconds: String?
        var workingDirectory = LaunchAgentDefaults.workingDirectory
        var standardOutPath = LaunchAgentDefaults.standardOutPath
        var standardErrorPath = LaunchAgentDefaults.standardErrorPath
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--label":
                label = try requireValue(after: arguments, index: index, option: "--label")
                plistPath = LaunchAgentDefaults.plistPath(for: label)
                index += 2

            case "--tool-executable-path", "--executable-path":
                toolExecutablePath = try requireValue(after: arguments, index: index, option: arguments[index])
                index += 2

            case "--plist-path":
                plistPath = try requireValue(after: arguments, index: index, option: "--plist-path")
                index += 2

            case "--config-file":
                configFilePath = try requireValue(after: arguments, index: index, option: "--config-file")
                index += 2

            case "--reload-interval-seconds":
                reloadIntervalSeconds = try requireValue(after: arguments, index: index, option: "--reload-interval-seconds")
                index += 2

            case "--working-directory":
                workingDirectory = try requireValue(after: arguments, index: index, option: "--working-directory")
                index += 2

            case "--stdout-path":
                standardOutPath = try requireValue(after: arguments, index: index, option: "--stdout-path")
                index += 2

            case "--stderr-path":
                standardErrorPath = try requireValue(after: arguments, index: index, option: "--stderr-path")
                index += 2

            default:
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) did not recognize launch-agent option '\(arguments[index])'. Run `\(speakSwiftlyServerToolName) help` for supported flags."
                )
            }
        }

        return try .init(
            label: label,
            toolExecutablePath: resolvePath(toolExecutablePath, relativeTo: currentDirectoryPath),
            plistPath: resolvePath(plistPath, relativeTo: currentDirectoryPath),
            configFilePath: configFilePath.map { resolvePath($0, relativeTo: currentDirectoryPath) },
            reloadIntervalSeconds: reloadIntervalSeconds,
            workingDirectory: resolvePath(workingDirectory, relativeTo: currentDirectoryPath),
            standardOutPath: resolvePath(standardOutPath, relativeTo: currentDirectoryPath),
            standardErrorPath: resolvePath(standardErrorPath, relativeTo: currentDirectoryPath)
        )
    }

    // MARK: - Initialization

    init(
        label: String = LaunchAgentDefaults.label,
        toolExecutablePath: String,
        plistPath: String? = nil,
        configFilePath: String? = nil,
        reloadIntervalSeconds: String? = nil,
        workingDirectory: String = LaunchAgentDefaults.workingDirectory,
        standardOutPath: String = LaunchAgentDefaults.standardOutPath,
        standardErrorPath: String = LaunchAgentDefaults.standardErrorPath,
        launchctlPath: String = LaunchAgentDefaults.launchctlPath,
        userDomain: String = LaunchAgentDefaults.userDomain
    ) throws {
        guard !label.isEmpty else {
            throw LaunchAgentCommandError("\(speakSwiftlyServerToolName) launch-agent support requires a non-empty launchd label.")
        }

        let resolvedToolExecutablePath = Self.resolvePath(toolExecutablePath)
        guard FileManager.default.fileExists(atPath: resolvedToolExecutablePath) else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not install a LaunchAgent because the tool executable path '\(resolvedToolExecutablePath)' does not exist."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: resolvedToolExecutablePath) else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not install a LaunchAgent because '\(resolvedToolExecutablePath)' is not executable."
            )
        }

        self.label = label
        self.toolExecutablePath = resolvedToolExecutablePath
        self.plistPath = Self.resolvePath(plistPath ?? LaunchAgentDefaults.plistPath(for: label))
        self.configFilePath = configFilePath.map { Self.resolvePath($0) }
        self.reloadIntervalSeconds = reloadIntervalSeconds
        self.workingDirectory = Self.resolvePath(workingDirectory)
        self.standardOutPath = Self.resolvePath(standardOutPath)
        self.standardErrorPath = Self.resolvePath(standardErrorPath)
        self.launchctlPath = launchctlPath
        self.userDomain = userDomain
    }

    // MARK: - Property List

    func propertyList() -> [String: Any] {
        var propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [toolExecutablePath, "serve"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "WorkingDirectory": workingDirectory,
            "StandardOutPath": standardOutPath,
            "StandardErrorPath": standardErrorPath,
        ]

        var environmentVariables = [String: String]()
        if let configFilePath, !configFilePath.isEmpty {
            environmentVariables["APP_CONFIG_FILE"] = configFilePath
        }
        if let reloadIntervalSeconds, !reloadIntervalSeconds.isEmpty {
            environmentVariables["APP_CONFIG_RELOAD_INTERVAL_SECONDS"] = reloadIntervalSeconds
        }
        if !environmentVariables.isEmpty {
            propertyList["EnvironmentVariables"] = environmentVariables
        }

        return propertyList
    }

    func propertyListData() throws -> Data {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: propertyList(),
                format: .xml,
                options: 0
            )
        } catch {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not encode the LaunchAgent property list for label '\(label)'. Likely cause: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Install

    func install() throws {
        try ensureParentDirectory(for: plistPath)
        try ensureParentDirectory(for: standardOutPath)
        try ensureParentDirectory(for: standardErrorPath)

        try propertyListData().write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistPath)

        let status = LaunchAgentStatusOptions(
            label: label,
            plistPath: plistPath,
            launchctlPath: launchctlPath,
            userDomain: userDomain
        )
        if try status.isLoaded() {
            try status.bootoutLoadedService()
        }

        _ = try runLaunchctl(
            arguments: ["bootstrap", userDomain, plistPath],
            launchctlPath: launchctlPath
        )
        print("Installed LaunchAgent '\(label)' at '\(plistPath)' and bootstrapped it into '\(userDomain)'.")
    }

    // MARK: - Helpers

    static func resolveDefaultToolExecutablePath(currentDirectoryPath: String) throws -> String {
        let repositoryRoot = try resolveRepositoryRoot(startingAt: currentDirectoryPath)
        let stagedReleasePath = LaunchAgentDefaults.stagedReleaseToolExecutablePath(for: repositoryRoot)

        guard FileManager.default.fileExists(atPath: stagedReleasePath) else {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not find the staged release artifact at '\(stagedReleasePath)'.
                Likely cause: this checkout has not staged a release build for the live service yet.
                Build and stage the release artifact first, or pass --tool-executable-path explicitly.
                """
            )
        }

        return stagedReleasePath
    }

    static func resolveRepositoryRoot(startingAt currentDirectoryPath: String) throws -> String {
        let fileManager = FileManager.default
        var candidateURL = URL(fileURLWithPath: resolvePath(currentDirectoryPath), isDirectory: true)

        while true {
            let packageURL = candidateURL.appendingPathComponent("Package.swift")
            let toolSourcesURL = candidateURL.appendingPathComponent("Sources/SpeakSwiftlyServerTool", isDirectory: true)
            if fileManager.fileExists(atPath: packageURL.path),
               fileManager.fileExists(atPath: toolSourcesURL.path)
            {
                return candidateURL.path
            }

            let parentURL = candidateURL.deletingLastPathComponent()
            if parentURL.path == candidateURL.path {
                break
            }
            candidateURL = parentURL
        }

        throw LaunchAgentCommandError(
            """
            \(speakSwiftlyServerToolName) could not find the SpeakSwiftlyServer repository root from '\(currentDirectoryPath)'.
            Likely cause: run the launch-agent command from this repository or pass --tool-executable-path explicitly.
            """
        )
    }

    static func resolvePath(_ rawPath: String, relativeTo basePath: String = FileManager.default.currentDirectoryPath) -> String {
        let url = URL(fileURLWithPath: rawPath, relativeTo: URL(fileURLWithPath: basePath, isDirectory: true))
        return url.standardizedFileURL.path
    }

    static func requireValue(after arguments: [String], index: Int, option: String) throws -> String {
        guard arguments.indices.contains(index + 1) else {
            throw LaunchAgentCommandError("\(speakSwiftlyServerToolName) expected a value after '\(option)'.")
        }
        return arguments[index + 1]
    }

    private func ensureParentDirectory(for path: String) throws {
        let directoryURL = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) could not create the directory '\(directoryURL.path)' needed for LaunchAgent support. Likely cause: \(error.localizedDescription)"
            )
        }
    }
}

struct LaunchAgentStatusOptions {
    let label: String
    let plistPath: String
    let launchctlPath: String
    let userDomain: String

    // MARK: - Parsing

    static func parse(arguments: [String], currentDirectoryPath: String) throws -> LaunchAgentStatusOptions {
        var label = LaunchAgentDefaults.label
        var plistPath = LaunchAgentDefaults.plistPath(for: label)
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--label":
                label = try LaunchAgentOptions.requireValue(after: arguments, index: index, option: "--label")
                plistPath = LaunchAgentDefaults.plistPath(for: label)
                index += 2

            case "--plist-path":
                plistPath = try LaunchAgentOptions.requireValue(after: arguments, index: index, option: "--plist-path")
                index += 2

            default:
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) did not recognize launch-agent option '\(arguments[index])'. The `status` and `uninstall` commands support `--label` and `--plist-path`."
                )
            }
        }

        return .init(
            label: label,
            plistPath: LaunchAgentOptions.resolvePath(plistPath, relativeTo: currentDirectoryPath),
            launchctlPath: LaunchAgentDefaults.launchctlPath,
            userDomain: LaunchAgentDefaults.userDomain
        )
    }

    // MARK: - Status

    func statusSummary() throws -> String {
        let plistExists = FileManager.default.fileExists(atPath: plistPath)
        let loaded = try isLoaded()
        return """
        label: \(label)
        plist_path: \(plistPath)
        plist_exists: \(plistExists ? "yes" : "no")
        loaded: \(loaded ? "yes" : "no")
        user_domain: \(userDomain)
        """
    }

    func isLoaded() throws -> Bool {
        let result = try runLaunchctl(
            arguments: ["print", "\(userDomain)/\(label)"],
            allowNonZeroExit: true,
            launchctlPath: launchctlPath
        )
        return result.exitCode == 0
    }

    func uninstall() throws {
        if try isLoaded() {
            try bootoutLoadedService()
        }

        if FileManager.default.fileExists(atPath: plistPath) {
            do {
                try FileManager.default.removeItem(atPath: plistPath)
            } catch {
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) could not remove LaunchAgent plist '\(plistPath)'. Likely cause: \(error.localizedDescription)"
                )
            }
            print("Removed LaunchAgent plist '\(plistPath)' for label '\(label)'.")
        } else {
            print("LaunchAgent plist '\(plistPath)' was already absent for label '\(label)'.")
        }
    }

    func bootoutLoadedService() throws {
        let result = try runLaunchctl(
            arguments: ["bootout", "\(userDomain)/\(label)"],
            allowNonZeroExit: true,
            launchctlPath: launchctlPath
        )
        guard result.exitCode == 0 else {
            throw LaunchAgentCommandError(
                "\(speakSwiftlyServerToolName) asked launchctl to unload '\(userDomain)/\(label)', but launchctl exited with status \(result.exitCode). stderr: \(result.standardError)"
            )
        }
    }
}

// MARK: - Launch Agent Defaults

enum LaunchAgentDefaults {
    static let label = "com.gaelic-ghost.speak-swiftly-server"
    static let launchctlPath = "/bin/launchctl"
    static let userDomain = "gui/\(getuid())"
    static let stagedReleaseDirectoryName = ".release-artifacts"
    static let stagedReleaseCurrentDirectoryName = "current"
    static let workingDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    static let standardOutPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpeakSwiftlyServer/stdout.log")
        .path
    static let standardErrorPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/SpeakSwiftlyServer/stderr.log")
        .path

    static func plistPath(for label: String) -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
            .path
    }

    static func stagedReleaseToolExecutablePath(for repositoryRoot: String) -> String {
        URL(fileURLWithPath: repositoryRoot, isDirectory: true)
            .appendingPathComponent(stagedReleaseDirectoryName, isDirectory: true)
            .appendingPathComponent(stagedReleaseCurrentDirectoryName, isDirectory: true)
            .appendingPathComponent(speakSwiftlyServerToolName)
            .path
    }
}

// MARK: - Launchctl

struct LaunchctlResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

@discardableResult
func runLaunchctl(
    arguments: [String],
    allowNonZeroExit: Bool = false,
    launchctlPath: String = LaunchAgentDefaults.launchctlPath
) throws -> LaunchctlResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: launchctlPath)
    process.arguments = arguments

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw LaunchAgentCommandError(
            "\(speakSwiftlyServerToolName) could not run launchctl at '\(launchctlPath)'. Likely cause: \(error.localizedDescription)"
        )
    }

    let output = String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let error = String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    let result = LaunchctlResult(
        exitCode: process.terminationStatus,
        standardOutput: output.trimmingCharacters(in: .whitespacesAndNewlines),
        standardError: error.trimmingCharacters(in: .whitespacesAndNewlines)
    )

    if !allowNonZeroExit, result.exitCode != 0 {
        throw LaunchAgentCommandError(
            "\(speakSwiftlyServerToolName) asked launchctl to run `\(arguments.joined(separator: " "))`, but launchctl exited with status \(result.exitCode). stderr: \(result.standardError)"
        )
    }

    return result
}
