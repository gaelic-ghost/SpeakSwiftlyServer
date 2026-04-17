import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - ServerProcess

final class ServerProcess: @unchecked Sendable {
    private final class SynchronizedLogBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var lines = [String]()

        func append(_ line: String) {
            lock.withLock {
                lines.append(line)
            }
        }

        var contents: String {
            lock.withLock {
                lines.joined(separator: "\n")
            }
        }

        var snapshot: [String] {
            lock.withLock {
                lines
            }
        }

        var isEmpty: Bool {
            lock.withLock {
                lines.isEmpty
            }
        }
    }

    let baseURL: URL

    private let executionLaneLease: E2ELiveServerExecutionLaneLease
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    private let stdoutRecorder = SynchronizedLogBuffer()
    private let stderrRecorder = SynchronizedLogBuffer()

    var isStillRunning: Bool {
        process.isRunning
    }

    var combinedOutput: String {
        stdoutRecorder.contents + (stdoutRecorder.isEmpty || stderrRecorder.isEmpty ? "" : "\n") + stderrRecorder.contents
    }

    init(
        executionLaneLease: E2ELiveServerExecutionLaneLease,
        executableURL: URL,
        profileRootURL: URL,
        port: Int,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil,
    ) throws {
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw E2ETransportError("The live end-to-end suite could not construct a localhost base URL for port '\(port)'.")
        }

        self.executionLaneLease = executionLaneLease
        self.baseURL = baseURL

        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["APP_PORT"] = String(port)
        environment["SPEAKSWIFTLY_PROFILE_ROOT"] = profileRootURL.path
        environment["APP_MCP_ENABLED"] = mcpEnabled ? "true" : "false"
        environment["APP_MCP_PATH"] = "/mcp"
        environment["APP_MCP_SERVER_NAME"] = "speak-swiftly-server-e2e"
        environment["APP_MCP_TITLE"] = "SpeakSwiftlyServer E2E MCP"
        if silentPlayback {
            environment["SPEAKSWIFTLY_SILENT_PLAYBACK"] = "1"
        } else {
            environment.removeValue(forKey: "SPEAKSWIFTLY_SILENT_PLAYBACK")
        }
        if playbackTrace {
            environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] = "1"
        }
        if let speechBackend {
            environment["SPEAKSWIFTLY_SPEECH_BACKEND"] = speechBackend
        } else {
            environment.removeValue(forKey: "SPEAKSWIFTLY_SPEECH_BACKEND")
        }
        environment["DYLD_FRAMEWORK_PATH"] = executableURL.deletingLastPathComponent().path
        process.environment = environment
    }

    deinit {
        stop()
    }

    func start() throws {
        stdoutTask = captureLines(from: stdoutPipe.fileHandleForReading, recordingInto: stdoutRecorder)
        stderrTask = captureLines(from: stderrPipe.fileHandleForReading, recordingInto: stderrRecorder)
        try process.run()
    }

    func stop() {
        terminateProcessIfNeeded()
        stdoutTask?.cancel()
        stderrTask?.cancel()
        executionLaneLease.release()
    }

    func stderrObjects() -> [[String: Any]] {
        stderrRecorder.snapshot.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }

            return json as? [String: Any]
        }
    }

    func recentStructuredStderrSummary(limit: Int = 20) -> String {
        let recentLines = Array(stderrRecorder.snapshot.suffix(limit))
        guard !recentLines.isEmpty else {
            return "No stderr lines were captured from the live SpeakSwiftlyServer process."
        }

        return recentLines.joined(separator: "\n")
    }

    func waitForStderrJSONObject(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool,
    ) async throws -> [String: Any] {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(100)) {
            for line in self.stderrRecorder.snapshot {
                guard let data = line.data(using: .utf8) else { continue }
                guard let json = try? JSONSerialization.jsonObject(with: data) else { continue }
                guard let object = json as? [String: Any], predicate(object) else { continue }

                return object
            }

            guard self.isStillRunning else {
                throw E2ETransportError(
                    "The live SpeakSwiftlyServer process exited before the expected stderr JSON log was observed.\n\(self.combinedOutput)",
                )
            }

            return nil
        }
    }

    private func captureLines(
        from handle: FileHandle,
        recordingInto recorder: SynchronizedLogBuffer,
    ) -> Task<Void, Never> {
        Task {
            do {
                for try await line in handle.bytes.lines {
                    recorder.append(line)
                }
            } catch is CancellationError {
                return
            } catch {
                recorder.append(
                    "Server process log capture stopped after an unexpected stream error: \(error.localizedDescription)",
                )
            }
        }
    }

    private func terminateProcessIfNeeded() {
        guard process.isRunning else { return }

        if waitForExit(after: { process.interrupt() }, timeout: .seconds(5)) {
            return
        }
        if waitForExit(after: { process.terminate() }, timeout: .seconds(5)) {
            return
        }

#if canImport(Darwin)
        kill(process.processIdentifier, SIGKILL)
        _ = waitForExit(timeout: .seconds(2))
#endif
    }

    private func waitForExit(
        after action: () -> Void,
        timeout: Duration,
    ) -> Bool {
        action()
        return waitForExit(timeout: timeout)
    }

    private func waitForExit(timeout: Duration) -> Bool {
        guard process.isRunning else { return true }

        let semaphore = DispatchSemaphore(value: 0)
        let originalHandler = process.terminationHandler
        process.terminationHandler = { completedProcess in
            originalHandler?(completedProcess)
            semaphore.signal()
        }
        defer {
            process.terminationHandler = originalHandler
        }

        guard process.isRunning else { return true }

        let timeoutInterval =
            Double(timeout.components.seconds)
                + Double(timeout.components.attoseconds) / 1_000_000_000_000_000_000
        return semaphore.wait(timeout: .now() + timeoutInterval) == .success
    }
}

