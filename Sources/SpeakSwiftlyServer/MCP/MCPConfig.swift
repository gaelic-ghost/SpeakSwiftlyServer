import Configuration
import Foundation

struct MCPConfig {
    let enabled: Bool
    let path: String
    let serverName: String
    let title: String

    // MARK: - Initialization

    init(
        enabled: Bool,
        path: String,
        serverName: String,
        title: String,
    ) {
        self.enabled = enabled
        self.path = path
        self.serverName = serverName
        self.title = title
    }

    init(config: ConfigReader) throws {
        do {
            enabled = try config.requiredBool(forKey: "enabled")
            path = try config.requiredString(forKey: "path")
            serverName = try config.requiredString(forKey: "serverName")
            title = try config.requiredString(forKey: "title")
        } catch {
            throw ServerConfigurationError(key: "APP_MCP_*", underlyingError: error)
        }
    }
}
