import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - End-to-End Helpers

enum E2ETransport: Sendable {
    case http
    case mcp

    var profilePrefix: String {
        switch self {
        case .http:
            "http"
        case .mcp:
            "mcp"
        }
    }
}

enum CloneTranscriptMode: Sendable {
    case provided
    case inferred

    var slug: String {
        switch self {
        case .provided:
            "provided-transcript"
        case .inferred:
            "inferred-transcript"
        }
    }

    var providedTranscript: String? {
        switch self {
        case .provided:
            SpeakSwiftlyServerE2ETests.testingCloneSourceText
        case .inferred:
            nil
        }
    }

    var expectTranscription: Bool {
        switch self {
        case .provided:
            false
        case .inferred:
            true
        }
    }
}

struct ServerE2ESandbox {
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

// MARK: - Live Server Process

final class ServerProcess: @unchecked Sendable {
    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private var stdoutTask: Task<Void, Never>?
    private var stderrTask: Task<Void, Never>?

    let baseURL: URL

    init(
        executableURL: URL,
        profileRootURL: URL,
        port: Int,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil
    ) throws {
        guard let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            throw E2ETransportError("The live end-to-end suite could not construct a localhost base URL for port '\(port)'.")
        }
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

    func start() throws {
        stdoutTask = captureLines(from: stdoutPipe.fileHandleForReading, recordingInto: stdoutRecorder)
        stderrTask = captureLines(from: stderrPipe.fileHandleForReading, recordingInto: stderrRecorder)
        try process.run()
    }

    func stop() {
        terminateProcessIfNeeded()
        stdoutTask?.cancel()
        stderrTask?.cancel()
    }

    var isStillRunning: Bool {
        process.isRunning
    }

    var combinedOutput: String {
        stdoutRecorder.contents + (stdoutRecorder.isEmpty || stderrRecorder.isEmpty ? "" : "\n") + stderrRecorder.contents
    }

    func stderrObjects() -> [[String: Any]] {
        stderrRecorder.snapshot.compactMap { line in
            guard let data = line.data(using: .utf8) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
            return json as? [String: Any]
        }
    }

    func waitForStderrJSONObject(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool
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
                    "The live SpeakSwiftlyServer process exited before the expected stderr JSON log was observed.\n\(self.combinedOutput)"
                )
            }
            return nil
        }
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

    private let stdoutRecorder = SynchronizedLogBuffer()
    private let stderrRecorder = SynchronizedLogBuffer()

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
        timeout: Duration
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

// MARK: - HTTP Client

struct E2EHTTPClient {
    let baseURL: URL

    func request(
        path: String,
        method: String,
        jsonBody: [String: Any]? = nil
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2ETransportError("The live HTTP request to '\(path)' did not return an HTTPURLResponse.")
        }
        return E2EHTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, data: data)
    }
}

struct E2EHTTPResponse {
    let statusCode: Int
    let headers: [AnyHashable: Any]
    let data: Data

    var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

// MARK: - MCP Client

struct E2EMCPClient {
    let baseURL: URL
    let path: String
    let sessionID: String

    static func connect(
        baseURL: URL,
        path: String,
        timeout: Duration,
        server: ServerProcess
    ) async throws -> E2EMCPClient {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
            guard server.isStillRunning else {
                throw E2ETransportError(
                    "The live SpeakSwiftlyServer process exited before the MCP transport became available.\n\(server.combinedOutput)"
                )
            }

            do {
                return try await connectNow(baseURL: baseURL, path: path)
            } catch {
                if isRetryableConnectionDuringStartup(error) {
                    return nil
                }
                return nil
            }
        }
    }

