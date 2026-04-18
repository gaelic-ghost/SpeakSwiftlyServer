import Foundation

let speakSwiftlyServerToolName = "SpeakSwiftlyServerTool"

// MARK: - ServeOptions

package struct ServeOptions {
    let runtimeProfileRootPath: String?

    static func parse(arguments: [String], currentDirectoryPath: String) throws -> ServeOptions {
        var runtimeProfileRootPath: String?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
                case "--profile-root":
                    runtimeProfileRootPath = try LaunchAgentOptions.requireValue(
                        after: arguments,
                        index: index,
                        option: "--profile-root",
                    )
                    index += 2

                default:
                    throw SpeakSwiftlyServerToolCommandError(
                        "\(speakSwiftlyServerToolName) did not recognize serve option '\(arguments[index])'. Run `\(speakSwiftlyServerToolName) help` for supported flags.",
                    )
            }
        }

        return .init(
            runtimeProfileRootPath: runtimeProfileRootPath.map {
                LaunchAgentOptions.resolvePath($0, relativeTo: currentDirectoryPath)
            },
        )
    }
}

// MARK: - SpeakSwiftlyServerToolCommand

/// Top-level parsed command for the `SpeakSwiftlyServerTool` executable.
package enum SpeakSwiftlyServerToolCommand {
    case serve(ServeOptions)
    case healthcheck(HealthcheckOptions)
    case launchAgent(LaunchAgentCommand)

    // MARK: - Help

    static let helpText = """
    Usage:
      \(speakSwiftlyServerToolName) serve
      \(speakSwiftlyServerToolName) healthcheck [options]
      \(speakSwiftlyServerToolName) launch-agent print-plist [options]
      \(speakSwiftlyServerToolName) launch-agent install [options]
      \(speakSwiftlyServerToolName) launch-agent promote-live [options]
      \(speakSwiftlyServerToolName) launch-agent uninstall [options]
      \(speakSwiftlyServerToolName) launch-agent status [options]

    Launch-agent options:
      --label <label>
      --tool-executable-path <path>
      --plist-path <path>
      --config-file <path>
      --reload-interval-seconds <seconds>
      --working-directory <path>
      --profile-root <path>
      --stdout-path <path>
      --stderr-path <path>

    Serve options:
      --profile-root <path>

    Healthcheck options:
      --base-url <url>
      --mcp-path <path>
      --timeout-seconds <seconds>

      Without arguments, \(speakSwiftlyServerToolName) defaults to `serve`.
    """

    // MARK: - Parsing

    /// Parses command-line arguments into the tool's top-level command model.
    package static func parse(
        arguments: [String],
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        currentExecutablePath: String = CommandLine.arguments[0],
    ) throws -> SpeakSwiftlyServerToolCommand {
        guard let first = arguments.first else {
            return .serve(.init(runtimeProfileRootPath: nil))
        }

        switch first {
            case "serve":
                return try .serve(
                    ServeOptions.parse(
                        arguments: Array(arguments.dropFirst()),
                        currentDirectoryPath: currentDirectoryPath,
                    ),
                )

            case "launch-agent":
                return try .launchAgent(
                    LaunchAgentCommand.parse(
                        arguments: Array(arguments.dropFirst()),
                        currentDirectoryPath: currentDirectoryPath,
                        currentExecutablePath: currentExecutablePath,
                    ),
                )

            case "healthcheck":
                return try .healthcheck(
                    HealthcheckOptions.parse(arguments: Array(arguments.dropFirst())),
                )

            case "-h", "--help", "help":
                throw SpeakSwiftlyServerToolCommandError(helpText)

            default:
                if first.hasPrefix("-") {
                    return try .serve(
                        ServeOptions.parse(
                            arguments: arguments,
                            currentDirectoryPath: currentDirectoryPath,
                        ),
                    )
                }
                throw SpeakSwiftlyServerToolCommandError(
                    "\(speakSwiftlyServerToolName) did not recognize command '\(first)'. Supported commands are `serve`, `healthcheck`, and `launch-agent`.",
                )
        }
    }

    // MARK: - Running

    /// Runs the parsed command against the standalone runtime or LaunchAgent workflow.
    package func run() async throws {
        switch self {
            case let .serve(options):
                try await ServerRuntimeEntrypoint.run(
                    options: .init(runtimeProfileRootPath: options.runtimeProfileRootPath),
                )

            case let .healthcheck(options):
                try await SpeakSwiftlyServerHealthcheck(options: options).run()

            case let .launchAgent(command):
                try command.run()
        }
    }
}

