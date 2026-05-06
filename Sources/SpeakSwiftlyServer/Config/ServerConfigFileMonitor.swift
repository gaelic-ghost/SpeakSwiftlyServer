import AsyncAlgorithms
import Foundation
import ServiceLifecycle

final class ServerConfigFileMonitor: Service, @unchecked Sendable {
    private struct FileSource: Equatable {
        var modifiedAt: Date
        var size: UInt64
    }

    private let fileURL: URL
    private let pollInterval: Duration
    private let lock = NSLock()
    private var source: FileSource
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    init(fileURL: URL, pollInterval: Duration) throws {
        self.fileURL = fileURL.standardizedFileURL
        self.pollInterval = pollInterval
        source = try Self.loadSource(from: self.fileURL)
    }

    private static func loadSource(from fileURL: URL) throws -> FileSource {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ServerConfigurationError(
                "Configuration file '\(fileURL.path)' does not exist. Use a server-owned config URL that has been seeded from the bundled default, or pass APP_CONFIG_FILE with an existing YAML config path.",
            )
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        } catch {
            throw ServerConfigurationError(
                "Configuration file '\(fileURL.path)' exists but its file attributes could not be read. Likely cause: \(error.localizedDescription)",
            )
        }

        guard let modifiedAt = attributes[.modificationDate] as? Date else {
            throw ServerConfigurationError(
                "Configuration file '\(fileURL.path)' is missing a modification timestamp, so reload checks cannot track it safely.",
            )
        }

        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        return FileSource(modifiedAt: modifiedAt, size: size)
    }

    func updates() -> AsyncThrowingStream<Void, Error> {
        AsyncThrowingStream { continuation in
            let (stream, streamContinuation) = AsyncStream<Void>
                .makeStream(bufferingPolicy: .bufferingNewest(1))
            let id = UUID()
            lock.withLock {
                continuations[id] = streamContinuation
            }

            let task = Task {
                for await update in stream {
                    continuation.yield(update)
                }
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                self.lock.withLock {
                    self.continuations[id] = nil
                }
            }
        }
    }

    func run() async throws {
        for try await _ in AsyncTimerSequence(interval: pollInterval, clock: .continuous)
            .cancelOnGracefulShutdown() {
            let loadedSource = try Self.loadSource(from: fileURL)
            let continuations = lock.withLock { () -> [AsyncStream<Void>.Continuation] in
                guard source != loadedSource else {
                    return []
                }

                source = loadedSource
                return Array(self.continuations.values)
            }

            for continuation in continuations {
                continuation.yield(())
            }
        }
    }
}

private extension NSLock {
    func withLock<Return>(_ body: () throws -> Return) rethrows -> Return {
        lock()
        defer { unlock() }
        return try body()
    }
}
