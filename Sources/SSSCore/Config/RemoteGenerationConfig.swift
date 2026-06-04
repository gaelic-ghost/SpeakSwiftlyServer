import Configuration
import Foundation

package struct RemoteGenerationConfig: Equatable {
    package static let streamTokenHeaderName = "X-SpeakSwiftly-Remote-Generation-Token"

    package let allowRemoteStreamRequests: Bool
    package let sharedToken: String?

    package init(
        allowRemoteStreamRequests: Bool,
        sharedToken: String?,
    ) {
        self.allowRemoteStreamRequests = allowRemoteStreamRequests
        self.sharedToken = Self.normalizedOptionalString(sharedToken)
    }

    package init(config: ConfigReader) throws {
        do {
            allowRemoteStreamRequests = try Self.requiredBool(
                config,
                key: "allowRemoteStreamRequests",
                fallback: false,
            )
            sharedToken = try Self.optionalNonEmptyString(config, key: "sharedToken")

            if allowRemoteStreamRequests, sharedToken == nil {
                throw ServerConfigurationError(
                    "Configuration value 'APP_REMOTE_GENERATION_SHARED_TOKEN' must be non-empty when 'app.remoteGeneration.allowRemoteStreamRequests' is true.",
                )
            }
        } catch let error as ServerConfigurationError {
            throw error
        } catch {
            throw ServerConfigurationError(key: "APP_REMOTE_GENERATION_*", underlyingError: error)
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

    private static func optionalNonEmptyString(
        _ config: ConfigReader,
        key: ConfigKey,
    ) throws -> String? {
        do {
            return try normalizedOptionalString(config.requiredString(forKey: key))
        } catch {
            guard isMissingRequiredConfigValue(error) else { throw error }

            return nil
        }
    }

    private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }

        return trimmed
    }

    private static func isMissingRequiredConfigValue(_ error: any Error) -> Bool {
        String(describing: error).contains("Missing required config value for key:")
    }
}
