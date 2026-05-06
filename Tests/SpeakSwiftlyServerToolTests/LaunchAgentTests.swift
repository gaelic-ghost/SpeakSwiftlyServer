import Foundation
@testable import SpeakSwiftlyServer
@testable import SpeakSwiftlyServerTool
import Testing

// MARK: - Launch Agent Command Tests

@Test func `launch agent promote live parses without preexisting staged executable`() throws {
    let repositoryRootURL = try makeLaunchAgentCommandTestRepository()

    let command = try LaunchAgentCommand.parse(
        arguments: ["promote-live"],
        currentDirectoryPath: repositoryRootURL.path,
        currentExecutablePath: testToolExecutablePath(in: repositoryRootURL),
    )

    switch command.action {
        case let .promoteLive(options):
            #expect(options.repositoryRootPath == repositoryRootURL.path)
            #expect(
                options.installOptions.toolExecutablePath
                    == repositoryRootURL
                    .appendingPathComponent(".release-artifacts/current/SpeakSwiftlyServerTool", isDirectory: false)
                    .path,
            )

        default:
            Issue.record("Expected `launch-agent promote-live` to parse into the promote-live action.")
    }
}

@Test func `release artifact replacement keeps existing destination when source copy fails`() throws {
    let temporaryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)

    let destinationURL = temporaryRootURL.appendingPathComponent("SpeakSwiftlyServerTool", isDirectory: false)
    let missingSourceURL = temporaryRootURL.appendingPathComponent("missing-tool", isDirectory: false)
    try "existing staged tool".write(to: destinationURL, atomically: true, encoding: .utf8)

    do {
        try ReleaseArtifactPromoter.replaceItem(at: destinationURL, with: missingSourceURL, permissions: 0o755)
        Issue.record("Expected replacement to fail when the source artifact is missing.")
    } catch {
        let stagedContent = try String(contentsOf: destinationURL, encoding: .utf8)
        #expect(stagedContent == "existing staged tool")
    }
}

@Test func `launch agent install stages default artifact when it is missing`() throws {
    let repositoryRootURL = try makeLaunchAgentCommandTestRepository()

    let command = try LaunchAgentCommand.parse(
        arguments: ["install"],
        currentDirectoryPath: repositoryRootURL.path,
        currentExecutablePath: testToolExecutablePath(in: repositoryRootURL),
    )

    switch command.action {
        case let .install(options):
            guard case let .promoteCurrentCheckout(repositoryRootPath) = options.stagedArtifactPolicy else {
                Issue.record("Expected `launch-agent install` to stage the current checkout for the default artifact path.")
                return
            }

            #expect(repositoryRootPath == repositoryRootURL.path)
            #expect(
                options.toolExecutablePath
                    == repositoryRootURL
                    .appendingPathComponent(".release-artifacts/current/SpeakSwiftlyServerTool", isDirectory: false)
                    .path,
            )

        default:
            Issue.record("Expected `launch-agent install` to parse into the install action.")
    }
}

@Test func `launch agent print plist honors explicit tool executable path without staged artifact`() throws {
    let repositoryRootURL = try makeLaunchAgentCommandTestRepository()
    let explicitToolURL = repositoryRootURL.appendingPathComponent("tmp/SpeakSwiftlyServerTool", isDirectory: false)
    try FileManager.default.createDirectory(
        at: explicitToolURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try "#!/bin/sh\nexit 0\n".write(to: explicitToolURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: explicitToolURL.path)

    let command = try LaunchAgentCommand.parse(
        arguments: ["print-plist", "--tool-executable-path", explicitToolURL.path],
        currentDirectoryPath: repositoryRootURL.path,
        currentExecutablePath: testToolExecutablePath(in: repositoryRootURL),
    )

    switch command.action {
        case let .printPlist(options):
            #expect(options.toolExecutablePath == explicitToolURL.path)

        default:
            Issue.record("Expected `launch-agent print-plist` to parse into the print-plist action.")
    }
}

@Test func `launch agent uninstall waits for delayed launchctl teardown`() throws {
    let temporaryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)

    let plistURL = temporaryRootURL.appendingPathComponent("SpeakSwiftlyServer.plist", isDirectory: false)
    try "plist".write(to: plistURL, atomically: true, encoding: .utf8)

    let serviceStateURL = temporaryRootURL.appendingPathComponent("service-loaded", isDirectory: false)
    try "loaded".write(to: serviceStateURL, atomically: true, encoding: .utf8)

    let launchctlScriptURL = temporaryRootURL.appendingPathComponent("launchctl", isDirectory: false)
    let launchctlScript = """
    #!/bin/sh
    STATE_FILE="\(serviceStateURL.path)"

    case "$1" in
      print)
        if [ -f "$STATE_FILE" ]; then
          exit 0
        fi
        exit 113
        ;;
      bootout)
        (
          sleep 0.2
          rm -f "$STATE_FILE"
        ) &
        exit 0
        ;;
      *)
        exit 64
        ;;
    esac
    """
    try launchctlScript.write(to: launchctlScriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctlScriptURL.path)

    let options = LaunchAgentStatusOptions(
        label: "com.gaelic-ghost.test-launch-agent",
        plistPath: plistURL.path,
        launchctlPath: launchctlScriptURL.path,
        userDomain: "gui/501",
    )

    try options.uninstall()

    #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
    #expect(FileManager.default.fileExists(atPath: serviceStateURL.path) == false)
}

