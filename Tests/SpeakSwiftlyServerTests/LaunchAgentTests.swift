import Foundation
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Launch Agent Command Tests

@Test func `launch agent promote live parses without preexisting staged executable`() throws {
    let repositoryRootURL = try makeLaunchAgentCommandTestRepository()

    let command = try LaunchAgentCommand.parse(
        arguments: ["promote-live"],
        currentDirectoryPath: repositoryRootURL.path,
        currentExecutablePath: "/tmp/SpeakSwiftlyServerTool",
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

@Test func `launch agent install still rejects missing staged executable by default`() throws {
    let repositoryRootURL = try makeLaunchAgentCommandTestRepository()

    do {
        _ = try LaunchAgentCommand.parse(
            arguments: ["install"],
            currentDirectoryPath: repositoryRootURL.path,
            currentExecutablePath: "/tmp/SpeakSwiftlyServerTool",
        )
        Issue.record("Expected `launch-agent install` to reject a missing staged executable.")
    } catch let error as LaunchAgentCommandError {
        #expect(error.message.contains("could not find the staged release artifact"))
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
        currentExecutablePath: "/tmp/SpeakSwiftlyServerTool",
    )

    switch command.action {
        case let .printPlist(options):
            #expect(options.toolExecutablePath == explicitToolURL.path)

        default:
            Issue.record("Expected `launch-agent print-plist` to parse into the print-plist action.")
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
        currentExecutablePath: "/tmp/SpeakSwiftlyServerTool",
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
            currentExecutablePath: "/tmp/SpeakSwiftlyServerTool",
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
