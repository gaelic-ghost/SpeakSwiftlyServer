import Darwin
import SpeakSwiftlyServer

// MARK: - Main

@main
enum SpeakSwiftlyServerToolMain {
    static func main() async {
        do {
            let command = try SpeakSwiftlyServerToolCommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try await command.run()
        } catch let error as SpeakSwiftlyServerToolCommandError {
            ToolLog.command.error("SpeakSwiftlyServerTool command failed: \(error.message, privacy: .public)")
            fputs("\(error.message)\n", stderr)
            exit(2)
        } catch {
            ToolLog.command.error("SpeakSwiftlyServerTool failed unexpectedly: \(String(describing: error), privacy: .public)")
            fputs("SpeakSwiftlyServerTool failed unexpectedly. Likely cause: \(error)\n", stderr)
            exit(1)
        }
    }
}
