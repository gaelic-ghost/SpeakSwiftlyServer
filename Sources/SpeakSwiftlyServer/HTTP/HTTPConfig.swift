import Foundation

// MARK: - HTTP Config

struct HTTPConfig: Sendable {
    let enabled: Bool
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double
}
