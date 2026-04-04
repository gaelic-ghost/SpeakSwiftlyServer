import Configuration
import Foundation

// MARK: - MCP Config

struct MCPConfig: Sendable {
    let enabled: Bool
    let path: String
    let serverName: String
    let title: String

    init(
        enabled: Bool,
        path: String,
        serverName: String,
        title: String
    ) {
        self.enabled = enabled
        self.path = path
        self.serverName = serverName
        self.title = title
    }

    init(config: ConfigReader) throws {
        do {
            self.enabled = try config.requiredBool(forKey: "enabled")
            self.path = try config.requiredString(forKey: "path")
            self.serverName = try config.requiredString(forKey: "serverName")
            self.title = try config.requiredString(forKey: "title")
        } catch {
            throw ServerConfigurationError(key: "APP_MCP_*", underlyingError: error)
        }
    }
}