    private static func connectNow(baseURL: URL, path: String) async throws -> E2EMCPClient {
        let initializeBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "initialize-1",
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [:],
                "clientInfo": [
                    "name": "SpeakSwiftlyServerE2ETests",
                    "version": "1.0",
                ],
            ],
        ]

        let initializeResponse = try await post(
            baseURL: baseURL,
            path: path,
            jsonBody: initializeBody,
            sessionID: nil
        )
        let sessionID = try requireMCPHeader("Mcp-Session-Id", in: initializeResponse.headers)
        _ = try parseMCPEnvelope(from: initializeResponse.data)

        let initializedBody: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized",
        ]
        let initializedResponse = try await post(
            baseURL: baseURL,
            path: path,
            jsonBody: initializedBody,
            sessionID: sessionID
        )
        #expect((200...299).contains(initializedResponse.statusCode))

        return .init(baseURL: baseURL, path: path, sessionID: sessionID)
    }

    func callTool(name: String, arguments: [String: String]) async throws -> [String: Any] {
        try await callTool(name: name, arguments: arguments as [String: Any])
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let payload = try await callToolJSON(name: name, arguments: arguments)
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected the '\(name)' MCP tool to return a top-level JSON object, but received '\(type(of: payload))'."
            )
        }
        return object
    }

    func callToolJSON(name: String, arguments: [String: String]) async throws -> Any {
        try await callToolJSON(name: name, arguments: arguments as [String: Any])
    }

    func callToolJSON(name: String, arguments: [String: Any]) async throws -> Any {
        let envelope = try await callMethod(
            "tools/call",
            params: [
                "name": name,
                "arguments": arguments,
            ]
        )
        if let error = envelope["error"] as? [String: Any] {
            throw E2ETransportError("The live MCP tools/call request for '\(name)' failed with payload: \(error)")
        }
        let result = try requireDictionary("result", in: envelope)
        let content = try requireArray("content", in: result)
        let first = try requireFirstDictionary(in: content)
        let text = try requireString("text", in: first)
        return try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    func readResourceText(uri: String) async throws -> String {
        let envelope = try await callMethod("resources/read", params: ["uri": uri])
        if let error = envelope["error"] as? [String: Any] {
            throw E2ETransportError("The live MCP resources/read request for '\(uri)' failed with payload: \(error)")
        }
        let result = try requireDictionary("result", in: envelope)
        let contents = try requireArray("contents", in: result)
        let first = try requireFirstDictionary(in: contents)
        return try requireString("text", in: first)
    }

    func readResourceJSON(uri: String) async throws -> Any {
        try JSONSerialization.jsonObject(with: Data(try await readResourceText(uri: uri).utf8))
    }

    func listResources() async throws -> [[String: Any]] {
        let envelope = try await callMethod("resources/list", params: [:])
        let result = try requireDictionary("result", in: envelope)
        return try requireArray("resources", in: result)
    }

    func listResourceTemplates() async throws -> [[String: Any]] {
        let envelope = try await callMethod("resources/templates/list", params: [:])
        let result = try requireDictionary("result", in: envelope)
        return try requireArray("resourceTemplates", in: result)
    }

    func listPrompts() async throws -> [[String: Any]] {
        let envelope = try await callMethod("prompts/list", params: [:])
        let result = try requireDictionary("result", in: envelope)
        return try requireArray("prompts", in: result)
    }

    func getPrompt(name: String, arguments: [String: String]) async throws -> [String: Any] {
        let envelope = try await callMethod(
            "prompts/get",
            params: [
                "name": name,
                "arguments": arguments,
            ]
        )
        return try requireDictionary("result", in: envelope)
    }

    func subscribe(to uri: String) async throws {
        _ = try await callMethod("resources/subscribe", params: ["uri": uri])
    }

    func unsubscribe(from uri: String) async throws {
        _ = try await callMethod("resources/unsubscribe", params: ["uri": uri])
    }

    func callMethod(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let response = try await Self.post(
            baseURL: baseURL,
            path: path,
            jsonBody: [
                "jsonrpc": "2.0",
                "id": UUID().uuidString,
                "method": method,
                "params": params,
            ],
            sessionID: sessionID
        )
        return try parseMCPEnvelope(from: response.data)
    }

    func openEventStream() -> E2EMCPEventStream {
        .init(baseURL: baseURL, path: path, sessionID: sessionID)
    }

    private static func post(
        baseURL: URL,
        path: String,
        jsonBody: [String: Any],
        sessionID: String?
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw E2ETransportError("The live MCP transport did not return an HTTPURLResponse.")
        }
        return E2EHTTPResponse(statusCode: httpResponse.statusCode, headers: httpResponse.allHeaderFields, data: data)
    }
}

