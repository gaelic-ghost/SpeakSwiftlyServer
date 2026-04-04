import Foundation
import Hummingbird

// MARK: - Entry Point

@main
enum SpeakSwiftlyServer {
    static func main() async throws {
        let config = try await AppConfig.load()
        let state = await MainActor.run { ServerState() }
        let host = await ServerHost.live(appConfig: config, state: state)
        let app = assembleHBApp(configuration: config.http, host: host)
        defer {
            Task {
                await host.shutdown()
            }
        }
        try await app.runService()
    }
}
