import Foundation

// MARK: - E2EMCPEventStream

final class E2EMCPEventStream: @unchecked Sendable {
    private let baseURL: URL
    private let path: String
    private let sessionID: String
    private let buffer = E2ENotificationBuffer()
    private let connectionState = E2EMCPEventStreamConnectionState()
    private let urlSession: URLSession
    private var task: Task<Void, Never>?

    init(baseURL: URL, path: String, sessionID: String) {
        self.baseURL = baseURL
        self.path = path
        self.sessionID = sessionID
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 300
        configuration.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: configuration)
    }

    func start() async throws {
        guard task == nil else { return }

        task = Task {
            var request = URLRequest(url: baseURL.appending(path: path))
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")

            do {
                let (bytes, response) = try await urlSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    await connectionState.finish(
                        with: E2ETransportError(
                            "The live MCP event stream did not open successfully for session '\(sessionID)'.",
                        ),
                    )
                    await buffer.finish(
                        with: E2ETransportError(
                            "The live MCP event stream did not open successfully for session '\(sessionID)'.",
                        ),
                    )
                    return
                }

                await connectionState.markConnected()

                for try await line in bytes.lines {
                    if Task.isCancelled {
                        return
                    }

                    if line.hasPrefix("data: ") {
                        let payload = String(line.dropFirst(6))
                        guard payload.isEmpty == false, let data = payload.data(using: .utf8) else {
                            continue
                        }

                        await buffer.append(data)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                await connectionState.finish(with: error)
                await buffer.finish(with: error)
            }
        }

        let _: Bool = try await e2eWaitUntil(timeout: .seconds(10), pollInterval: .milliseconds(100)) {
            try await self.connectionState.streamReady()
        }
        try await Task.sleep(for: .milliseconds(100))
    }

    func stop() {
        task?.cancel()
        task = nil
        urlSession.invalidateAndCancel()
    }

    func waitForNotification(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool,
    ) async throws -> [String: Any] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if let data = try await buffer.takeMatching(predicate) {
                let json = try JSONSerialization.jsonObject(with: data)
                guard let object = json as? [String: Any] else {
                    throw E2ETransportError(
                        "The live MCP event stream produced a notification payload that was not a JSON object.",
                    )
                }

                return object
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        let observedPayloads = await buffer.recentPayloads(limit: 12)
        let preview = observedPayloads.isEmpty
            ? "none"
            : observedPayloads.joined(separator: "\n")
        throw E2ETransportError(
            "The live MCP event stream timed out after waiting \(timeout) for a matching notification. The GET SSE stream stayed connected, but no matching notification arrived. Recent raw notification payloads seen before timeout:\n\(preview)",
        )
    }
}

// MARK: - E2EMCPEventStreamConnectionState

private actor E2EMCPEventStreamConnectionState {
    private var isConnected = false
    private var terminalError: Error?

    func markConnected() {
        isConnected = true
    }

    func finish(with error: Error) {
        terminalError = error
    }

    func streamReady() throws -> Bool? {
        if let terminalError {
            throw terminalError
        }
        return isConnected ? true : nil
    }
}

// MARK: - E2ENotificationBuffer

private actor E2ENotificationBuffer {
    private var notifications = [Data]()
    private var terminalError: Error?
    private var payloadHistory = [String]()
    private static let payloadHistoryLimit = 48

    func append(_ notification: Data) {
        notifications.append(notification)
        payloadHistory.append(String(decoding: notification, as: UTF8.self))
        if payloadHistory.count > Self.payloadHistoryLimit {
            payloadHistory.removeFirst(payloadHistory.count - Self.payloadHistoryLimit)
        }
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

    func recentPayloads(limit: Int) -> [String] {
        Array(payloadHistory.suffix(limit))
    }
}
