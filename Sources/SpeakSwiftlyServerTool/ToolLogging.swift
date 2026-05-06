import OSLog

enum ToolLog {
    static let command = Logger(
        subsystem: "com.gaelic-ghost.speak-swiftly-server.tool",
        category: "command",
    )

    static let healthcheck = Logger(
        subsystem: "com.gaelic-ghost.speak-swiftly-server.tool",
        category: "healthcheck",
    )

    static let launchAgent = Logger(
        subsystem: "com.gaelic-ghost.speak-swiftly-server.tool",
        category: "launch-agent",
    )
}
