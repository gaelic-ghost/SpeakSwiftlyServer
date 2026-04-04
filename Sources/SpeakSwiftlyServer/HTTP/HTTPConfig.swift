import Foundation

// MARK: - HTTP Config

struct HTTPConfig: Sendable {
    let enabled: Bool
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double

    static func load(
        environment: [String: String],
        defaults: ServerConfiguration
    ) throws -> HTTPConfig {
        .init(
            enabled: parseBool(environment["APP_HTTP_ENABLED"], defaultValue: true, key: "APP_HTTP_ENABLED"),
            host: environment["APP_HTTP_HOST"] ?? defaults.host,
            port: try parseInt(environment["APP_HTTP_PORT"], defaultValue: defaults.port, key: "APP_HTTP_PORT"),
            sseHeartbeatSeconds: try parseDouble(
                environment["APP_HTTP_SSE_HEARTBEAT_SECONDS"],
                defaultValue: defaults.sseHeartbeatSeconds,
                key: "APP_HTTP_SSE_HEARTBEAT_SECONDS"
            )
        )
    }

    private static func parseBool(_ rawValue: String?, defaultValue: Bool, key: String) -> Bool {
        guard let rawValue else { return defaultValue }
        return switch rawValue.lowercased() {
        case "1", "true", "yes", "on":
            true
        case "0", "false", "no", "off":
            false
        default:
            defaultValue
        }
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
