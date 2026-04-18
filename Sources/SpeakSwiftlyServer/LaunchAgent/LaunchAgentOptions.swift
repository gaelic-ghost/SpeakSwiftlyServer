import Foundation

// MARK: - Launch Agent Options

struct LaunchAgentOptions {
    let label: String
    let toolExecutablePath: String
    let plistPath: String
    let configFilePath: String?
    let reloadIntervalSeconds: String?
    let workingDirectory: String
    let profileRootPath: String
    let standardOutPath: String
    let standardErrorPath: String
    let launchctlPath: String
    let userDomain: String

    // MARK: - Initialization

    init(
        label: String = LaunchAgentDefaults.label,
        toolExecutablePath: String,
        plistPath: String? = nil,
        configFilePath: String? = nil,
        reloadIntervalSeconds: String? = nil,
        workingDirectory: String = LaunchAgentDefaults.workingDirectory,
        profileRootPath: String = LaunchAgentDefaults.runtimeProfileRootPath,
        standardOutPath: String = LaunchAgentDefaults.standardOutPath,
        standardErrorPath: String = LaunchAgentDefaults.standardErrorPath,
        launchctlPath: String = LaunchAgentDefaults.launchctlPath,
        userDomain: String = LaunchAgentDefaults.userDomain,
        requireToolExecutableExists: Bool = true,
    ) throws {
        guard !label.isEmpty else {
            throw LaunchAgentCommandError("\(speakSwiftlyServerToolName) launch-agent support requires a non-empty launchd label.")
        }

        let resolvedToolExecutablePath = Self.resolvePath(toolExecutablePath)
        if requireToolExecutableExists {
            guard FileManager.default.fileExists(atPath: resolvedToolExecutablePath) else {
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) could not install a LaunchAgent because the tool executable path '\(resolvedToolExecutablePath)' does not exist.",
                )
            }
            guard FileManager.default.isExecutableFile(atPath: resolvedToolExecutablePath) else {
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) could not install a LaunchAgent because '\(resolvedToolExecutablePath)' is not executable.",
                )
            }
        }

        self.label = label
        self.toolExecutablePath = resolvedToolExecutablePath
        self.plistPath = Self.resolvePath(plistPath ?? LaunchAgentDefaults.plistPath(for: label))
        self.configFilePath = configFilePath.map { Self.resolvePath($0) }
        self.reloadIntervalSeconds = reloadIntervalSeconds
        self.workingDirectory = Self.resolvePath(workingDirectory)
        self.profileRootPath = Self.resolvePath(profileRootPath)
        self.standardOutPath = Self.resolvePath(standardOutPath)
        self.standardErrorPath = Self.resolvePath(standardErrorPath)
        self.launchctlPath = launchctlPath
        self.userDomain = userDomain
    }

    // MARK: - Parsing

    static func parse(
        arguments: [String],
        currentDirectoryPath: String,
        currentExecutablePath: String,
        requireToolExecutableExists: Bool = true,
    ) throws -> LaunchAgentOptions {
        var label = LaunchAgentDefaults.label
        let _ = currentExecutablePath
        var toolExecutablePathOverride: String?
        var plistPath = LaunchAgentDefaults.plistPath(for: label)
        var configFilePath: String?
        var reloadIntervalSeconds: String?
        var workingDirectory = LaunchAgentDefaults.workingDirectory
        var profileRootPath = LaunchAgentDefaults.runtimeProfileRootPath
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
                    toolExecutablePathOverride = try requireValue(after: arguments, index: index, option: arguments[index])
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

                case "--profile-root":
                    profileRootPath = try requireValue(after: arguments, index: index, option: "--profile-root")
                    index += 2

                case "--stdout-path":
                    standardOutPath = try requireValue(after: arguments, index: index, option: "--stdout-path")
                    index += 2

                case "--stderr-path":
                    standardErrorPath = try requireValue(after: arguments, index: index, option: "--stderr-path")
                    index += 2

                default:
                    throw LaunchAgentCommandError(
                        "\(speakSwiftlyServerToolName) did not recognize launch-agent option '\(arguments[index])'. Run `\(speakSwiftlyServerToolName) help` for supported flags.",
                    )
            }
        }

        let toolExecutablePath = try toolExecutablePathOverride ?? resolveDefaultToolExecutablePath(
            currentDirectoryPath: currentDirectoryPath,
            mustExist: requireToolExecutableExists,
        )

        return try .init(
            label: label,
            toolExecutablePath: resolvePath(toolExecutablePath, relativeTo: currentDirectoryPath),
            plistPath: resolvePath(plistPath, relativeTo: currentDirectoryPath),
            configFilePath: configFilePath.map { resolvePath($0, relativeTo: currentDirectoryPath) },
            reloadIntervalSeconds: reloadIntervalSeconds,
            workingDirectory: resolvePath(workingDirectory, relativeTo: currentDirectoryPath),
            profileRootPath: resolvePath(profileRootPath, relativeTo: currentDirectoryPath),
            standardOutPath: resolvePath(standardOutPath, relativeTo: currentDirectoryPath),
            standardErrorPath: resolvePath(standardErrorPath, relativeTo: currentDirectoryPath),
            requireToolExecutableExists: requireToolExecutableExists,
        )
    }

    // MARK: - Helpers

    static func resolveDefaultToolExecutablePath(
        currentDirectoryPath: String,
        mustExist: Bool = true,
    ) throws -> String {
        let repositoryRoot = try resolveRepositoryRoot(startingAt: currentDirectoryPath)
        let stagedReleasePath = LaunchAgentDefaults.stagedReleaseToolExecutablePath(for: repositoryRoot)

        guard mustExist == false || FileManager.default.fileExists(atPath: stagedReleasePath) else {
            throw LaunchAgentCommandError(
                """
                \(speakSwiftlyServerToolName) could not find the staged release artifact at '\(stagedReleasePath)'.
                Likely cause: this checkout has not staged a release build for the live service yet.
                Build and stage the release artifact first, or pass --tool-executable-path explicitly.
                """,
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
               fileManager.fileExists(atPath: toolSourcesURL.path) {
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
            """,
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
}
