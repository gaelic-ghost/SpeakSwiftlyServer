import Foundation
@testable import SpeakSwiftlyServer
@testable import SpeakSwiftlyServerTool
import Testing

// MARK: - Tool Tests

@Test func `tool parses launch agent install and defaults to staged release artifact`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let currentDirectory = tempDirectory.path
    try FileManager.default.createDirectory(
        at: tempDirectory.appendingPathComponent("Sources/SpeakSwiftlyServerTool", isDirectory: true),
        withIntermediateDirectories: true,
    )
    try "// test package\n".write(
        to: tempDirectory.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8,
    )

    let stagedToolURL = tempDirectory
        .appendingPathComponent(".release-artifacts/current", isDirectory: true)
        .appendingPathComponent("SpeakSwiftlyServerTool")
    try FileManager.default.createDirectory(at: stagedToolURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: stagedToolURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagedToolURL.path)

    let currentToolURL = tempDirectory.appendingPathComponent("bin/SpeakSwiftlyServerTool")
    try FileManager.default.createDirectory(at: currentToolURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: currentToolURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentToolURL.path)

    let command = try SpeakSwiftlyServerToolCommand.parse(
        arguments: [
            "launch-agent",
            "install",
            "--config-file", "./server.yaml",
            "--reload-interval-seconds", "2",
        ],
        currentDirectoryPath: currentDirectory,
        currentExecutablePath: currentToolURL.path,
    )

    guard case let .launchAgent(launchAgentCommand) = command,
          case let .install(options) = launchAgentCommand.action else {
        Issue.record("Expected the tool parser to produce a launch-agent install command.")
        return
    }

    #expect(options.toolExecutablePath == stagedToolURL.path)
    #expect(options.configFilePath == tempDirectory.appendingPathComponent("server.yaml").path)
    #expect(options.reloadIntervalSeconds == "2")
    guard case let .promoteCurrentCheckout(repositoryRootPath) = options.stagedArtifactPolicy else {
        Issue.record("Expected launch-agent install to stage the current checkout when using the default release artifact.")
        return
    }

    #expect(repositoryRootPath == tempDirectory.path)
}

@Test func `tool parses serve config file and profile root options`() throws {
    let tempDirectory = try makeTemporaryDirectory()

    let command = try SpeakSwiftlyServerToolCommand.parse(
        arguments: ["serve", "--config-file", "./config/server.yaml", "--profile-root", "./runtime/profiles"],
        currentDirectoryPath: tempDirectory.path,
    )

    guard case let .serve(options) = command else {
        Issue.record("Expected the tool parser to produce a serve command.")
        return
    }

    #expect(
        options.configFilePath
            == tempDirectory.appendingPathComponent("config/server.yaml").standardizedFileURL.path,
    )
    #expect(
        options.runtimeProfileRootPath
            == tempDirectory.appendingPathComponent("runtime/profiles").standardizedFileURL.path,
    )
}

@Test func `tool treats bare serve options as serve command`() throws {
    let tempDirectory = try makeTemporaryDirectory()

    let command = try SpeakSwiftlyServerToolCommand.parse(
        arguments: ["--profile-root", "./runtime/profiles"],
        currentDirectoryPath: tempDirectory.path,
    )

    guard case let .serve(options) = command else {
        Issue.record("Expected bare serve options to parse as the serve command.")
        return
    }

    #expect(
        options.configFilePath == nil,
    )
    #expect(
        options.runtimeProfileRootPath
            == tempDirectory.appendingPathComponent("runtime/profiles").standardizedFileURL.path,
    )
}

