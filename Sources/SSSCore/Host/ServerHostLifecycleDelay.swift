import Foundation

private final class ServerHostLifecycleDelayState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var isResolved = false

    func install(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if isResolved {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }

        self.continuation = continuation
        lock.unlock()
    }

    func resume(returning result: Result<Void, Error>) {
        let pendingContinuation: CheckedContinuation<Void, Error>?

        lock.lock()
        if isResolved {
            lock.unlock()
            return
        }

        isResolved = true
        pendingContinuation = continuation
        continuation = nil
        lock.unlock()

        guard let pendingContinuation else { return }

        switch result {
            case .success:
                pendingContinuation.resume()
            case let .failure(error):
                pendingContinuation.resume(throwing: error)
        }
    }
}

package func hostLifecycleDelay(for duration: Duration) async throws {
    let state = ServerHostLifecycleDelayState()
    let interval = max(0, duration.timeInterval)

    try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            state.install(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
                state.resume(returning: .success(()))
            }
        }
    } onCancel: {
        state.resume(returning: .failure(CancellationError()))
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = components
        let seconds = TimeInterval(components.seconds)
        let fractionalSeconds = TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds + fractionalSeconds
    }
}