// MARK: - SpeakSwiftlyServerToolCommandError

/// Human-friendly parse or usage error for the top-level executable command surface.
package struct SpeakSwiftlyServerToolCommandError: Error, CustomStringConvertible {
    package let message: String

    package init(_ message: String) {
        self.message = message
    }

    package var description: String { message }
}

// MARK: - LaunchAgentCommand

/// Parsed subcommand for LaunchAgent install, uninstall, status, and property-list rendering.
package struct LaunchAgentCommand {
    enum Action {
        case printPlist(LaunchAgentOptions)
        case install(LaunchAgentOptions)
        case promoteLive(LaunchAgentPromoteOptions)
        case uninstall(LaunchAgentStatusOptions)
        case status(LaunchAgentStatusOptions)
    }

    let action: Action

    // MARK: - Parsing

    /// Parses the `launch-agent` subcommand surface.
    static func parse(arguments: [String], currentDirectoryPath: String, currentExecutablePath: String) throws -> LaunchAgentCommand {
        guard let subcommand = arguments.first else {
            throw LaunchAgentCommandError(
                "The `launch-agent` command requires a subcommand. Supported subcommands are `print-plist`, `install`, `promote-live`, `uninstall`, and `status`.",
            )
        }

        switch subcommand {
            case "print-plist":
                return try .init(action: .printPlist(LaunchAgentOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath, currentExecutablePath: currentExecutablePath)))

            case "install":
                return try .init(action: .install(LaunchAgentOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath, currentExecutablePath: currentExecutablePath)))

            case "promote-live":
                return try .init(action: .promoteLive(LaunchAgentPromoteOptions.parse(
                    arguments: Array(arguments.dropFirst()),
                    currentDirectoryPath: currentDirectoryPath,
                    currentExecutablePath: currentExecutablePath,
                )))

            case "uninstall":
                return try .init(action: .uninstall(LaunchAgentStatusOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath)))

            case "status":
                return try .init(action: .status(LaunchAgentStatusOptions.parse(arguments: Array(arguments.dropFirst()), currentDirectoryPath: currentDirectoryPath)))

            case "-h", "--help", "help":
                throw LaunchAgentCommandError(SpeakSwiftlyServerToolCommand.helpText)

            default:
                throw LaunchAgentCommandError(
                    "\(speakSwiftlyServerToolName) did not recognize launch-agent subcommand '\(subcommand)'. Supported subcommands are `print-plist`, `install`, `promote-live`, `uninstall`, and `status`.",
                )
        }
    }

    // MARK: - Running

    /// Executes the requested LaunchAgent management action.
    func run() throws {
        switch action {
            case let .printPlist(options):
                let data = try options.propertyListData()
                guard let xml = String(data: data, encoding: .utf8) else {
                    throw LaunchAgentCommandError(
                        "\(speakSwiftlyServerToolName) rendered a LaunchAgent property list, but it could not be decoded back into UTF-8 text for printing.",
                    )
                }

                print(xml, terminator: "")

            case let .install(options):
                try options.install()

            case let .promoteLive(options):
                try options.promoteLive()

            case let .uninstall(options):
                try options.uninstall()

            case let .status(options):
                try print(options.statusSummary())
        }
    }
}

// MARK: - LaunchAgentCommandError

/// Human-friendly parse or execution error for the LaunchAgent command surface.
package typealias LaunchAgentCommandError = SpeakSwiftlyServerToolCommandError
