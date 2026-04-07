import SpeakSwiftlyServerCore

// MARK: - Main

@main
enum SpeakSwiftlyServerExecutableMain {
    static func main() async throws {
        try await ServerRuntimeEntrypoint.run()
    }
}