@Test func `tool parses install when staged release artifact is missing`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    try FileManager.default.createDirectory(
        at: tempDirectory.appendingPathComponent("Sources/SpeakSwiftlyServerTool", isDirectory: true),
        withIntermediateDirectories: true,
    )
    try "// test package\n".write(
        to: tempDirectory.appendingPathComponent("Package.swift"),
        atomically: true,
        encoding: .utf8,
    )

    let currentToolURL = tempDirectory.appendingPathComponent("bin/SpeakSwiftlyServerTool")
    try FileManager.default.createDirectory(at: currentToolURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "#!/bin/sh\nexit 0\n".write(to: currentToolURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: currentToolURL.path)

    let command = try SpeakSwiftlyServerToolCommand.parse(
        arguments: ["launch-agent", "install"],
        currentDirectoryPath: tempDirectory.path,
        currentExecutablePath: currentToolURL.path,
    )

    guard case let .launchAgent(launchAgentCommand) = command,
          case let .install(options) = launchAgentCommand.action,
          case let .promoteCurrentCheckout(repositoryRootPath) = options.stagedArtifactPolicy else {
        Issue.record("Expected launch-agent install to stage the current checkout instead of requiring a preexisting staged executable.")
        return
    }

    #expect(repositoryRootPath == tempDirectory.path)
    #expect(
        options.toolExecutablePath
            == tempDirectory
            .appendingPathComponent(".release-artifacts/current/SpeakSwiftlyServerTool", isDirectory: false)
            .path,
    )
}

@Test func `launch agent property list includes serve command and environment overrides`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let executableURL = tempDirectory.appendingPathComponent("SpeakSwiftlyServerTool")
    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let options = try LaunchAgentOptions(
        toolExecutablePath: executableURL.path,
        plistPath: tempDirectory.appendingPathComponent("agent.plist").path,
        configFilePath: tempDirectory.appendingPathComponent("config/server.yaml").path,
        reloadIntervalSeconds: "0.5",
        workingDirectory: tempDirectory.path,
        profileRootPath: tempDirectory.appendingPathComponent("runtime/profiles").path,
        standardOutPath: tempDirectory.appendingPathComponent("logs/stdout.log").path,
        standardErrorPath: tempDirectory.appendingPathComponent("logs/stderr.log").path,
    )

    let propertyList = options.propertyList()
    let arguments = try #require(propertyList["ProgramArguments"] as? [String])
    let environment = try #require(propertyList["EnvironmentVariables"] as? [String: String])

    #expect(arguments == [
        executableURL.path,
        "serve",
        "--default-profile",
        "launch-agent",
        "--config-file",
        tempDirectory.appendingPathComponent("config/server.yaml").path,
        "--profile-root",
        tempDirectory.appendingPathComponent("runtime/profiles").path,
    ])
    #expect(propertyList["RunAtLoad"] as? Bool == true)
    #expect(propertyList["KeepAlive"] as? Bool == true)
    #expect(environment["APP_CONFIG_RELOAD_INTERVAL_SECONDS"] == "0.5")
    #expect(environment["APP_CONFIG_FILE"] == nil)
    #expect(environment["SPEAKSWIFTLY_PROFILE_ROOT"] == nil)
}

@Test func `launch agent install writes plist and bootstraps service`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let executableURL = tempDirectory.appendingPathComponent("SpeakSwiftlyServerTool")
    let plistURL = tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist")
    let logURL = tempDirectory.appendingPathComponent("launchctl.log")
    let stateURL = tempDirectory.appendingPathComponent("launchctl.state")
    let fakeLaunchctlURL = tempDirectory.appendingPathComponent("launchctl")

    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    let configURL = tempDirectory.appendingPathComponent("config/server.yaml", isDirectory: false)
    try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "app:\n  port: 7337\n".write(to: configURL, atomically: true, encoding: .utf8)

    let fakeLaunchctlScript = """
    #!/bin/sh
    set -eu
    printf '%s\\n' "$*" >> "\(logURL.path)"
    command="$1"
    shift
    case "$command" in
      print)
        if [ -f "\(stateURL.path)" ]; then
          printf 'loaded\\n'
          exit 0
        fi
        printf 'not loaded\\n' >&2
        exit 113
        ;;
      bootstrap)
        : > "\(stateURL.path)"
        exit 0
        ;;
      bootout)
        rm -f "\(stateURL.path)"
        exit 0
        ;;
    esac
    """
    try fakeLaunchctlScript.write(to: fakeLaunchctlURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeLaunchctlURL.path)

    let options = try LaunchAgentOptions(
        label: "com.example.test",
        toolExecutablePath: executableURL.path,
        plistPath: plistURL.path,
        configFilePath: configURL.path,
        workingDirectory: tempDirectory.path,
        profileRootPath: tempDirectory.appendingPathComponent("runtime/profiles").path,
        standardOutPath: tempDirectory.appendingPathComponent("logs/stdout.log").path,
        standardErrorPath: tempDirectory.appendingPathComponent("logs/stderr.log").path,
        launchctlPath: fakeLaunchctlURL.path,
        userDomain: "gui/501",
    )

    try options.install()

    #expect(FileManager.default.fileExists(atPath: plistURL.path))
    let launchctlLog = try String(contentsOf: logURL, encoding: .utf8)
    #expect(launchctlLog.contains("print gui/501/com.example.test"))
    #expect(launchctlLog.contains("bootstrap gui/501 \(plistURL.path)"))
}

