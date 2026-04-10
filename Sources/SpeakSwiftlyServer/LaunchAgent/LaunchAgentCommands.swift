import Foundation

let speakSwiftlyServerToolName = "SpeakSwiftlyServerTool"

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
      --profile-root <path>
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
