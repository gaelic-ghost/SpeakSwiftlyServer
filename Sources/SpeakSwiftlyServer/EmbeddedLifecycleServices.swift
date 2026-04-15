import AsyncAlgorithms
import Foundation
import ServiceLifecycle

// MARK: - EmbeddedLifecycleReadinessError

private struct EmbeddedLifecycleReadinessError: Error {
    let message: String
}

// MARK: - EmbeddedLifecycleReadinessGate

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

// MARK: - EmbeddedLifecycleShutdownBarrier

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

// MARK: - HostLifecycleService

struct HostLifecycleService: Service {
    let host: ServerHost
    let readinessGate: EmbeddedLifecycleReadinessGate
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        await host.start()
        await readinessGate.markReady()

        do {
            try await gracefulShutdown()
        } catch is CancellationError {
            // Let sibling-service failure or shutdown still flow through orderly host teardown.
        }

        await shutdownBarrier.waitUntilCompleted()
        await host.shutdown()
    }
}

// MARK: - HostPruneService

struct HostPruneService: Service {
    let host: ServerHost
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
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

        await shutdownBarrier.markCompleted()
    }
}

// MARK: - ConfigWatchService

struct ConfigWatchService: Service {
    let configStore: ConfigStore
    let host: ServerHost
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        do {
            for try await update in configStore.updates().cancelOnGracefulShutdown() {
                switch update {
                    case let .reloaded(updatedConfig):
                        await host.applyConfigurationUpdate(updatedConfig)
                    case let .rejected(message):
                        await host.markConfigurationReloadRejected(message)
                }
            }
            await shutdownBarrier.markCompleted()
        } catch is CancellationError {
            // Graceful shutdown or sibling failure cancelled the watch loop.
            await shutdownBarrier.markCompleted()
        } catch {
            await host.markConfigurationWatchFailed(error)
            // Preserve the pre-service-lifecycle behavior: a config-watch failure should be
            // reported clearly, but it should not tear down the embedded host.
            await shutdownBarrier.markCompleted()
            return
        }
    }
}

// MARK: - MCPLifecycleService

struct MCPLifecycleService: Service {
    let surface: MCPSurface
    let readinessGate: EmbeddedLifecycleReadinessGate
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        do {
            try await surface.start()
            await readinessGate.markReady()

            do {
                try await gracefulShutdown()
            } catch is CancellationError {
                // Stop and drain MCP sessions before the shared host tears down.
            }

            await surface.stop()
            await shutdownBarrier.markCompleted()
        } catch {
            await readinessGate.markFailed(
                message: "SpeakSwiftly MCP could not finish starting inside the embedded session lifecycle. Likely cause: \(error.localizedDescription)",
            )
            await shutdownBarrier.markCompleted()
            throw error
        }
    }
}

// MARK: - EmbeddedApplicationService

struct EmbeddedApplicationService: Service {
    let application: any Service
    let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    func run() async throws {
        do {
            try await application.run()
            await shutdownBarrier.markCompleted()
        } catch {
            await shutdownBarrier.markCompleted()
            throw error
        }
    }
}
