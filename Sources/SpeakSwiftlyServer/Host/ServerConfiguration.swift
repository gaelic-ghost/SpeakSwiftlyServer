import Foundation

// MARK: - Server Configuration

struct ServerConfiguration: Sendable {
    let name: String
    let environment: String
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double
    let completedJobTTLSeconds: Double
    let completedJobMaxCount: Int
    let jobPruneIntervalSeconds: Double

    static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ServerConfiguration {
        try .init(
            name: environment["APP_NAME"] ?? "speak-swiftly-server",
            environment: environment["APP_ENVIRONMENT"] ?? "development",
            host: environment["APP_HOST"] ?? "127.0.0.1",
            port: parseInt(environment["APP_PORT"], defaultValue: 7337, key: "APP_PORT"),
            sseHeartbeatSeconds: parseDouble(
                environment["APP_SSE_HEARTBEAT_SECONDS"],
                defaultValue: 10,
                key: "APP_SSE_HEARTBEAT_SECONDS"
            ),
            completedJobTTLSeconds: parseDouble(
                environment["APP_COMPLETED_JOB_TTL_SECONDS"],
                defaultValue: 900,
                key: "APP_COMPLETED_JOB_TTL_SECONDS"
            ),
            completedJobMaxCount: parseInt(
                environment["APP_COMPLETED_JOB_MAX_COUNT"],
                defaultValue: 200,
                key: "APP_COMPLETED_JOB_MAX_COUNT"
            ),
            jobPruneIntervalSeconds: parseDouble(
                environment["APP_JOB_PRUNE_INTERVAL_SECONDS"],
                defaultValue: 60,
                key: "APP_JOB_PRUNE_INTERVAL_SECONDS"
            )
        )
    }

    private static func parseInt(_ rawValue: String?, defaultValue: Int, key: String) throws -> Int {
        guard let rawValue else { return defaultValue }
        guard let value = Int(rawValue), value > 0 else {
            throw ServerConfigurationError(
                "Environment value '\(key)' must be a positive integer, but received '\(rawValue)'."
            )
        }
        return value
    }

    private static func parseDouble(_ rawValue: String?, defaultValue: Double, key: String) throws -> Double {
        guard let rawValue else { return defaultValue }
        guard let value = Double(rawValue), value > 0 else {
            throw ServerConfigurationError(
                "Environment value '\(key)' must be a positive number, but received '\(rawValue)'."
            )
        }
        return value
    }
}

struct ServerConfigurationError: Error, Sendable {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
