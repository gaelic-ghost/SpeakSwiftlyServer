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

    // MARK: - Parsing

    static func parse(arguments: [String], currentDirectoryPath: String, currentExecutablePath: String) throws -> LaunchAgentOptions {
        var label = LaunchAgentDefaults.label
        let _ = currentExecutablePath
        var toolExecutablePath = try resolveDefaultToolExecutablePath(currentDirectoryPath: currentDirectoryPath)
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
            profileRootPath: resolvePath(profileRootPath, relativeTo: currentDirectoryPath),
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
        profileRootPath: String = LaunchAgentDefaults.runtimeProfileRootPath,
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
        self.profileRootPath = Self.resolvePath(profileRootPath)
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

        let layout = ServerInstallLayout.defaultForCurrentUser(launchAgentLabel: label)
        let environmentVariables = layout.launchAgentEnvironmentVariables(
            configFilePath: configFilePath,
            reloadIntervalSeconds: reloadIntervalSeconds
        ).merging(["SPEAKSWIFTLY_PROFILE_ROOT": profileRootPath]) { _, rhs in rhs }
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
        try FileManager.default.createDirectory(atPath: profileRootPath, withIntermediateDirectories: true)
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
