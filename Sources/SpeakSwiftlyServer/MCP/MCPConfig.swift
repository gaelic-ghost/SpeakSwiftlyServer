import Foundation

// MARK: - MCP Config

struct MCPConfig: Sendable {
    let enabled: Bool
    let path: String
    let serverName: String
    let title: String

    static func load(environment: [String: String]) -> MCPConfig {
        .init(
            enabled: parseBool(environment["APP_MCP_ENABLED"], defaultValue: false),
            path: environment["APP_MCP_PATH"] ?? "/mcp",
            serverName: environment["APP_MCP_SERVER_NAME"] ?? "speak-to-user-mcp",
            title: environment["APP_MCP_TITLE"] ?? "SpeakSwiftlyMCP"
        )
    }

    private static func parseBool(_ rawValue: String?, defaultValue: Bool) -> Bool {
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
}
