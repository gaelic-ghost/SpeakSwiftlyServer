import Configuration
import Foundation

package struct HTTPListenersConfig {
    package static let localhostTransportName = "http_localhost"
    package static let lanTransportName = "http_lan"
    package static let lanBonjourType = "_spswift-http._tcp"
    package static let bonjourDomain = "local."

    package let localhost: HTTPConfig
    package let lan: LANHTTPListenerConfig

    package init(
        localhost: HTTPConfig,
        lan: LANHTTPListenerConfig,
    ) {
        self.localhost = localhost
        self.lan = lan
    }

    package init(
        config: ConfigReader,
        legacyHTTPConfig: HTTPConfig,
        fallbackServiceName: String,
    ) throws {
        localhost = try HTTPConfig(
            config: config.scoped(to: "localhost"),
            fallbackEnabled: legacyHTTPConfig.enabled,
            fallbackHost: legacyHTTPConfig.host,
            fallbackPort: legacyHTTPConfig.port,
            fallbackSSEHeartbeatSeconds: legacyHTTPConfig.sseHeartbeatSeconds,
        )
        lan = try LANHTTPListenerConfig(
            config: config.scoped(to: "lan"),
            fallbackServiceName: fallbackServiceName,
        )
    }
}

package struct LANHTTPListenerConfig: Equatable {
    package let enabled: Bool
    package let host: String
    package let port: Int
    package let sseHeartbeatSeconds: Double
    package let advertiseBonjour: Bool
    package let serviceName: String

    package var http: HTTPConfig {
        .init(
            enabled: enabled,
            host: host,
            port: port,
            sseHeartbeatSeconds: sseHeartbeatSeconds,
        )
    }

    package init(
        enabled: Bool,
        host: String,
        port: Int,
        sseHeartbeatSeconds: Double,
        advertiseBonjour: Bool,
        serviceName: String,
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.sseHeartbeatSeconds = sseHeartbeatSeconds
        self.advertiseBonjour = advertiseBonjour
        self.serviceName = serviceName
    }

    package init(
        config: ConfigReader,
        fallbackServiceName: String,
    ) throws {
        do {
            enabled = try Self.requiredBool(config, key: "enabled", fallback: false)
            host = try Self.requiredString(config, key: "host", fallback: "0.0.0.0")
            port = try Self.requireValidPort(
                Self.requiredInt(config, key: "port", fallback: 0),
                key: "APP_LISTENERS_LAN_PORT",
            )
            sseHeartbeatSeconds = try Self.requirePositive(
                Self.requiredDouble(config, key: "sseHeartbeatSeconds", fallback: 10),
                key: "APP_LISTENERS_LAN_SSE_HEARTBEAT_SECONDS",
            )
            advertiseBonjour = try Self.requiredBool(config, key: "advertiseBonjour", fallback: true)
            serviceName = try Self.requiredNonEmptyString(
                config,
                key: "serviceName",
                fallback: "\(fallbackServiceName) LAN",
            )
        } catch let error as ServerConfigurationError {
            throw error
        } catch {
            throw ServerConfigurationError(key: "APP_LISTENERS_LAN_*", underlyingError: error)
        }
    }

    private static func requiredBool(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: Bool,
    ) throws -> Bool {
        do {
            return try config.requiredBool(forKey: key)
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return fallback
        }
    }

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

    private static func requiredNonEmptyString(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: String,
    ) throws -> String {
        let value = try requiredString(config, key: key, fallback: fallback)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw ServerConfigurationError(
                "Configuration value 'APP_LISTENERS_LAN_SERVICE_NAME' must be non-empty when the LAN HTTP listener is configured.",
            )
        }

        return value
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

    private static func requireValidPort(_ value: Int, key: String) throws -> Int {
        guard value >= 0, value <= 65_535 else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be between 0 and 65535, but received '\(value)'. Use '0' to let macOS choose an available LAN listener port.",
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

    private static func isMissingRequiredConfigValue(_ error: any Error) -> Bool {
        String(describing: error).contains("Missing required config value for key:")
    }
}
