import Darwin
import SpeakSwiftlyServerCore

// MARK: - Main

@main
enum SpeakSwiftlyServerCliMain {
    static func main() {
        do {
            let command = try SpeakSwiftlyServerCliCommand.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            try command.run()
        } catch let error as SpeakSwiftlyServerCliCommandError {
            fputs("\(error.message)\n", stderr)
            exit(2)
        } catch let error as LaunchAgentCommandError {
            fputs("\(error.message)\n", stderr)
            exit(2)
        } catch {
            fputs("SpeakSwiftlyServerCli failed unexpectedly. Likely cause: \(error)\n", stderr)
            exit(1)
        }
    }
}
