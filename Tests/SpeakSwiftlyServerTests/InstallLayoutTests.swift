import Foundation
import Testing
@testable import SpeakSwiftlyServer

// MARK: - Install Layout Tests

@Test func installedLogsReadTextLinesAndJSONLinesFromOwnedPaths() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let layout = ServerInstallLayout(
        launchAgentLabel: "com.example.test",
        workingDirectoryURL: tempDirectory,
        applicationSupportDirectoryURL: tempDirectory.appendingPathComponent("Application Support", isDirectory: true),
        cacheDirectoryURL: tempDirectory.appendingPathComponent("Caches", isDirectory: true),
        logsDirectoryURL: tempDirectory.appendingPathComponent("Logs", isDirectory: true),
        launchAgentsDirectoryURL: tempDirectory.appendingPathComponent("LaunchAgents", isDirectory: true),
        launchAgentPlistURL: tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist", isDirectory: false),
        serverConfigFileURL: tempDirectory.appendingPathComponent("Application Support/server.yaml", isDirectory: false),
        launchAgentConfigAliasURL: tempDirectory.appendingPathComponent("Caches/launch-agent-server.yaml", isDirectory: false),
        runtimeBaseDirectoryURL: tempDirectory.appendingPathComponent("Application Support/runtime", isDirectory: true),
        runtimeProfileRootURL: tempDirectory.appendingPathComponent("Application Support/runtime/profiles", isDirectory: true),
        runtimeConfigurationFileURL: tempDirectory.appendingPathComponent("Application Support/runtime/configuration.json", isDirectory: false),
        standardOutLogURL: tempDirectory.appendingPathComponent("Logs/stdout.log", isDirectory: false),
        standardErrorLogURL: tempDirectory.appendingPathComponent("Logs/stderr.log", isDirectory: false)
    )

    try FileManager.default.createDirectory(at: layout.logsDirectoryURL, withIntermediateDirectories: true)
    try "ready\nplain line\n".write(to: layout.standardOutLogURL, atomically: true, encoding: .utf8)
    try """
    {"event":"resident_model_ready","ok":true}
    {"event":"playback_engine_ready","ok":true}
    trailing note
    """.write(to: layout.standardErrorLogURL, atomically: true, encoding: .utf8)

    let snapshot = try ServerInstalledLogs.read(layout: layout, maximumLineCount: 2)

    #expect(snapshot.stdout.exists)
    #expect(snapshot.stdout.text == "ready\nplain line")
    #expect(snapshot.stdout.lines == ["ready", "plain line"])
    #expect(snapshot.stdout.jsonLineTexts.isEmpty)

    #expect(snapshot.stderr.exists)
    #expect(snapshot.stderr.totalLineCount == 3)
    #expect(snapshot.stderr.truncatedLineCount == 1)
    #expect(snapshot.stderr.lines == [
        #"{"event":"playback_engine_ready","ok":true}"#,
        "trailing note",
    ])
    #expect(snapshot.stderr.jsonLineTexts == [#"{"event":"playback_engine_ready","ok":true}"#])

    struct LogEvent: Decodable, Sendable, Equatable {
        let event: String
        let ok: Bool
    }

    let decoded = try snapshot.stderr.decodeJSONLines(as: LogEvent.self)
    #expect(decoded == [.init(event: "playback_engine_ready", ok: true)])
}

@Test func installedLogsReturnMissingSnapshotWhenLogFileDoesNotExist() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let layout = ServerInstallLayout(
        launchAgentLabel: "com.example.test",
        workingDirectoryURL: tempDirectory,
        applicationSupportDirectoryURL: tempDirectory.appendingPathComponent("Application Support", isDirectory: true),
        cacheDirectoryURL: tempDirectory.appendingPathComponent("Caches", isDirectory: true),
        logsDirectoryURL: tempDirectory.appendingPathComponent("Logs", isDirectory: true),
        launchAgentsDirectoryURL: tempDirectory.appendingPathComponent("LaunchAgents", isDirectory: true),
        launchAgentPlistURL: tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist", isDirectory: false),
        serverConfigFileURL: tempDirectory.appendingPathComponent("Application Support/server.yaml", isDirectory: false),
        launchAgentConfigAliasURL: tempDirectory.appendingPathComponent("Caches/launch-agent-server.yaml", isDirectory: false),
        runtimeBaseDirectoryURL: tempDirectory.appendingPathComponent("Application Support/runtime", isDirectory: true),
        runtimeProfileRootURL: tempDirectory.appendingPathComponent("Application Support/runtime/profiles", isDirectory: true),
        runtimeConfigurationFileURL: tempDirectory.appendingPathComponent("Application Support/runtime/configuration.json", isDirectory: false),
        standardOutLogURL: tempDirectory.appendingPathComponent("Logs/stdout.log", isDirectory: false),
        standardErrorLogURL: tempDirectory.appendingPathComponent("Logs/stderr.log", isDirectory: false)
    )

    let snapshot = try ServerInstalledLogs.read(layout: layout)

    #expect(snapshot.stdout.exists == false)
    #expect(snapshot.stderr.exists == false)
    #expect(snapshot.stdout.text.isEmpty)
    #expect(snapshot.stderr.lines.isEmpty)
}

@Test func launchAgentEnvironmentUsesCacheAliasWhenConfigPathContainsSpaces() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let layout = ServerInstallLayout(
        launchAgentLabel: "com.example.test",
        workingDirectoryURL: tempDirectory,
        applicationSupportDirectoryURL: tempDirectory.appendingPathComponent("Application Support", isDirectory: true),
        cacheDirectoryURL: tempDirectory.appendingPathComponent("Caches", isDirectory: true),
        logsDirectoryURL: tempDirectory.appendingPathComponent("Logs", isDirectory: true),
        launchAgentsDirectoryURL: tempDirectory.appendingPathComponent("LaunchAgents", isDirectory: true),
        launchAgentPlistURL: tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist", isDirectory: false),
        serverConfigFileURL: tempDirectory.appendingPathComponent("Application Support/server.yaml", isDirectory: false),
        launchAgentConfigAliasURL: tempDirectory.appendingPathComponent("Caches/launch-agent-server.yaml", isDirectory: false),
        runtimeBaseDirectoryURL: tempDirectory.appendingPathComponent("Application Support/runtime", isDirectory: true),
        runtimeProfileRootURL: tempDirectory.appendingPathComponent("Application Support/runtime/profiles", isDirectory: true),
        runtimeConfigurationFileURL: tempDirectory.appendingPathComponent("Application Support/runtime/configuration.json", isDirectory: false),
        standardOutLogURL: tempDirectory.appendingPathComponent("Logs/stdout.log", isDirectory: false),
        standardErrorLogURL: tempDirectory.appendingPathComponent("Logs/stderr.log", isDirectory: false)
    )

    let environmentVariables = layout.launchAgentEnvironmentVariables(
        configFilePath: layout.serverConfigFileURL.path,
        reloadIntervalSeconds: nil
    )

    #expect(environmentVariables["APP_CONFIG_FILE"] == layout.launchAgentConfigAliasURL.path)
    #expect(environmentVariables["SPEAKSWIFTLY_PROFILE_ROOT"] == layout.runtimeProfileRootURL.path)
}

private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
