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
            fputs("\(error.message)\n", stderr)
            exit(2)
        } catch {
            fputs("SpeakSwiftlyServerTool failed unexpectedly. Likely cause: \(error)\n", stderr)
            exit(1)
        }
    }
}