final class E2EMCPEventStream: @unchecked Sendable {
    private let baseURL: URL
    private let path: String
    private let sessionID: String
    private let buffer = E2ENotificationBuffer()
    private var task: Task<Void, Never>?

    init(baseURL: URL, path: String, sessionID: String) {
        self.baseURL = baseURL
        self.path = path
        self.sessionID = sessionID
    }

    func start() {
        guard task == nil else { return }

        task = Task {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await buffer.finish(
                        with: E2ETransportError(
                            "The live MCP event stream did not open successfully for session '\(sessionID)'."
                        )
                    )
                    return
                }

                var dataLines = [String]()
                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }

                    if line.isEmpty {
                        if dataLines.isEmpty == false {
                            let payload = dataLines.joined(separator: "\n")
                            dataLines.removeAll(keepingCapacity: true)
                            if let data = payload.data(using: .utf8) {
                                await buffer.append(data)
                            }
                        }
                        continue
                    }

                    if line.hasPrefix("data: ") {
                        dataLines.append(String(line.dropFirst(6)))
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await buffer.finish(with: error)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func waitForNotification(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool
    ) async throws -> [String: Any] {
        try await e2eWaitUntil(timeout: timeout, pollInterval: .milliseconds(100)) {
            guard let data = try await self.buffer.takeMatching(predicate) else {
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data)
            guard let object = json as? [String: Any] else {
                throw E2ETransportError(
                    "The live MCP event stream produced a notification payload that was not a JSON object."
                )
            }
            return object
        }
    }
}

private actor E2ENotificationBuffer {
    private var notifications = [Data]()
    private var terminalError: Error?

    func append(_ notification: Data) {
        notifications.append(notification)
    }

    func finish(with error: Error) {
        terminalError = error
    }

    func takeMatching(_ predicate: @escaping @Sendable ([String: Any]) -> Bool) throws -> Data? {
        if let terminalError {
            throw terminalError
        }

        for (index, notification) in notifications.enumerated() {
            let json = try JSONSerialization.jsonObject(with: notification)
            guard let object = json as? [String: Any] else {
                continue
            }
            if predicate(object) {
                return notifications.remove(at: index)
            }
        }
        return nil
    }
}

// MARK: - Transport Waiters

func waitUntilWorkerReady(
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess,
    expectPlaybackEngine: Bool = false
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before `/readyz` reported readiness.\n\(server.combinedOutput)"
            )
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

    guard expectPlaybackEngine else { return }

    _ = try await server.waitForStderrJSONObject(timeout: timeout) {
        guard
            $0["event"] as? String == "playback_engine_ready",
            let details = $0["details"] as? [String: Any]
        else {
            return false
        }

        return details["process_phys_footprint_bytes"] as? Int != nil
            && details["mlx_active_memory_bytes"] as? Int != nil
    }
}

func waitUntilWorkerReady(
    using client: E2EMCPClient,
    timeout: Duration,
    server: ServerProcess,
    expectPlaybackEngine: Bool = false
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before the MCP status tool reported readiness.\n\(server.combinedOutput)"
            )
        }

        let payload = try await client.callTool(name: "get_runtime_overview", arguments: [:])
        guard payload["worker_mode"] as? String == "ready" else { return nil }
        return true
    }

    guard expectPlaybackEngine else { return }

    _ = try await server.waitForStderrJSONObject(timeout: timeout) {
        guard
            $0["event"] as? String == "playback_engine_ready",
            let details = $0["details"] as? [String: Any]
        else {
            return false
        }

        return details["process_phys_footprint_bytes"] as? Int != nil
            && details["mlx_active_memory_bytes"] as? Int != nil
    }
}

func waitForTerminalJob(
    id requestID: String,
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before request '\(requestID)' reached a terminal state.\n\(server.combinedOutput)"
            )
        }

        let response = try await client.request(path: "/requests/\(requestID)", method: "GET")
        guard response.statusCode == 200 else { return nil }
        let snapshot = try decode(E2EJobSnapshot.self, from: response.data)
        return snapshot.terminalEvent == nil ? nil : snapshot
    }
}

