import Configuration
import Foundation

package struct NetworkAudioReceiverConfig: Equatable {
    package static let transportName = "network_audio_receiver"

    package let enabled: Bool
    package let serviceName: String
    package let port: UInt16
    package let sharedToken: String?

    package var advertisedAddress: String? {
        guard enabled else {
            return nil
        }

        return "\(serviceName).local:\(port == 0 ? "auto" : String(port))"
    }

    package init(
        enabled: Bool,
        serviceName: String,
        port: UInt16,
        sharedToken: String?,
    ) {
        self.enabled = enabled
        self.serviceName = serviceName
        self.port = port
        self.sharedToken = sharedToken
    }

    package init(
        config: ConfigReader,
        fallbackServiceName: String,
    ) throws {
        do {
            enabled = try config.requiredBool(forKey: "enabled")
            serviceName = try Self.requiredString(
                config,
                key: "serviceName",
                fallback: fallbackServiceName,
            )
            port = try Self.requireValidPort(
                Self.requiredInt(config, key: "port", fallback: 0),
                key: "APP_NETWORK_AUDIO_RECEIVER_PORT",
            )
            sharedToken = try Self.optionalNonEmptyString(config, key: "sharedToken")

            if enabled, sharedToken == nil {
                throw ServerConfigurationError(
                    "Configuration value 'APP_NETWORK_AUDIO_RECEIVER_SHARED_TOKEN' must be non-empty when 'app.networkAudioReceiver.enabled' is true.",
                )
            }
        } catch let error as ServerConfigurationError {
            throw error
        } catch {
            throw ServerConfigurationError(key: "APP_NETWORK_AUDIO_RECEIVER_*", underlyingError: error)
        }
    }

    private static func requiredString(
        _ config: ConfigReader,
        key: ConfigKey,
        fallback: String,
    ) throws -> String {
        do {
            let value = try config.requiredString(forKey: key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? fallback : value
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

    private static func optionalNonEmptyString(
        _ config: ConfigReader,
        key: ConfigKey,
    ) throws -> String? {
        do {
            let value = try config.requiredString(forKey: key)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return nil
        }
    }

    private static func requireValidPort(_ value: Int, key: String) throws -> UInt16 {
        guard (0...Int(UInt16.max)).contains(value) else {
            throw ServerConfigurationError(
                "Configuration value '\(key)' must be between 0 and \(UInt16.max), but received '\(value)'. Use 0 to let Network.framework choose an available port.",
            )
        }

        return UInt16(value)
    }

    private static func isMissingRequiredConfigValue(_ error: any Error) -> Bool {
        String(describing: error).contains("Missing required config value for key:")
    }
}
