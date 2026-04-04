import Foundation
import Testing

@Suite(.serialized)
struct SpeakSwiftlyServerE2ETests {
    private static let profileName = "e2e-voice"
    private static let profileText = "Hello there from the SpeakSwiftlyServer live HTTP end-to-end test."
    private static let voiceDescription = "A calm, warm, steady speaking voice."
    private static let playbackText = """
    Hello from the live SpeakSwiftlyServer end-to-end path. This request exercises the real localhost HTTP surface, the direct SpeakSwiftlyCore runtime, profile reconciliation, queued live speech submission, and terminal job capture without falling back to the mock runtime.
    """

    @Test func liveServerRunsCreateProfileAndQueuedSpeechEndToEnd() async throws {
        guard Self.isE2EEnabled else { return }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let dependencyProductsURL = try Self.speakSwiftlyProductsURL()
        let serverExecutableURL = try Self.serverExecutableURL()
        try Self.stageMetallibForServerBinary(
            from: dependencyProductsURL,
            serverExecutableURL: serverExecutableURL
        )

        let port = 59_000 + Int.random(in: 0..<500)
        let client = E2EHTTPClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let server = try ServerProcess(
            executableURL: serverExecutableURL,
            dependencyProductsURL: dependencyProductsURL,
            profileRootURL: sandbox.profileRootURL,
            port: port,
            silentPlayback: true
        )

        try server.start()
        defer { server.stop() }

        do {
            try await waitUntilWorkerReady(using: client, timeout: .seconds(180), server: server)

            let createResponse = try await client.request(
                path: "/profiles",
                method: "POST",
                jsonBody: [
                    "profile_name": Self.profileName,
                    "text": Self.profileText,
                    "voice_description": Self.voiceDescription,
                ]
            )
            #expect(createResponse.statusCode == 202)

            let createJobID = try decode(E2EJobCreatedResponse.self, from: createResponse.data).jobID
            let createSnapshot = try await waitForTerminalJob(
                id: createJobID,
                using: client,
                timeout: .seconds(240),
                server: server
            )
            #expect(createSnapshot.status == "completed")
            #expect(createSnapshot.terminalEvent?.ok == true)

            let profilesResponse = try await client.request(path: "/profiles", method: "GET")
            #expect(profilesResponse.statusCode == 200)
            let profiles = try decode(E2EProfileListResponse.self, from: profilesResponse.data).profiles
            #expect(profiles.contains { $0.profileName == Self.profileName })

            let foregroundSpeakResponse = try await client.request(
                path: "/speak",
                method: "POST",
                jsonBody: [
                    "text": Self.playbackText,
                    "profile_name": Self.profileName,
                ]
            )
            #expect(foregroundSpeakResponse.statusCode == 202)

            let foregroundSpeakJobID = try decode(E2EJobCreatedResponse.self, from: foregroundSpeakResponse.data).jobID
            let foregroundSpeakSnapshot = try await waitForTerminalJob(
                id: foregroundSpeakJobID,
                using: client,
                timeout: .seconds(240),
                server: server
            )
            #expect(foregroundSpeakSnapshot.status == "completed")
            #expect(foregroundSpeakSnapshot.terminalEvent?.ok == true)
            #expect(foregroundSpeakSnapshot.history.filter { $0.ok == true }.count == 2)

            let foregroundEventsResponse = try await client.request(
                path: "/jobs/\(foregroundSpeakJobID)/events",
                method: "GET"
            )
            #expect(foregroundEventsResponse.statusCode == 200)
            #expect(foregroundEventsResponse.text.contains("event: worker_status"))
            #expect(foregroundEventsResponse.text.contains(#""event":"started""#))
            #expect(foregroundEventsResponse.text.contains(#""ok":true"#))
            #expect(!foregroundEventsResponse.text.contains(#""event":"queued""#))

        } catch {
            Issue.record("Live server log output before failure:\n\(server.combinedOutput)")
            throw error
        }
    }

    @Test func liveServerRunsForegroundPlaybackEndToEndWithRealPlaybackPath() async throws {
        guard Self.isE2EEnabled, Self.isRealPlaybackE2EEnabled else { return }

        let sandbox = try ServerE2ESandbox()
        defer { sandbox.cleanup() }

        let dependencyProductsURL = try Self.speakSwiftlyProductsURL()
        let serverExecutableURL = try Self.serverExecutableURL()
        try Self.stageMetallibForServerBinary(
            from: dependencyProductsURL,
            serverExecutableURL: serverExecutableURL
        )

        let port = 59_500 + Int.random(in: 0..<400)
        let client = E2EHTTPClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!)
        let server = try ServerProcess(
            executableURL: serverExecutableURL,
            dependencyProductsURL: dependencyProductsURL,
            profileRootURL: sandbox.profileRootURL,
            port: port,
            silentPlayback: false,
            playbackTrace: Self.isPlaybackTraceEnabled
        )

        try server.start()
        defer { server.stop() }

