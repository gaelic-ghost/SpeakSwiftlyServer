import Configuration
import Foundation

// MARK: - HTTP Config

struct HTTPConfig: Sendable {
    let enabled: Bool
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double

    init(
        enabled: Bool,
        host: String,
        port: Int,
        sseHeartbeatSeconds: Double
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.sseHeartbeatSeconds = sseHeartbeatSeconds
    }

    init(config: ConfigReader) throws {
        do {
            self.enabled = try config.requiredBool(forKey: "enabled")
            self.host = try config.requiredString(forKey: "host")
            self.port = try Self.requirePositive(
                try config.requiredInt(forKey: "port"),
                key: "APP_HTTP_PORT"
            )
            self.sseHeartbeatSeconds = try Self.requirePositive(
                try config.requiredDouble(forKey: "sseHeartbeatSeconds"),
                key: "APP_HTTP_SSE_HEARTBEAT_SECONDS"
            )
        } catch {
            throw ServerConfigurationError(key: "APP_HTTP_*", underlyingError: error)
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
