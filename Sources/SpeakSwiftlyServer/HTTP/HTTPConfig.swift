import Configuration
import Foundation

struct HTTPConfig {
    let enabled: Bool
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double

    // MARK: - Initialization

    init(
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

    init(
        config: ConfigReader,
        fallbackHost: String,
        fallbackPort: Int,
        fallbackSSEHeartbeatSeconds: Double,
    ) throws {
        do {
            enabled = try config.requiredBool(forKey: "enabled")
            host = try Self.requiredString(
                config,
                key: "host",
                fallback: fallbackHost,
            )
            port = try Self.requirePositive(
                Self.requiredInt(
                    config,
                    key: "port",
                    fallback: fallbackPort,
                ),
                key: "APP_HTTP_PORT",
            )
            sseHeartbeatSeconds = try Self.requirePositive(
                Self.requiredDouble(
                    config,
                    key: "sseHeartbeatSeconds",
                    fallback: fallbackSSEHeartbeatSeconds,
                ),
                key: "APP_HTTP_SSE_HEARTBEAT_SECONDS",
            )
        } catch {
            throw ServerConfigurationError(key: "APP_HTTP_*", underlyingError: error)
        }
    }

    // MARK: - Validation

    private static func requiredString(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: String,
    ) throws -> String {
        do {
            return try config.requiredString(forKey: key)
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return fallback
        }
    }

    private static func requiredInt(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: Int,
    ) throws -> Int {
        do {
            return try config.requiredInt(forKey: key)
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return fallback
        }
    }

    private static func requiredDouble(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: Double,
    ) throws -> Double {
        do {
            return try config.requiredDouble(forKey: key)
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return fallback
        }
    }

    private static func isMissingRequiredConfigValue(_ error: any Error) -> Bool {
        String(describing: error).contains("Missing required config value for key:")
    }

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
