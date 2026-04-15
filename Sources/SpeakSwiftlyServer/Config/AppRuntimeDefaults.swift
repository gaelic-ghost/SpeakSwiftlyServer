import Configuration
import Foundation

// MARK: - Runtime Default Profiles

enum AppRuntimeDefaultProfile: String {
    case standaloneExecutable = "standalone-executable"
    case launchAgent = "launch-agent"
    case embeddedSession = "embedded-session"

    static let environmentKey = "SPEAKSWIFTLY_SERVER_DEFAULT_PROFILE"

    var port: Int {
        switch self {
            case .standaloneExecutable:
                7338
            case .launchAgent:
                7337
            case .embeddedSession:
                7339
        }
    }

    var configDefaults: [AbsoluteConfigKey: ConfigValue] {
        [
            .init(["app", "name"]): "speak-swiftly-server",
            .init(["app", "environment"]): "development",
            .init(["app", "host"]): "127.0.0.1",
            .init(["app", "port"]): ConfigValue(integerLiteral: port),
            .init(["app", "sseHeartbeatSeconds"]): 10.0,
            .init(["app", "completedJobTTLSeconds"]): 900.0,
            .init(["app", "completedJobMaxCount"]): 200,
            .init(["app", "jobPruneIntervalSeconds"]): 60.0,
            .init(["app", "http", "enabled"]): true,
            .init(["app", "mcp", "enabled"]): false,
            .init(["app", "mcp", "path"]): "/mcp",
            .init(["app", "mcp", "serverName"]): "speak-swiftly-mcp",
            .init(["app", "mcp", "title"]): "SpeakSwiftly",
        ]
    }

    static func resolve(
        explicitProfile: AppRuntimeDefaultProfile?,
        environment: [String: String],
    ) -> AppRuntimeDefaultProfile {
        if let explicitProfile {
            return explicitProfile
        }

        guard let rawValue = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty
        else {
            return .standaloneExecutable
        }

        return AppRuntimeDefaultProfile(rawValue: rawValue) ?? .standaloneExecutable
    }
}