@Test func `launch agent uninstall removes legacy staged config aliases`() throws {
    let homeDirectoryURL = try makeLaunchAgentCommandTestRepository()
    let layout = ServerInstallLayout.defaultForCurrentUser(
        homeDirectoryURL: homeDirectoryURL,
        launchAgentLabel: "com.gaelic-ghost.test-launch-agent",
    )
    let cacheAliasURL = layout.cacheDirectoryURL.appendingPathComponent("launch-agent-server.yaml", isDirectory: false)

    try FileManager.default.createDirectory(
        at: layout.launchAgentConfigAliasURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try FileManager.default.createDirectory(
        at: cacheAliasURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try FileManager.default.createDirectory(
        at: layout.launchAgentPlistURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try "aliased config".write(to: layout.launchAgentConfigAliasURL, atomically: true, encoding: .utf8)
    try "cache aliased config".write(to: cacheAliasURL, atomically: true, encoding: .utf8)
    try "plist".write(to: layout.launchAgentPlistURL, atomically: true, encoding: .utf8)

    let options = LaunchAgentStatusOptions(
        label: layout.launchAgentLabel,
        plistPath: layout.launchAgentPlistURL.path,
        launchctlPath: "/usr/bin/true",
        userDomain: "gui/501",
    )

    try options.removeStagedConfigAliasIfPresent(layout: layout)
    #expect(FileManager.default.fileExists(atPath: layout.launchAgentConfigAliasURL.path) == false)
    #expect(FileManager.default.fileExists(atPath: cacheAliasURL.path) == false)
}

@Test func `launch agent config preparation seeds missing canonical application support config`() throws {
    let homeDirectoryURL = try makeLaunchAgentCommandTestRepository()
    let layout = ServerInstallLayout(
        launchAgentLabel: "com.gaelic-ghost.test-launch-agent",
        workingDirectoryURL: homeDirectoryURL,
        applicationSupportDirectoryURL: homeDirectoryURL
            .appendingPathComponent("Library/Application Support/SpeakSwiftlyServer", isDirectory: true),
        cacheDirectoryURL: homeDirectoryURL.appendingPathComponent("Library/Caches/SpeakSwiftlyServer", isDirectory: true),
        logsDirectoryURL: homeDirectoryURL.appendingPathComponent("Library/Logs/SpeakSwiftlyServer", isDirectory: true),
        launchAgentsDirectoryURL: homeDirectoryURL.appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        launchAgentPlistURL: homeDirectoryURL
            .appendingPathComponent("Library/LaunchAgents/com.gaelic-ghost.test-launch-agent.plist", isDirectory: false),
        serverConfigFileURL: homeDirectoryURL
            .appendingPathComponent("Library/Application Support/SpeakSwiftlyServer/server.yaml", isDirectory: false),
        launchAgentConfigAliasURL: homeDirectoryURL
            .appendingPathComponent("Library/SpeakSwiftlyServer/launch-agent-server.yaml", isDirectory: false),
        runtimeBaseDirectoryURL: homeDirectoryURL
            .appendingPathComponent("Library/Application Support/SpeakSwiftlyServer/runtime", isDirectory: true),
        runtimeProfileRootURL: homeDirectoryURL
            .appendingPathComponent("Library/Application Support/SpeakSwiftlyServer/runtime/profiles", isDirectory: true),
        runtimeConfigurationFileURL: homeDirectoryURL
            .appendingPathComponent("Library/Application Support/SpeakSwiftlyServer/runtime/configuration.json", isDirectory: false),
        standardOutLogURL: homeDirectoryURL.appendingPathComponent("Library/Logs/SpeakSwiftlyServer/stdout.log"),
        standardErrorLogURL: homeDirectoryURL.appendingPathComponent("Library/Logs/SpeakSwiftlyServer/stderr.log"),
    )
    let options = try LaunchAgentOptions(
        label: layout.launchAgentLabel,
        toolExecutablePath: testToolExecutablePath(in: homeDirectoryURL),
        plistPath: layout.launchAgentPlistURL.path,
        configFilePath: layout.serverConfigFileURL.path,
        requireToolExecutableExists: false,
    )

    try options.prepareLaunchAgentConfig(layout: layout)

    let seededConfig = try String(contentsOf: layout.serverConfigFileURL, encoding: .utf8)
    #expect(seededConfig.contains("port: 7337"))
    #expect(seededConfig.contains("enabled: true"))
    #expect(options.effectiveConfigFilePath(layout: layout) == layout.serverConfigFileURL.standardizedFileURL.path)
}

@Test func `launch agent status reports explicit not loaded state`() throws {
    let temporaryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)

    let plistURL = temporaryRootURL.appendingPathComponent("SpeakSwiftlyServer.plist", isDirectory: false)
    let launchctlScriptURL = temporaryRootURL.appendingPathComponent("launchctl", isDirectory: false)
    let launchctlScript = """
    #!/bin/sh
    if [ "$1" = "print" ]; then
      echo "Could not find service" >&2
      exit 113
    fi
    exit 64
    """
    try launchctlScript.write(to: launchctlScriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctlScriptURL.path)

    let options = LaunchAgentStatusOptions(
        label: "com.gaelic-ghost.test-launch-agent",
        plistPath: plistURL.path,
        launchctlPath: launchctlScriptURL.path,
        userDomain: "gui/501",
    )

    let status = try options.statusSummary()
    #expect(status.contains("loaded: no"))
    #expect(status.contains("load_state: not_loaded"))
}

@Test func `launch agent status surfaces unexpected launchctl print failures`() throws {
    let temporaryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporaryRootURL, withIntermediateDirectories: true)

    let plistURL = temporaryRootURL.appendingPathComponent("SpeakSwiftlyServer.plist", isDirectory: false)
    let launchctlScriptURL = temporaryRootURL.appendingPathComponent("launchctl", isDirectory: false)
    let launchctlScript = """
    #!/bin/sh
    if [ "$1" = "print" ]; then
      echo "Permission denied while reading launchd state" >&2
      exit 5
    fi
    exit 64
    """
    try launchctlScript.write(to: launchctlScriptURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: launchctlScriptURL.path)

    let options = LaunchAgentStatusOptions(
        label: "com.gaelic-ghost.test-launch-agent",
        plistPath: plistURL.path,
        launchctlPath: launchctlScriptURL.path,
        userDomain: "gui/501",
    )

    do {
        _ = try options.statusSummary()
        Issue.record("Expected launch-agent status to surface an unexpected launchctl print failure.")
    } catch let error as LaunchAgentCommandError {
        #expect(error.message.contains("unexpected failure"))
        #expect(error.message.contains("Permission denied while reading launchd state"))
    }
}

@Test func `healthcheck command parses custom probe options`() throws {
    let command = try SpeakSwiftlyServerToolCommand.parse(
        arguments: [
            "healthcheck",
            "--base-url", "http://127.0.0.1:8123",
            "--mcp-path", "rpc",
            "--timeout-seconds", "5",
        ],
        currentExecutablePath: testToolExecutablePath(),
    )

    switch command {
        case let .healthcheck(options):
            #expect(options.baseURL.absoluteString == "http://127.0.0.1:8123")
            #expect(options.mcpPath == "/rpc")
            #expect(options.timeoutSeconds == 5)

        default:
            Issue.record("Expected `healthcheck` to parse into the healthcheck command.")
    }
}

@Test func `unknown top level command lists healthcheck in supported commands`() throws {
    do {
        _ = try SpeakSwiftlyServerToolCommand.parse(
            arguments: ["wat"],
            currentExecutablePath: testToolExecutablePath(),
        )
        Issue.record("Expected an unknown top-level command to fail parsing.")
    } catch let error as SpeakSwiftlyServerToolCommandError {
        #expect(error.message.contains("`serve`, `healthcheck`, and `launch-agent`"))
    }
}

private func makeLaunchAgentCommandTestRepository() throws -> URL {
    let repositoryRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: repositoryRootURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
        at: repositoryRootURL.appendingPathComponent("Sources/SpeakSwiftlyServerTool", isDirectory: true),
        withIntermediateDirectories: true,
    )
    try "import PackageDescription\nlet package = Package(name: \"SpeakSwiftlyServer\")\n"
        .write(
            to: repositoryRootURL.appendingPathComponent("Package.swift", isDirectory: false),
            atomically: true,
            encoding: .utf8,
        )
    return repositoryRootURL
}

private func testToolExecutablePath(in rootURL: URL? = nil) -> String {
    (rootURL ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true))
        .appendingPathComponent("tmp/SpeakSwiftlyServerTool", isDirectory: false)
        .path
}
