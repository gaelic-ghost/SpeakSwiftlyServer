import Foundation

// MARK: - Transport Waiters

func waitUntilWorkerReady(
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess,
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before `/readyz` reported readiness.\n\(server.combinedOutput)",
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
}

func waitUntilWorkerReady(
    using client: E2EMCPClient,
    timeout: Duration,
    server: ServerProcess,
) async throws {
    let _: Bool = try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before the MCP status tool reported readiness.\n\(server.combinedOutput)",
            )
        }

        let payload = try await client.callTool(name: "get_runtime_overview", arguments: [:])
        guard payload["worker_mode"] as? String == "ready" else { return nil }

        return true
    }
}

func waitForTerminalJob(
    id requestID: String,
    using client: E2EHTTPClient,
    timeout: Duration,
    server: ServerProcess,
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before request '\(requestID)' reached a terminal state.\n\(server.combinedOutput)",
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
    server: ServerProcess,
) async throws -> E2EJobSnapshot {
    try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
        guard server.isStillRunning else {
            throw E2ETransportError(
                "The live SpeakSwiftlyServer process exited before MCP request resource '\(requestID)' reached a terminal state.\n\(server.combinedOutput)",
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
    condition: @escaping () async throws -> T?,
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

// MARK: - StoredProfileManifest

struct StoredProfileManifest: Decodable {
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
            "The stored profile manifest at '\(manifestURL.path)' did not decode into a JSON object.",
        )
    }

    let sourceText =
        object["source_text"] as? String
            ?? object["sourceText"] as? String
            ?? object["transcript"] as? String

    guard let sourceText else {
        let availableKeys = object.keys.sorted().joined(separator: ", ")
        throw E2ETransportError(
            "The stored profile manifest at '\(manifestURL.path)' did not contain a usable source-text field. Available keys: [\(availableKeys)].",
        )
    }

    return .init(sourceText: sourceText)
}
