import Configuration
import Foundation

package struct HTTPConfig {
    package let enabled: Bool
    package let host: String
    package let port: Int
    package let sseHeartbeatSeconds: Double

    // MARK: - Initialization

    package init(
        enabled: Bool,
        host: String,
        port: Int,
        sseHeartbeatSeconds: Double,
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.sseHeartbeatSeconds = sseHeartbeatSeconds
    }

    package init(
        config: ConfigReader,
        fallbackHost: String,
        fallbackPort: Int,
        fallbackSSEHeartbeatSeconds: Double,
    ) throws {
        try self.init(
            config: config,
            fallbackEnabled: true,
            fallbackHost: fallbackHost,
            fallbackPort: fallbackPort,
            fallbackSSEHeartbeatSeconds: fallbackSSEHeartbeatSeconds,
        )
    }

    package init(
        config: ConfigReader,
        fallbackEnabled: Bool,
        fallbackHost: String,
        fallbackPort: Int,
        fallbackSSEHeartbeatSeconds: Double,
    ) throws {
        do {
            enabled = try config.requiredBool(forKey: "enabled", fallback: fallbackEnabled)
            host = try config.requiredString(
                forKey: "host",
                fallback: fallbackHost,
            )
            port = try Self.requirePositive(
                config.requiredInt(
                    forKey: "port",
                    fallback: fallbackPort,
                ),
                key: "APP_HTTP_PORT",
            )
            sseHeartbeatSeconds = try Self.requirePositive(
                config.requiredDouble(
                    forKey: "sseHeartbeatSeconds",
                    fallback: fallbackSSEHeartbeatSeconds,
                ),
                key: "APP_HTTP_SSE_HEARTBEAT_SECONDS",
            )
        } catch {
            throw ServerConfigurationError(key: "APP_HTTP_*", underlyingError: error)
        }
    }

    // MARK: - Validation

    private static func requirePositive(_ value: Int, key: String) throws -> Int {
        guard value > 0 else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be a positive integer, but received '\(value)'.",
            )
        }

        return value
    }

    private static func requirePositive(_ value: Double, key: String) throws -> Double {
        guard value > 0 else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be a positive number, but received '\(value)'.",
            )
        }

        return value
    }
}
