import Foundation

// MARK: - Server Runtime Entrypoint

public enum ServerRuntimeEntrypoint {
    public static func run() async throws {
        let session = try await EmbeddedServerSession.start()
        try await session.waitUntilStopped()
    }
}