        do {
            try await waitUntilWorkerReady(using: client, timeout: .seconds(180), server: server)

            let engineReadyLog = try await server.waitForStderrLine(timeout: .seconds(60)) { line in
                line.contains(#""event":"playback_engine_ready""#)
                    && line.contains(#""process_phys_footprint_bytes""#)
                    && line.contains(#""mlx_active_memory_bytes""#)
            }
            #expect(engineReadyLog.contains(#""event":"playback_engine_ready""#))

            let createResponse = try await client.request(
                path: "/profiles",
                method: "POST",
                jsonBody: [
                    "profile_name": Self.profileName,
                    "text": Self.profileText,
                    "voice_description": Self.voiceDescription,
                ]
            )
            #expect(createResponse.statusCode == 202)

            let createJobID = try decode(E2EJobCreatedResponse.self, from: createResponse.data).jobID
            let createSnapshot = try await waitForTerminalJob(
                id: createJobID,
                using: client,
                timeout: .seconds(240),
                server: server
            )
            #expect(createSnapshot.terminalEvent?.ok == true)

            let foregroundSpeakResponse = try await client.request(
                path: "/speak",
                method: "POST",
                jsonBody: [
                    "text": Self.playbackText,
                    "profile_name": Self.profileName,
                ]
            )
            #expect(foregroundSpeakResponse.statusCode == 202)

            let foregroundSpeakJobID = try decode(E2EJobCreatedResponse.self, from: foregroundSpeakResponse.data).jobID

            let playbackStartedLog = try await server.waitForStderrLine(timeout: .seconds(240)) { line in
                line.contains(#""event":"playback_started""#)
                    && line.contains(#""request_id":"\#(foregroundSpeakJobID)""#)
                    && line.contains(#""text_complexity_class""#)
            }
            #expect(playbackStartedLog.contains(#""event":"playback_started""#))

            let playbackFinishedLog = try await server.waitForStderrLine(timeout: .seconds(240)) { line in
                line.contains(#""event":"playback_finished""#)
                    && line.contains(#""request_id":"\#(foregroundSpeakJobID)""#)
                    && line.contains(#""time_to_first_chunk_ms""#)
                    && line.contains(#""played_back_callback_count""#)
            }
            #expect(playbackFinishedLog.contains(#""event":"playback_finished""#))

            let foregroundSpeakSnapshot = try await waitForTerminalJob(
                id: foregroundSpeakJobID,
                using: client,
                timeout: .seconds(240),
                server: server
            )
            #expect(foregroundSpeakSnapshot.status == "completed")
            #expect(foregroundSpeakSnapshot.terminalEvent?.ok == true)
            #expect(foregroundSpeakSnapshot.history.filter { $0.ok == true }.count == 2)
        } catch {
            Issue.record("Live server log output before failure:\n\(server.combinedOutput)")
            throw error
        }
    }

    private static var isE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1"
    }

    private static var isRealPlaybackE2EEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E_REAL_PLAYBACK"] == "1"
    }

    private static var isPlaybackTraceEnabled: Bool {
        ProcessInfo.processInfo.environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] == "1"
    }

    private static func speakSwiftlyProductsURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productsURL = serverRootURL
            .deletingLastPathComponent()
            .appendingPathComponent("SpeakSwiftly/.derived/Build/Products/Debug", isDirectory: true)

        let metallibURL = productsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)
        guard FileManager.default.fileExists(atPath: metallibURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The live HTTP end-to-end test requires the Xcode-built SpeakSwiftly products at '\(productsURL.path)'. Build ../SpeakSwiftly with Xcode first so `default.metallib` is available."
            )
        }
        return productsURL
    }

    private static func serverExecutableURL() throws -> URL {
        let serverRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let executableURL = serverRootURL
            .appendingPathComponent(".build/arm64-apple-macosx/debug/SpeakSwiftlyServer", isDirectory: false)

        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw SpeakSwiftlyBuildError(
                "The SpeakSwiftlyServer executable was expected at '\(executableURL.path)', but it was not present. Run `swift build` before the live HTTP end-to-end test."
            )
        }
        return executableURL
    }

    private static func stageMetallibForServerBinary(
        from dependencyProductsURL: URL,
        serverExecutableURL: URL
    ) throws {
        let sourceURL = dependencyProductsURL
            .appendingPathComponent("mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib", isDirectory: false)
        let targetDirectoryURL = serverExecutableURL
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let targetURL = targetDirectoryURL.appendingPathComponent("default.metallib", isDirectory: false)

        try FileManager.default.createDirectory(at: targetDirectoryURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
    }
}

private struct ServerE2ESandbox {
    let rootURL: URL
    let profileRootURL: URL

    init() throws {
        rootURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SpeakSwiftlyServer-E2E-\(UUID().uuidString)", isDirectory: true)
        profileRootURL = rootURL.appendingPathComponent("profiles", isDirectory: true)

        try FileManager.default.createDirectory(at: profileRootURL, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private final class ServerProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    init(
        executableURL: URL,
        dependencyProductsURL: URL,
        profileRootURL: URL,
        port: Int,
        silentPlayback: Bool,
        playbackTrace: Bool = false
    ) throws {
        process.executableURL = executableURL
        process.currentDirectoryURL = executableURL.deletingLastPathComponent()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var environment = ProcessInfo.processInfo.environment
        environment["APP_PORT"] = String(port)
        environment["SPEAKSWIFTLY_PROFILE_ROOT"] = profileRootURL.path
        if silentPlayback {
            environment["SPEAKSWIFTLY_SILENT_PLAYBACK"] = "1"
        } else {
            environment.removeValue(forKey: "SPEAKSWIFTLY_SILENT_PLAYBACK")
        }
        if playbackTrace {
            environment["SPEAKSWIFTLY_PLAYBACK_TRACE"] = "1"
        }
        environment["DYLD_FRAMEWORK_PATH"] = dependencyProductsURL.path
        process.environment = environment
    }

    func start() throws {
        stdoutTask = captureLines(from: stdoutPipe.fileHandleForReading, recordingInto: stdoutRecorder)
        stderrTask = captureLines(from: stderrPipe.fileHandleForReading, recordingInto: stderrRecorder)
        try process.run()
    }

    func stop() {
        if process.isRunning {
            process.interrupt()
            process.waitUntilExit()
        }
        stdoutTask?.cancel()
        stderrTask?.cancel()
    }

    var isStillRunning: Bool {
        process.isRunning
    }

    var combinedOutput: String {
        stdoutRecorder.contents + (stdoutRecorder.isEmpty || stderrRecorder.isEmpty ? "" : "\n") + stderrRecorder.contents
    }

    private func captureLines(
        from handle: FileHandle,
        recordingInto recorder: SynchronizedLogBuffer
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
                    "Server process log capture stopped after an unexpected stream error: \(error.localizedDescription)"
                )
            }
        }
    }

    func waitForStderrLine(
        timeout: Duration,
        matching predicate: @escaping @Sendable (String) -> Bool
    ) async throws -> String {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(100)) {
            for line in self.stderrRecorder.snapshot where predicate(line) {
                return line
            }
            guard self.isStillRunning else {
                throw E2EHTTPError("The live SpeakSwiftlyServer process exited before the expected stderr playback log was observed.\n\(self.combinedOutput)")
            }
            return nil
        }
    }

    private let stdoutRecorder = SynchronizedLogBuffer()
    private let stderrRecorder = SynchronizedLogBuffer()

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
}

private struct E2EHTTPClient {
    let baseURL: URL