@Test func `launch agent install validates explicit config before staging default artifact`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let executableURL = tempDirectory.appendingPathComponent("SpeakSwiftlyServerTool")
    let plistURL = tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist")
    let missingConfigURL = tempDirectory.appendingPathComponent("config/missing-server.yaml", isDirectory: false)

    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

    let stagingProbe = StagingProbe()
    let options = try LaunchAgentOptions(
        label: "com.example.test",
        toolExecutablePath: executableURL.path,
        plistPath: plistURL.path,
        configFilePath: missingConfigURL.path,
        workingDirectory: tempDirectory.path,
        profileRootPath: tempDirectory.appendingPathComponent("runtime/profiles").path,
        standardOutPath: tempDirectory.appendingPathComponent("logs/stdout.log").path,
        standardErrorPath: tempDirectory.appendingPathComponent("logs/stderr.log").path,
        launchctlPath: "/usr/bin/false",
        userDomain: "gui/501",
        stagedArtifactPolicy: .custom {
            stagingProbe.markStaged()
            return ReleaseArtifactPromotionResult(
                builtExecutablePath: executableURL.path,
                stagedExecutablePath: executableURL.path,
                stagedMetallibPath: executableURL.path,
            )
        },
    )

    do {
        try options.install()
        Issue.record("Expected launch-agent install to reject a missing explicit config file before staging.")
    } catch let error as LaunchAgentCommandError {
        #expect(error.message.contains("explicit config file"))
        #expect(error.message.contains(missingConfigURL.path))
    }

    #expect(stagingProbe.didStageArtifact == false)
    #expect(FileManager.default.fileExists(atPath: plistURL.path) == false)
}

