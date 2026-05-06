import Configuration
import Foundation

struct ServerConfiguration {
    let name: String
    let environment: String
    let defaultVoiceProfileName: String?
    let host: String
    let port: Int
    let sseHeartbeatSeconds: Double
    let completedJobTTLSeconds: Double
    let completedJobMaxCount: Int
    let jobPruneIntervalSeconds: Double

    // MARK: - Initialization

    init(
        name: String,
        environment: String,
        defaultVoiceProfileName: String?,
        host: String,
        port: Int,
        sseHeartbeatSeconds: Double,
        completedJobTTLSeconds: Double,
        completedJobMaxCount: Int,
        jobPruneIntervalSeconds: Double,
    ) {
        self.name = name
        self.environment = environment
        self.defaultVoiceProfileName = Self.normalizedOptionalString(defaultVoiceProfileName)
        self.host = host
        self.port = port
        self.sseHeartbeatSeconds = sseHeartbeatSeconds
        self.completedJobTTLSeconds = completedJobTTLSeconds
        self.completedJobMaxCount = completedJobMaxCount
        self.jobPruneIntervalSeconds = jobPruneIntervalSeconds
    }

    init(config: ConfigReader) throws {
        do {
            name = try config.requiredString(forKey: "name")
            environment = try config.requiredString(forKey: "environment")
            defaultVoiceProfileName = try Self.optionalString(
                config,
                key: "defaultVoiceProfileName",
            )
            host = try config.requiredString(forKey: "host")
            port = try Self.requirePositive(
                config.requiredInt(forKey: "port"),
                key: "APP_PORT",
            )
            sseHeartbeatSeconds = try Self.requirePositive(
                config.requiredDouble(forKey: "sseHeartbeatSeconds"),
                key: "APP_SSE_HEARTBEAT_SECONDS",
            )
            completedJobTTLSeconds = try Self.requirePositive(
                config.requiredDouble(forKey: "completedJobTTLSeconds"),
                key: "APP_COMPLETED_JOB_TTL_SECONDS",
            )
            completedJobMaxCount = try Self.requirePositive(
                config.requiredInt(forKey: "completedJobMaxCount"),
                key: "APP_COMPLETED_JOB_MAX_COUNT",
            )
            jobPruneIntervalSeconds = try Self.requirePositive(
                config.requiredDouble(forKey: "jobPruneIntervalSeconds"),
                key: "APP_JOB_PRUNE_INTERVAL_SECONDS",
            )
        } catch {
            throw ServerConfigurationError(key: "APP_*", underlyingError: error)
        }
    }

    // MARK: - Validation

    private static func optionalString(
        _ config: ConfigReader,
        key: ConfigKey,
    ) throws -> String? {
        do {
            return try normalizedOptionalString(config.requiredString(forKey: key))
        } catch {
            guard String(describing: error).contains("Missing required config value for key:") else {
                throw error
            }

            return nil
        }
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
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

struct ServerConfigurationError: Error, CustomStringConvertible {
    let message: String

    // MARK: - Initialization

    init(_ message: String) {
        self.message = message
    }

    init(key: String, underlyingError: any Error) {
        message = "Configuration value '\(key)' could not be loaded: \(underlyingError)."
    }

    // MARK: - CustomStringConvertible

    var description: String { message }
}