func waitForTerminalJob(
    id requestID: String,
    using client: E2EMCPClient,
    timeout: Duration,
    server: ServerProcess
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before MCP request resource '\(requestID)' reached a terminal state.\n\(server.combinedOutput)"
            )
        }

        let text = try await client.readResourceText(uri: "speak://requests/\(requestID)")
        let snapshot = try decode(E2EJobSnapshot.self, from: Data(text.utf8))
        return snapshot.terminalEvent == nil ? nil : snapshot
    }
}

func e2eWaitUntil<T>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping () async throws -> T?
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

// MARK: - Stored Profile Helpers

struct StoredProfileManifest: Decodable, Sendable {
    let sourceText: String
}

func loadStoredProfileManifest(named profileName: String, from rootURL: URL) throws -> StoredProfileManifest {
    let manifestURL = rootURL
        .appendingPathComponent(profileName, isDirectory: true)
        .appendingPathComponent("profile.json", isDirectory: false)
    let data = try Data(contentsOf: manifestURL)
    let manifest = try JSONSerialization.jsonObject(with: data)
    guard let object = manifest as? [String: Any] else {
        throw E2ETransportError(
            "The stored profile manifest at '\(manifestURL.path)' did not decode into a JSON object."
        )
    }

    let sourceText =
        object["source_text"] as? String
        ?? object["sourceText"] as? String
        ?? object["transcript"] as? String

    guard let sourceText else {
        let availableKeys = object.keys.sorted().joined(separator: ", ")
        throw E2ETransportError(
            "The stored profile manifest at '\(manifestURL.path)' did not contain a usable source-text field. Available keys: [\(availableKeys)]."
        )
    }

    return .init(sourceText: sourceText)
}

// MARK: - JSON Helpers

func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
    try JSONDecoder().decode(Value.self, from: data)
}

func jsonObject(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    if let dictionaries = json as? [[String: Any]] {
        guard let dictionary = dictionaries.first else {
            throw E2ETransportError("Expected at least one JSON object in the live end-to-end helper array payload, but the array was empty.")
        }
        return dictionary
    }
    guard let dictionary = json as? [String: Any] else {
        throw E2ETransportError("Expected a top-level JSON object in the live end-to-end helper, but received '\(type(of: json))'.")
    }
    return dictionary
}

func parseMCPEnvelope(from data: Data) throws -> [String: Any] {
    let body = String(decoding: data, as: UTF8.self)
    if let dataLine = body
        .split(separator: "\n")
        .reversed()
        .first(where: {
            $0.hasPrefix("data: ")
                && $0.dropFirst("data: ".count).isEmpty == false
        })
    {
        let payload = dataLine.dropFirst("data: ".count)
        guard payload.isEmpty == false else {
            throw E2ETransportError("The live MCP response contained an empty `data:` payload. Raw body: \(body)")
        }
        return try mcpEnvelope(from: Data(payload.utf8), rawBody: body)
    }
    return try mcpEnvelope(from: data, rawBody: body)
}

func mcpEnvelope(from data: Data, rawBody: String) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    if let dictionary = json as? [String: Any] {
        return dictionary
    }

    if let dictionaries = json as? [[String: Any]] {
        if let envelope = dictionaries.first(where: { $0["result"] != nil || $0["error"] != nil }) {
            return envelope
        }
        if let first = dictionaries.first {
            return first
        }
        throw E2ETransportError("The live MCP response decoded to an empty envelope array. Raw body: \(rawBody)")
    }

    throw E2ETransportError("Expected the live MCP response to decode into a JSON-RPC object or array of objects, but received '\(type(of: json))'. Raw body: \(rawBody)")
}

func requireMCPHeader(_ name: String, in headers: [AnyHashable: Any]) throws -> String {
    for (key, value) in headers {
        if String(describing: key).caseInsensitiveCompare(name) == .orderedSame,
           let stringValue = value as? String,
           stringValue.isEmpty == false
        {
            return stringValue
        }
    }
    throw E2ETransportError("The live MCP initialize response was missing the required '\(name)' header.")
}

func requireDictionary(_ key: String, in object: [String: Any]) throws -> [String: Any] {
    guard let value = object[key] as? [String: Any] else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be a JSON object.")
    }
    return value
}

func requireArray(_ key: String, in object: [String: Any]) throws -> [[String: Any]] {
    guard let value = object[key] as? [[String: Any]] else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be an array of JSON objects.")
    }
    return value
}