    func request(
        path: String,
        method: String,
        jsonBody: [String: String]? = nil
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2EHTTPError("The live HTTP end-to-end request to '\(path)' did not return an HTTPURLResponse.")
        }
        return E2EHTTPResponse(statusCode: httpResponse.statusCode, data: data)
    }
}

private struct E2EHTTPResponse {
    let statusCode: Int
    let data: Data

    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

private func waitUntilWorkerReady(
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2EHTTPError("The live SpeakSwiftlyServer process exited before `/readyz` reported readiness.\n\(server.combinedOutput)")
        }

        let response: E2EHTTPResponse
        do {
            response = try await client.request(path: "/readyz", method: "GET")
        } catch {
            guard isRetryableConnectionDuringStartup(error) else {
                throw error
            }
            return nil
        }
        guard response.statusCode == 200 else { return nil }
        let readiness = try decode(E2EReadinessSnapshot.self, from: response.data)
        return readiness.workerReady ? true : nil
    }
}

private func waitForTerminalJob(
    id jobID: String,
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2EHTTPError("The live SpeakSwiftlyServer process exited before job '\(jobID)' reached a terminal state.\n\(server.combinedOutput)")
        }

        let response = try await client.request(path: "/jobs/\(jobID)", method: "GET")
        guard response.statusCode == 200 else { return nil }
        let snapshot = try decode(E2EJobSnapshot.self, from: response.data)
        return snapshot.terminalEvent == nil ? nil : snapshot
    }
}

private func e2eWaitUntil<T: Sendable>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping @Sendable () async throws -> T?
) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(for: pollInterval)
    }
    throw E2ETimeoutError()
}

private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try JSONDecoder().decode(Value.self, from: data)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private struct E2ETimeoutError: Error {}
private struct E2EHTTPError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct SpeakSwiftlyBuildError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func isRetryableConnectionDuringStartup(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    return nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorNetworkConnectionLost
}

private struct E2EReadinessSnapshot: Decodable, Sendable {
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case workerReady = "worker_ready"
    }
}

private struct E2EJobCreatedResponse: Decodable, Sendable {
    let jobID: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
    }
}

private struct E2EProfileListResponse: Decodable, Sendable {
    let profiles: [E2EProfileSnapshot]
}

private struct E2EProfileSnapshot: Decodable, Sendable {
    let profileName: String

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
    }
}

private struct E2EJobSnapshot: Decodable, Sendable {
    let status: String
    let history: [E2EHistoryEvent]
    let terminalEvent: E2ESuccessEvent?

    enum CodingKeys: String, CodingKey {
        case status
        case history
        case terminalEvent = "terminal_event"
    }
}

private struct E2EHistoryEvent: Decodable, Sendable {
    let ok: Bool?
}

private struct E2ESuccessEvent: Decodable, Sendable {
    let id: String
    let ok: Bool
}
