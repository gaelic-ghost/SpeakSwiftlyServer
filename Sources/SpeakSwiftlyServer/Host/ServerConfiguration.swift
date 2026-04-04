import Configuration
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

    init(
        name: String,
        environment: String,
        host: String,
        port: Int,
        sseHeartbeatSeconds: Double,
        completedJobTTLSeconds: Double,
        completedJobMaxCount: Int,
        jobPruneIntervalSeconds: Double
    ) {
        self.name = name
        self.environment = environment
        self.host = host
        self.port = port
        self.sseHeartbeatSeconds = sseHeartbeatSeconds
        self.completedJobTTLSeconds = completedJobTTLSeconds
        self.completedJobMaxCount = completedJobMaxCount
        self.jobPruneIntervalSeconds = jobPruneIntervalSeconds
    }

    init(config: ConfigReader) throws {
        do {
            self.name = try config.requiredString(forKey: "name")
            self.environment = try config.requiredString(forKey: "environment")
            self.host = try config.requiredString(forKey: "host")
            self.port = try Self.requirePositive(
                try config.requiredInt(forKey: "port"),
                key: "APP_PORT"
            )
            self.sseHeartbeatSeconds = try Self.requirePositive(
                try config.requiredDouble(forKey: "sseHeartbeatSeconds"),
                key: "APP_SSE_HEARTBEAT_SECONDS"
            )
            self.completedJobTTLSeconds = try Self.requirePositive(
                try config.requiredDouble(forKey: "completedJobTTLSeconds"),
                key: "APP_COMPLETED_JOB_TTL_SECONDS"
            )
            self.completedJobMaxCount = try Self.requirePositive(
                try config.requiredInt(forKey: "completedJobMaxCount"),
                key: "APP_COMPLETED_JOB_MAX_COUNT"
            )
            self.jobPruneIntervalSeconds = try Self.requirePositive(
                try config.requiredDouble(forKey: "jobPruneIntervalSeconds"),
                key: "APP_JOB_PRUNE_INTERVAL_SECONDS"
            )
        } catch {
            throw ServerConfigurationError(key: "APP_*", underlyingError: error)
        }
    }

    private static func requirePositive(_ value: Int, key: String) throws -> Int {
        guard value > 0 else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be a positive integer, but received '\(value)'."
            )
        }
        return value
    }

    private static func requirePositive(_ value: Double, key: String) throws -> Double {
        guard value > 0 else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be a positive number, but received '\(value)'."
            )
        }
        return value
    }
}

struct ServerConfigurationError: Error, Sendable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    init(key: String, underlyingError: any Error) {
        self.message = "Configuration value '\(key)' could not be loaded: \(underlyingError)."
    }

    var description: String { message }
}
