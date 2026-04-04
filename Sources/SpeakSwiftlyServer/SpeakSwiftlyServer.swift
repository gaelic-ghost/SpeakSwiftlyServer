import Foundation
import Hummingbird

// MARK: - Entry Point

@main
enum SpeakSwiftlyServer {
    static func main() async throws {
        let config = try AppConfig.load()
        let state = await MainActor.run { ServerState() }
        let host = await ServerHost.live(configuration: config.server, state: state)
        let app = makeApplication(configuration: config.server, host: host)
        defer {
            Task {
                await host.shutdown()
            }
        }
        try await app.runService()
    }
}
