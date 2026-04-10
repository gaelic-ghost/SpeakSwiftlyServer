import Darwin
import Foundation

// MARK: - Launch Agent Status

let launchAgentGraceIntervalMicroseconds: useconds_t = 100_000
let launchAgentBootstrapRetryCount = 10

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

    func waitUntilNotLoaded(
        timeout: TimeInterval = 5,
        pollIntervalMicroseconds: useconds_t = launchAgentGraceIntervalMicroseconds
    ) throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try !isLoaded() {
                return
            }
            usleep(pollIntervalMicroseconds)
        }

        throw LaunchAgentCommandError(
            """
            \(speakSwiftlyServerToolName) unloaded '\(userDomain)/\(label)', but launchctl still reported the service as loaded after \(timeout) seconds.
            Likely cause: launchd has not finished tearing the old job down yet.
            """
        )
    }
}

// MARK: - Launch Agent Defaults

enum LaunchAgentDefaults {
    static let label = "com.gaelic-ghost.speak-swiftly-server"
    static let launchctlPath = "/bin/launchctl"
    static let userDomain = "gui/\(getuid())"
    static let stagedReleaseDirectoryName = ".release-artifacts"
    static let stagedReleaseCurrentDirectoryName = "current"
    private static let installLayout = ServerInstallLayout.defaultForCurrentUser()
    static let workingDirectory = installLayout.workingDirectoryURL.path
    static let standardOutPath = installLayout.standardOutLogURL.path
    static let standardErrorPath = installLayout.standardErrorLogURL.path
    static let runtimeProfileRootPath = installLayout.runtimeProfileRootURL.path

    static func plistPath(for label: String) -> String {
        ServerInstallLayout.defaultForCurrentUser(launchAgentLabel: label).launchAgentPlistURL.path
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

func shouldRetryLaunchAgentBootstrap(_ result: LaunchctlResult) -> Bool {
    guard result.exitCode != 0 else {
        return false
    }

    let diagnostic = "\(result.standardOutput)\n\(result.standardError)".lowercased()
    return diagnostic.contains("operation already in progress")
        || diagnostic.contains("bootstrap failed: 37")
}
