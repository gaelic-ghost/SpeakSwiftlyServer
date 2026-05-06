import Foundation
import Testing

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

        try await e2eWithTimeout(.seconds(10)) {
            try await self.connectionState.waitUntilReady()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        urlSession.invalidateAndCancel()
        let cancellationError = CancellationError()
        Task {
            await connectionState.finish(with: cancellationError)
            await buffer.finish(with: cancellationError)
        }
    }

    func waitForNotification(
        timeout: Duration,
        matching predicate: @escaping @Sendable ([String: Any]) -> Bool,
    ) async throws -> [String: Any] {
        do {
            let data = try await e2eWithTimeout(timeout) {
                try await self.buffer.waitForMatching(predicate)
            }
            let json = try JSONSerialization.jsonObject(with: data)
            guard let object = json as? [String: Any] else {
                throw E2ETransportError(
                    "The live MCP event stream produced a notification payload that was not a JSON object.",
                )
            }

            return object
        } catch is E2ETimeoutError {
            let observedPayloads = await buffer.recentPayloads(limit: 12)
            let preview = observedPayloads.isEmpty
                ? "none"
                : observedPayloads.joined(separator: "\n")
            throw E2ETransportError(
                "The live MCP event stream timed out after waiting \(timeout) for a matching notification. The GET SSE stream stayed connected, but no matching notification arrived. Recent raw notification payloads seen before timeout:\n\(preview)",
            )
        }
    }
}

// MARK: - E2EMCPEventStreamConnectionState

private actor E2EMCPEventStreamConnectionState {
    private var isConnected = false
    private var terminalError: Error?
    private var waiters = [CheckedContinuation<Void, Error>]()

    func markConnected() {
        isConnected = true
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume()
        }
    }

    func finish(with error: Error) {
        guard terminalError == nil else { return }

        terminalError = error
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.resume(throwing: error)
        }
    }

    func waitUntilReady() async throws {
        if let terminalError {
            throw terminalError
        }
        guard isConnected == false else { return }

        try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

// MARK: - E2ENotificationBuffer

private actor E2ENotificationBuffer {
    private struct Waiter {
        let id: UUID
        let predicate: @Sendable ([String: Any]) -> Bool
        let continuation: CheckedContinuation<Data, Error>
    }

    private static let payloadHistoryLimit = 48

    private var notifications = [Data]()
    private var terminalError: Error?
    private var payloadHistory = [String]()
    private var waiters = [Waiter]()

    func append(_ notification: Data) {
        payloadHistory.append(String(decoding: notification, as: UTF8.self))
        if payloadHistory.count > Self.payloadHistoryLimit {
            payloadHistory.removeFirst(payloadHistory.count - Self.payloadHistoryLimit)
        }

        if let object = try? decodeJSONObject(from: notification),
           let waiterIndex = waiters.firstIndex(where: { $0.predicate(object) }) {
            let waiter = waiters.remove(at: waiterIndex)
            waiter.continuation.resume(returning: notification)
            return
        }

        notifications.append(notification)
    }

    func finish(with error: Error) {
        guard terminalError == nil else { return }

        terminalError = error
        let pendingWaiters = waiters
        waiters.removeAll()
        for waiter in pendingWaiters {
            waiter.continuation.resume(throwing: error)
        }
    }

    func waitForMatching(_ predicate: @escaping @Sendable ([String: Any]) -> Bool) async throws -> Data {
        if let terminalError {
            throw terminalError
        }

        for (index, notification) in notifications.enumerated() {
            guard let object = try? decodeJSONObject(from: notification) else {
                continue
            }

            if predicate(object) {
                return notifications.remove(at: index)
            }
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let terminalError {
                    continuation.resume(throwing: terminalError)
                    return
                }

                waiters.append(.init(id: waiterID, predicate: predicate, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID)
            }
        }
    }

    func recentPayloads(limit: Int) -> [String] {
        Array(payloadHistory.suffix(limit))
    }

    private func cancelWaiter(id: UUID) {
        guard let waiterIndex = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }

        let waiter = waiters.remove(at: waiterIndex)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func decodeJSONObject(from notification: Data) throws -> [String: Any] {
        let json = try JSONSerialization.jsonObject(with: notification)
        guard let object = json as? [String: Any] else {
            throw E2ETransportError(
                "The live MCP event stream produced a notification payload that was not a JSON object.",
            )
        }

        return object
    }
}

// MARK: - Timeout Support

private func e2eWithTimeout<T: Sendable>(
    _ timeout: Duration,
    operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw E2ETimeoutError()
        }

        guard let value = try await group.next() else {
            throw E2ETimeoutError()
        }

        group.cancelAll()
        return value
    }
}

// MARK: - E2E MCP Event Stream Tests

@Test func `notification buffer wakes a matching waiter when payload arrives`() async throws {
    let buffer = E2ENotificationBuffer()
    let waiter = Task {
        try await buffer.waitForMatching {
            $0["method"] as? String == "notifications/resources/updated"
        }
    }

    await Task.yield()
    await buffer.append(
        Data(#"{"method":"notifications/resources/updated","params":{"uri":"speak-swiftly://voices"}}"#.utf8),
    )

    let data = try await waiter.value
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["method"] as? String == "notifications/resources/updated")
}

@Test func `notification buffer finishes pending waiters on terminal error`() async throws {
    let buffer = E2ENotificationBuffer()
    let waiter = Task {
        try await buffer.waitForMatching { _ in true }
    }

    await Task.yield()
    await buffer.finish(with: E2ETransportError("The event stream closed before a notification arrived."))

    await #expect(throws: E2ETransportError.self) {
        _ = try await waiter.value
    }
}