func requireFirstDictionary(in array: [[String: Any]]) throws -> [String: Any] {
    guard let first = array.first else {
        throw E2ETransportError("The live end-to-end helper expected at least one object in the MCP content array.")
    }
    return first
}

func requireString(_ key: String, in object: [String: Any]) throws -> String {
    guard let value = object[key] as? String, value.isEmpty == false else {
        throw E2ETransportError("The live end-to-end helper expected '\(key)' to be a non-empty string.")
    }
    return value
}

func requireProfiles(from payload: Any) throws -> [E2EProfileSnapshot] {
    if let profiles = payload as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    if let profile = payload as? [String: Any], profile["profile_name"] != nil {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": [profile]])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    guard let payload = payload as? [String: Any] else {
        throw E2ETransportError(
            "The live end-to-end helper expected the profile list payload to decode into a JSON object or array, but received '\(type(of: payload))'."
        )
    }

    if let profiles = payload["profiles"] as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    if let wrappedProfiles = payload["profiles"] as? [String: Any] {
        if let profiles = wrappedProfiles["profiles"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
            return try decode(E2EProfileListResponse.self, from: data).profiles
        }
        if let items = wrappedProfiles["items"] as? [[String: Any]] {
            let data = try JSONSerialization.data(withJSONObject: ["profiles": items])
            return try decode(E2EProfileListResponse.self, from: data).profiles
        }
    }

    if let profiles = payload["items"] as? [[String: Any]] {
        let data = try JSONSerialization.data(withJSONObject: ["profiles": profiles])
        return try decode(E2EProfileListResponse.self, from: data).profiles
    }

    let availableKeys = payload.keys.sorted().joined(separator: ", ")
    throw E2ETransportError(
        "The live end-to-end helper could not find a decodable profile list in the MCP payload. Available top-level keys: [\(availableKeys)]."
    )
}

extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// MARK: - Error Helpers

struct E2ETimeoutError: Error {}

struct E2ETransportError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

struct SpeakSwiftlyBuildError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

func isRetryableConnectionDuringStartup(_ error: Error) -> Bool {
    let nsError = error as NSError
    guard nsError.domain == NSURLErrorDomain else { return false }
    return nsError.code == NSURLErrorCannotConnectToHost || nsError.code == NSURLErrorNetworkConnectionLost
}

// MARK: - Decodable Transport Models

struct E2EReadinessSnapshot: Decodable, Sendable {
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case workerReady = "worker_ready"
    }
}

struct E2EJobCreatedResponse: Decodable, Sendable {
    let requestID: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
    }

    var jobID: String { requestID }
}

struct E2EProfileListResponse: Decodable, Sendable {
    let profiles: [E2EProfileSnapshot]
}

struct E2EProfileSnapshot: Decodable, Sendable {
    let profileName: String
    let vibe: String?
    let voiceDescription: String?
    let sourceText: String?

    enum CodingKeys: String, CodingKey {
        case profileName = "profile_name"
        case vibe
        case voiceDescription = "voice_description"
        case sourceText = "source_text"
    }
}

struct E2ETransportStatus: Decodable, Sendable {
    let name: String
    let state: String
    let advertisedAddress: String?

    enum CodingKeys: String, CodingKey {
        case name
        case state
        case advertisedAddress = "advertised_address"
    }
}

struct E2EHealthSnapshot: Decodable, Sendable {
    let status: String
    let workerMode: String
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case workerMode = "worker_mode"
        case workerReady = "worker_ready"
    }
}

struct E2EStatusSnapshot: Decodable, Sendable {
    let workerMode: String
    let cachedProfiles: [E2EProfileSnapshot]
    let transports: [E2ETransportStatus]
    let generationQueue: E2EQueueStatusSnapshot
    let playbackQueue: E2EQueueStatusSnapshot
    let playback: E2EPlaybackStatusSnapshot

    enum CodingKeys: String, CodingKey {
        case workerMode = "worker_mode"
        case cachedProfiles = "cached_profiles"
        case transports
        case generationQueue = "generation_queue"
        case playbackQueue = "playback_queue"
        case playback
    }
}