@Test func `launch agent install waits for bootout and retries bootstrap race`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let executableURL = tempDirectory.appendingPathComponent("SpeakSwiftlyServerTool")
    let plistURL = tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist")
    let logURL = tempDirectory.appendingPathComponent("launchctl.log")
    let stateURL = tempDirectory.appendingPathComponent("launchctl.state")
    let pendingRemovalURL = tempDirectory.appendingPathComponent("launchctl.pending-removal")
    let bootstrapAttemptsURL = tempDirectory.appendingPathComponent("launchctl.bootstrap-attempts")
    let fakeLaunchctlURL = tempDirectory.appendingPathComponent("launchctl")

    try "#!/bin/sh\nexit 0\n".write(to: executableURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
    try Data().write(to: stateURL)
    let configURL = tempDirectory.appendingPathComponent("config/server.yaml", isDirectory: false)
    try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "app:\n  port: 7337\n".write(to: configURL, atomically: true, encoding: .utf8)

    let fakeLaunchctlScript = """
    #!/bin/sh
    set -eu
    printf '%s\\n' "$*" >> "\(logURL.path)"
    command="$1"
    shift
    case "$command" in
      print)
        if [ -f "\(stateURL.path)" ]; then
          if [ -f "\(pendingRemovalURL.path)" ]; then
            rm -f "\(stateURL.path)" "\(pendingRemovalURL.path)"
          fi
          printf 'loaded\\n'
          exit 0
        fi
        printf 'not loaded\\n' >&2
        exit 113
        ;;
      bootout)
        : > "\(pendingRemovalURL.path)"
        exit 0
        ;;
      bootstrap)
        count=0
        if [ -f "\(bootstrapAttemptsURL.path)" ]; then
          count=$(cat "\(bootstrapAttemptsURL.path)")
        fi
        count=$((count + 1))
        printf '%s' "$count" > "\(bootstrapAttemptsURL.path)"
        if [ "$count" -eq 1 ]; then
          printf 'Bootstrap failed: 37: Operation already in progress\\n' >&2
          exit 5
        fi
        : > "\(stateURL.path)"
        exit 0
        ;;
    esac
    """
    try fakeLaunchctlScript.write(to: fakeLaunchctlURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeLaunchctlURL.path)

    let options = try LaunchAgentOptions(
        label: "com.example.test",
        toolExecutablePath: executableURL.path,
        plistPath: plistURL.path,
        configFilePath: configURL.path,
        workingDirectory: tempDirectory.path,
        profileRootPath: tempDirectory.appendingPathComponent("runtime/profiles").path,
        standardOutPath: tempDirectory.appendingPathComponent("logs/stdout.log").path,
        standardErrorPath: tempDirectory.appendingPathComponent("logs/stderr.log").path,
        launchctlPath: fakeLaunchctlURL.path,
        userDomain: "gui/501",
    )

    try options.install()

    #expect(FileManager.default.fileExists(atPath: plistURL.path))
    let launchctlLog = try String(contentsOf: logURL, encoding: .utf8)
    #expect(launchctlLog.contains("bootout gui/501/com.example.test"))
    #expect(launchctlLog.contains("bootstrap gui/501 \(plistURL.path)"))
    let bootstrapAttempts = try String(contentsOf: bootstrapAttemptsURL, encoding: .utf8)
    #expect(bootstrapAttempts == "2")
}

@Test func `launch agent uninstall boots out loaded service and removes plist`() throws {
    let tempDirectory = try makeTemporaryDirectory()
    let plistURL = tempDirectory.appendingPathComponent("LaunchAgents/com.example.test.plist")
    let logURL = tempDirectory.appendingPathComponent("launchctl.log")
    let stateURL = tempDirectory.appendingPathComponent("launchctl.state")
    let fakeLaunchctlURL = tempDirectory.appendingPathComponent("launchctl")

    try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "plist".write(to: plistURL, atomically: true, encoding: .utf8)
    try Data().write(to: stateURL)

    let fakeLaunchctlScript = """
    #!/bin/sh
    set -eu
    printf '%s\\n' "$*" >> "\(logURL.path)"
    command="$1"
    shift
    case "$command" in
      print)
        if [ -f "\(stateURL.path)" ]; then
          printf 'loaded\\n'
          exit 0
        fi
        printf 'not loaded\\n' >&2
        exit 113
        ;;
      bootout)
        rm -f "\(stateURL.path)"
        exit 0
        ;;
    esac
    """
    try fakeLaunchctlScript.write(to: fakeLaunchctlURL, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeLaunchctlURL.path)

    let options = LaunchAgentStatusOptions(
        label: "com.example.test",
        plistPath: plistURL.path,
        launchctlPath: fakeLaunchctlURL.path,
        userDomain: "gui/501",
    )

    try options.uninstall()

    #expect(!FileManager.default.fileExists(atPath: plistURL.path))
    let launchctlLog = try String(contentsOf: logURL, encoding: .utf8)
    #expect(launchctlLog.contains("print gui/501/com.example.test"))
    #expect(launchctlLog.contains("bootout gui/501/com.example.test"))
}

// MARK: - Helpers

private func makeTemporaryDirectory() throws -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private final class StagingProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var staged = false

    var didStageArtifact: Bool {
        lock.withLock { staged }
    }

    func markStaged() {
        lock.withLock {
            staged = true
        }
    }
}
