import AsyncAlgorithms
import Foundation
import ServiceLifecycle

private struct EmbeddedLifecycleReadinessError: Error {
    let message: String
}

struct EmbeddedLifecycleStartupTimeoutError: Error, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

actor EmbeddedLifecycleReadinessGate {
    private enum State {
        case pending([CheckedContinuation<Void, Error>])
        case ready
        case failed(EmbeddedLifecycleReadinessError)
    }

    private var state: State = .pending([])

    func waitUntilReady() async throws {
        switch state {
            case .ready:
                return
            case let .failed(error):
                throw error
            case .pending:
                try await withCheckedThrowingContinuation { continuation in
                    switch state {
                        case .ready:
                            continuation.resume()
                        case let .failed(error):
                            continuation.resume(throwing: error)
                        case var .pending(continuations):
                            continuations.append(continuation)
                            state = .pending(continuations)
                    }
                }
        }
    }

    func markReady() {
        guard case let .pending(continuations) = state else {
            return
        }

        state = .ready
        for continuation in continuations {
            continuation.resume()
        }
    }

    func markFailed(message: String) {
        guard case let .pending(continuations) = state else {
            return
        }

        let error = EmbeddedLifecycleReadinessError(message: message)
        state = .failed(error)
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}

actor EmbeddedLifecycleShutdownBarrier {
    private let targetCount: Int
    private var completedCount = 0
    private var continuations = [CheckedContinuation<Void, Never>]()

    init(targetCount: Int) {
        self.targetCount = targetCount
    }

    func markCompleted() {
        guard completedCount < targetCount else {
            return
        }

        completedCount += 1
        guard completedCount == targetCount else {
            return
        }

        let pendingContinuations = continuations
        continuations.removeAll()
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }

    func waitUntilCompleted() async {
        guard completedCount < targetCount else {
            return
        }

        await withCheckedContinuation { continuation in
            if completedCount >= targetCount {
                continuation.resume()
            } else {
                continuations.append(continuation)
            }
        }
    }
}

private func withEmbeddedShutdownBarrier<T>(
    _ shutdownBarrier: EmbeddedLifecycleShutdownBarrier,
    operation: () async throws -> T,
) async throws -> T {
    do {
        let result = try await operation()
        await shutdownBarrier.markCompleted()
        return result
    } catch {
        await shutdownBarrier.markCompleted()
        throw error
    }
}

private enum HostLifecycleStartupOutcome {
    case started
    case shutdownRequested
    case timedOut
}

private func embeddedLifecycleDurationDescription(_ duration: Duration) -> String {
    if duration.components.attoseconds == 0 {
        return "\(duration.components.seconds) second(s)"
    }

    let fractionalSeconds = Double(duration.components.seconds)
        + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    return String(format: "%.2f second(s)", fractionalSeconds)
}

struct HostLifecycleService: Service {
    static let defaultStartupTimeout: Duration = .seconds(15)

    let host: ServerHost
    let readinessGate: EmbeddedLifecycleReadinessGate
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier
    let startupTimeout: Duration

    func run() async throws {
        let startupTask = Task {
            await host.start()
        }

        switch await waitForStartupOutcome(startupTask: startupTask) {
            case .started:
                await readinessGate.markReady()
            case .shutdownRequested:
                startupTask.cancel()
                await host.shutdown()
                return
            case .timedOut:
                startupTask.cancel()
                let message =
                    "SpeakSwiftlyServer timed out while waiting for the embedded runtime to finish startup after \(embeddedLifecycleDurationDescription(startupTimeout)). Likely cause: the underlying SpeakSwiftly runtime start path stopped responding before it reported readiness."
                await readinessGate.markFailed(message: message)
                await host.markEmbeddedStartupFailure(message)
                await host.shutdown()
                throw EmbeddedLifecycleStartupTimeoutError(message: message)
        }

        do {
            try await gracefulShutdown()
        } catch is CancellationError {
            // Let sibling-service failure or shutdown still flow through orderly host teardown.
        }

        await shutdownBarrier.waitUntilCompleted()
        await host.shutdown()
    }

    private func waitForStartupOutcome(startupTask: Task<Void, Never>) async -> HostLifecycleStartupOutcome {
        let (events, continuation) = AsyncStream.makeStream(
            of: HostLifecycleStartupOutcome.self,
            bufferingPolicy: .bufferingNewest(1),
        )

        let startupWatcher = Task {
            await startupTask.value
            continuation.yield(.started)
            continuation.finish()
        }

        let shutdownWatcher = Task {
            do {
                try await gracefulShutdown()
                continuation.yield(.shutdownRequested)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.yield(.shutdownRequested)
                continuation.finish()
            }
        }

        let timeoutWatcher = Task {
            do {
                try await hostLifecycleDelay(for: startupTimeout)
                continuation.yield(.timedOut)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish()
            } catch {
                continuation.finish()
            }
        }

        let outcome = await events.first(where: { _ in true }) ?? .started
        // These watcher tasks complete on their own once startup, shutdown, or timeout happens.
        // Cancelling the sleeping timeout watcher during normal fast startup can trip Swift
        // concurrency teardown in optimized LaunchAgent builds before the server binds HTTP.
        _ = (startupWatcher, shutdownWatcher, timeoutWatcher)
        return outcome
    }
}

struct HostPruneService: Service {
    let host: ServerHost
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        _ = try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            while !Task.isCancelled {
                let interval = await host.jobPruneInterval()
                var didReceiveTick = false
                for await _ in AsyncTimerSequence(interval: interval, clock: .continuous)
                    .prefix(1)
                    .cancelOnGracefulShutdown() {
                    didReceiveTick = true
                }

                guard didReceiveTick, !Task.isCancelled else {
                    break
                }

                await host.runPruneMaintenanceTick()
            }
        }
    }
}

struct ConfigWatchService: Service {
    let serverConfigStore: ServerConfigStore
    let host: ServerHost
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        _ = try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            do {
                for try await update in serverConfigStore.updates().cancelOnGracefulShutdown() {
                    switch update {
                        case let .reloaded(updatedConfig):
                            await host.applyConfigurationUpdate(updatedConfig)
                        case let .rejected(message):
                            await host.markConfigurationReloadRejected(message)
                    }
                }
            } catch is CancellationError {
                // Graceful shutdown or sibling failure cancelled the watch loop.
            } catch {
                await host.markConfigurationWatchFailed(error)
                // Preserve the pre-service-lifecycle behavior: a config-watch failure should be
                // reported clearly, but it should not tear down the embedded host.
            }
        }
    }
}

struct MCPLifecycleService: Service {
    let surface: MCPSurface
    let readinessGate: EmbeddedLifecycleReadinessGate
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        do {
            try await surface.start()
        } catch {
            await readinessGate.markFailed(
                message: "SpeakSwiftly MCP could not finish starting inside the embedded session lifecycle. Likely cause: \(error.localizedDescription)",
            )
            await shutdownBarrier.markCompleted()
            throw error
        }

        await readinessGate.markReady()

        try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            do {
                try await gracefulShutdown()
            } catch is CancellationError {
                // Stop and drain MCP sessions before the shared host tears down.
            }

            await surface.stop()
        }
    }
}

struct EmbeddedApplicationService: Service {
    let application: any Service
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            try await application.run()
        }
    }
}