struct E2EQueueStatusSnapshot: Decodable, Sendable {
    let activeRequest: E2EActiveRequestSnapshot?
    let queuedRequests: [E2EQueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case activeRequest = "active_request"
        case queuedRequests = "queued_requests"
    }
}

struct E2EPlaybackStatusSnapshot: Decodable, Sendable {
    let state: String
    let activeRequest: E2EActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

struct E2EActiveRequestSnapshot: Decodable, Sendable, Equatable {
    let id: String
    let op: String
    let profileName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
    }
}

struct E2EQueuedRequestSnapshot: Decodable, Sendable, Equatable {
    let id: String
    let op: String
    let profileName: String?
    let queuePosition: Int

    enum CodingKeys: String, CodingKey {
        case id
        case op
        case profileName = "profile_name"
        case queuePosition = "queue_position"
    }
}

struct E2EQueueSnapshotResponse: Decodable, Sendable {
    let queueType: String
    let activeRequest: E2EActiveRequestSnapshot?
    let queue: [E2EQueuedRequestSnapshot]

    enum CodingKeys: String, CodingKey {
        case queueType = "queue_type"
        case activeRequest = "active_request"
        case queue
    }
}

struct E2EPlaybackStateResponse: Decodable, Sendable {
    let playback: E2EPlaybackStateSnapshot
}

struct E2EPlaybackStateSnapshot: Decodable, Sendable {
    let state: String
    let activeRequest: E2EActiveRequestSnapshot?

    enum CodingKeys: String, CodingKey {
        case state
        case activeRequest = "active_request"
    }
}

struct E2EQueueClearedResponse: Decodable, Sendable {
    let clearedCount: Int

    enum CodingKeys: String, CodingKey {
        case clearedCount = "cleared_count"
    }
}

struct E2EQueueCancellationResponse: Decodable, Sendable {
    let cancelledRequestID: String

    enum CodingKeys: String, CodingKey {
        case cancelledRequestID = "cancelled_request_id"
    }
}

struct E2ETextProfileListResponse: Decodable, Sendable {
    let textProfiles: E2ETextProfilesSnapshot

    enum CodingKeys: String, CodingKey {
        case textProfiles = "text_profiles"
    }
}

struct E2ETextProfileResponse: Decodable, Sendable {
    let profile: E2ETextProfileSnapshot
}

struct E2ETextProfilesSnapshot: Decodable, Sendable {
    let persistenceURL: String?
    let baseProfile: E2ETextProfileSnapshot
    let activeProfile: E2ETextProfileSnapshot
    let storedProfiles: [E2ETextProfileSnapshot]
    let effectiveProfile: E2ETextProfileSnapshot

    enum CodingKeys: String, CodingKey {
        case persistenceURL = "persistence_url"
        case baseProfile = "base_profile"
        case activeProfile = "active_profile"
        case storedProfiles = "stored_profiles"
        case effectiveProfile = "effective_profile"
    }
}

struct E2ETextProfileSnapshot: Decodable, Sendable, Equatable {
    let id: String
    let name: String
    let replacements: [E2ETextReplacementSnapshot]
}

struct E2ETextReplacementSnapshot: Decodable, Sendable, Equatable {
    let id: String
    let text: String
    let replacement: String
    let match: String
    let phase: String
    let isCaseSensitive: Bool
    let formats: [String]
    let priority: Int

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case replacement
        case match
        case phase
        case isCaseSensitive = "is_case_sensitive"
        case formats
        case priority
    }
}

struct E2EJobSnapshot: Decodable, Sendable {
    let requestID: String
    let status: String
    let history: [E2EJobEvent]
    let terminalEvent: E2EJobEvent?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case status
        case history
        case terminalEvent = "terminal_event"
    }

    var jobID: String { requestID }
}

struct E2EJobEvent: Decodable, Sendable {
    let id: String?
    let event: String?
    let op: String?
    let stage: String?
    let ok: Bool?
    let reason: String?
    let profileName: String?
    let profilePath: String?
    let message: String?
    let code: String?
    let cancelledRequestID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case event
        case op
        case stage
        case ok
        case reason
        case profileName = "profile_name"
        case profilePath = "profile_path"
        case message
        case code
        case cancelledRequestID = "cancelled_request_id"
    }
}