// MARK: - E2ELiveServerExecutionLaneLease

final class E2ELiveServerExecutionLaneLease: @unchecked Sendable {
    private static let lockURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("speak-swiftly-server-e2e-live-server.lock", isDirectory: false)
    private static let launchAgentLabel = "com.gaelic-ghost.speak-swiftly-server"
    private static let launchctlPath = "/bin/launchctl"
    private static let pgrepPath = "/usr/bin/pgrep"

    private var fileDescriptor: Int32?
    private let lockPath: String

    deinit {
        release()
    }

    private init(fileDescriptor: Int32, lockPath: String) {
        self.fileDescriptor = fileDescriptor
        self.lockPath = lockPath
    }

    static func acquire(timeout: Duration = .seconds(5)) throws -> E2ELiveServerExecutionLaneLease {
        try ensureLaunchAgentBackedLiveServiceIsNotLoaded()
        try ensureNoCompetingServeProcessIsRunning()

        let lockPath = lockURL.path
        let descriptor = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw E2ETransportError(
                "The live end-to-end suite could not open the exclusive server-lane lock file at '\(lockPath)'.",
            )
        }

        let timeoutNanoseconds = durationToNanoseconds(timeout)
        let pollIntervalNanoseconds: UInt64 = 100_000_000
        let deadline = DispatchTime.now().uptimeNanoseconds &+ timeoutNanoseconds

        while true {
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                return E2ELiveServerExecutionLaneLease(fileDescriptor: descriptor, lockPath: lockPath)
            }

            let currentErrno = errno
            guard currentErrno == EWOULDBLOCK else {
                close(descriptor)
                throw E2ETransportError(
                    "The live end-to-end suite could not acquire the exclusive server-lane lock at '\(lockPath)' because `flock` failed with errno \(currentErrno).",
                )
            }

            if DispatchTime.now().uptimeNanoseconds >= deadline {
                close(descriptor)
                throw E2ETransportError(
                    """
                    The live end-to-end suite waited more than \(durationDescription(timeout)) for the exclusive server-lane lock at '\(lockPath)'.
                    Another live end-to-end test process is already holding the lane.
                    Run live end-to-end coverage in one foreground process at a time, and do not overlap HTTP, MCP, or control-suite reruns.
                    """,
                )
            }

            usleep(UInt32(pollIntervalNanoseconds / 1000))
        }
    }

    func release() {
        guard let fileDescriptor else { return }

        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
        self.fileDescriptor = nil
    }

    private static func ensureLaunchAgentBackedLiveServiceIsNotLoaded() throws {
        let userDomain = "gui/\(getuid())"
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: launchctlPath),
            arguments: ["print", "\(userDomain)/\(launchAgentLabel)"],
            allowNonZeroExit: true,
            failureSummary: "The live end-to-end suite could not inspect the LaunchAgent-backed SpeakSwiftlyServer service state.",
        )

        guard result.exitCode != 0 else {
            throw E2ETransportError(
                """
                The LaunchAgent-backed live SpeakSwiftlyServer service '\(launchAgentLabel)' is still loaded in '\(userDomain)'.
                Live end-to-end coverage must run without the always-on service active, or the machine can end up speaking from two different server processes at once.
                Stop it first with `./.release-artifacts/current/SpeakSwiftlyServerTool launch-agent uninstall` and then rerun the end-to-end command.
                """,
            )
        }
    }

    private static func ensureNoCompetingServeProcessIsRunning() throws {
        let result = try runProcess(
            executableURL: URL(fileURLWithPath: pgrepPath),
            arguments: ["-fl", "SpeakSwiftlyServerTool serve"],
            allowNonZeroExit: true,
            failureSummary: "The live end-to-end suite could not inspect the current process table for competing SpeakSwiftlyServerTool serve processes.",
        )

        let currentProcessIdentifier = String(ProcessInfo.processInfo.processIdentifier)
        let competingProcesses = result.standardOutput
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                line.contains("SpeakSwiftlyServerTool serve") && !line.hasPrefix(currentProcessIdentifier + " ")
            }

        guard competingProcesses.isEmpty else {
            let processSummary = competingProcesses.joined(separator: "\n")
            throw E2ETransportError(
                """
                The live end-to-end suite found an existing `SpeakSwiftlyServerTool serve` process before it could start its own helper.
                Live end-to-end coverage must own the only speaking server process on the machine while it runs.
                Existing processes:
                \(processSummary)
                """,
            )
        }
    }
}

private func durationToNanoseconds(_ duration: Duration) -> UInt64 {
    let seconds = UInt64(max(duration.components.seconds, 0))
    let attoseconds = UInt64(max(duration.components.attoseconds, 0))
    return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
}

private func durationDescription(_ duration: Duration) -> String {
    if duration.components.attoseconds == 0 {
        return "\(duration.components.seconds) second(s)"
    }

    let fractionalSeconds = Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    return String(format: "%.2f second(s)", fractionalSeconds)
}

private struct E2EProcessExecutionResult {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

@discardableResult
private func runProcess(
    executableURL: URL,
    arguments: [String],
    allowNonZeroExit: Bool,
    failureSummary: String,
) throws -> E2EProcessExecutionResult {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments

    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        throw E2ETransportError("\(failureSummary) Likely cause: \(error.localizedDescription)")
    }

    let result = E2EProcessExecutionResult(
        exitCode: process.terminationStatus,
        standardOutput: String(decoding: standardOutput.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines),
        standardError: String(decoding: standardError.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines),
    )

    if !allowNonZeroExit, result.exitCode != 0 {
        throw E2ETransportError(
            "\(failureSummary) The helper process exited with status \(result.exitCode). stderr: \(result.standardError)",
        )
    }

    return result
}
