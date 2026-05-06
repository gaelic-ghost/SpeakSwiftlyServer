import Foundation
import Testing

// MARK: - E2EMCPClient

struct E2EMCPClient {
    let baseURL: URL
    let path: String
    let sessionID: String

    static func connect(
        baseURL: URL,
        path: String,
        timeout: Duration,
        server: ServerProcess,
    ) async throws -> E2EMCPClient {
        let startupErrorRecorder = E2ERecordedError()
        do {
            return try await e2eWaitUntil(timeout: timeout, pollInterval: .seconds(1)) {
                guard server.isStillRunning else {
                    throw E2ETransportError(
                        "The live SpeakSwiftlyServer process exited before the MCP transport became available.\n\(server.combinedOutput)",
                    )
                }

                do {
                    return try await connectNow(baseURL: baseURL, path: path)
                } catch {
                    if isRetryableConnectionDuringStartup(error) {
                        startupErrorRecorder.record(error)
                        return nil
                    }

                    throw E2ETransportError(
                        "The live MCP transport became reachable, but the initial session handshake failed before a session was established. Underlying error: \(error)",
                    )
                }
            }
        } catch is E2ETimeoutError {
            if let startupError = startupErrorRecorder.value {
                throw E2ETransportError(
                    "The live MCP transport did not become ready within \(timeout). The most recent retryable startup error was: \(startupError)",
                )
            }

            throw E2ETransportError(
                "The live MCP transport did not become ready within \(timeout), and the server never completed the initial MCP session handshake.",
            )
        }
    }

    func callTool(name: String, arguments: [String: String]) async throws -> [String: Any] {
        try await callTool(name: name, arguments: arguments as [String: Any])
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> [String: Any] {
        let payload = try await callToolJSON(name: name, arguments: arguments)
        guard let object = payload as? [String: Any] else {
            throw E2ETransportError(
                "The live end-to-end helper expected the '\(name)' MCP tool to return a top-level JSON object, but received '\(type(of: payload))'.",
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
            ],
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
        try await JSONSerialization.jsonObject(with: Data(readResourceText(uri: uri).utf8))
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
            ],
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
            sessionID: sessionID,
        )
        return try parseMCPEnvelope(from: response.data)
    }

    func openEventStream() -> E2EMCPEventStream {
        .init(baseURL: baseURL, path: path, sessionID: sessionID)
    }
}

// MARK: - MCP Transport Helpers

private extension E2EMCPClient {
    static func connectNow(baseURL: URL, path: String) async throws -> E2EMCPClient {
        let initializeBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": "initialize-1",
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [:],
                "clientInfo": [
                    "name": "ServerE2E",
                    "version": "1.0",
                ],
            ],
        ]

        let initializeResponse = try await post(
            baseURL: baseURL,
            path: path,
            jsonBody: initializeBody,
            sessionID: nil,
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
            sessionID: sessionID,
        )
        #expect((200...299).contains(initializedResponse.statusCode))

        return .init(baseURL: baseURL, path: path, sessionID: sessionID)
    }

    static func post(
        baseURL: URL,
        path: String,
        jsonBody: [String: Any],
        sessionID: String?,
    ) async throws -> E2EHTTPResponse {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
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
