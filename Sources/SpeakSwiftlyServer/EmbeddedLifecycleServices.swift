import Foundation
import ServiceLifecycle

// MARK: - Embedded Lifecycle Coordination

private struct EmbeddedLifecycleReadinessError: Error, Sendable {
    let message: String
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
        case .failed(let error):
            throw error
        case .pending:
            try await withCheckedThrowingContinuation { continuation in
                switch state {
                case .ready:
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .pending(var continuations):
                    continuations.append(continuation)
                    state = .pending(continuations)
                }
            }
        }
    }

    func markReady() {
        guard case .pending(let continuations) = state else {
            return
        }
        state = .ready
        for continuation in continuations {
            continuation.resume()
        }
    }

    func markFailed(message: String) {
        guard case .pending(let continuations) = state else {
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

// MARK: - Embedded Lifecycle Services

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

struct ConfigWatchService: Service {
    let configStore: ConfigStore
    let host: ServerHost

    func run() async throws {
        do {
            for try await update in configStore.updates().cancelOnGracefulShutdown() {
                switch update {
                case .reloaded(let updatedConfig):
                    await host.applyConfigurationUpdate(updatedConfig)
                case .rejected(let message):
                    await host.markConfigurationReloadRejected(message)
                }
            }
        } catch is CancellationError {
            // Graceful shutdown or sibling failure cancelled the watch loop.
        } catch {
            await host.markConfigurationWatchFailed(error)
            throw error
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
                message: "SpeakSwiftly MCP could not finish starting inside the embedded session lifecycle. Likely cause: \(error.localizedDescription)"
            )
            await shutdownBarrier.markCompleted()
            throw error
        }
    }
}

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
