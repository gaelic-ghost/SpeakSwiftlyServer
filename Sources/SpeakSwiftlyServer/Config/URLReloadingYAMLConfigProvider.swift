import AsyncAlgorithms
import Configuration
import Foundation
import ServiceLifecycle

final class URLReloadingYAMLConfigProvider: ConfigProvider, Service, @unchecked Sendable {
    private struct FileSource: Equatable {
        var modifiedAt: Date
        var size: UInt64
    }

    private struct Storage {
        var snapshot: any ConfigSnapshot
        var source: FileSource
        var valueWatchers: [AbsoluteConfigKey: [UUID: AsyncStream<Result<LookupResult, any Error>>.Continuation]]
        var snapshotWatchers: [UUID: AsyncStream<any ConfigSnapshot>.Continuation]
    }

    let providerName = "URLReloadingYAMLConfigProvider"

    private let fileURL: URL
    private let pollInterval: Duration
    private let lock = NSLock()
    private var storage: Storage

    init(fileURL: URL, pollInterval: Duration) async throws {
        self.fileURL = fileURL.standardizedFileURL
        self.pollInterval = pollInterval
        let loadedFile = try Self.loadSnapshot(from: self.fileURL, providerName: providerName)
        storage = Storage(
            snapshot: loadedFile.snapshot,
            source: loadedFile.source,
            valueWatchers: [:],
            snapshotWatchers: [:],
        )
    }

    private static func loadSnapshot(
        from fileURL: URL,
        providerName: String,
    ) throws -> (snapshot: any ConfigSnapshot, source: FileSource) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ServerConfigurationError(
                "Configuration file '\(fileURL.path)' does not exist. Use a server-owned config URL that has been seeded from the bundled default, or run launch-agent install to seed the default Application Support config.",
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

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ServerConfigurationError(
                "Configuration file '\(fileURL.path)' exists but could not be read. Likely cause: \(error.localizedDescription)",
            )
        }

        let snapshot = try YAMLSnapshot(
            data: data.bytes,
            providerName: providerName,
            parsingOptions: .default,
        )
        return (snapshot, FileSource(modifiedAt: modifiedAt, size: size))
    }

    func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        try lock.withLock {
            try storage.snapshot.value(forKey: key, type: type)
        }
    }

    func fetchValue(forKey key: AbsoluteConfigKey, type: ConfigType) async throws -> LookupResult {
        try await reloadIfNeeded()
        return try value(forKey: key, type: type)
    }

    nonisolated(nonsending) func watchValue<Return: ~Copyable>(
        forKey key: AbsoluteConfigKey,
        type: ConfigType,
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<Result<LookupResult, any Error>, Never>) async throws ->
            Return,
    ) async throws -> Return {
        let (stream, continuation) = AsyncStream<Result<LookupResult, any Error>>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let initialValue: Result<LookupResult, any Error> = lock.withLock {
            storage.valueWatchers[key, default: [:]][id] = continuation
            return Result { try storage.snapshot.value(forKey: key, type: type) }
        }
        defer {
            lock.withLock {
                storage.valueWatchers[key, default: [:]][id] = nil
            }
        }

        continuation.yield(initialValue)
        return try await updatesHandler(.init(stream))
    }

    func snapshot() -> any ConfigSnapshot {
        lock.withLock {
            storage.snapshot
        }
    }

    nonisolated(nonsending) func watchSnapshot<Return: ~Copyable>(
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<any ConfigSnapshot, Never>) async throws -> Return,
    ) async throws -> Return {
        let (stream, continuation) = AsyncStream<any ConfigSnapshot>
            .makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let initialSnapshot = lock.withLock {
            storage.snapshotWatchers[id] = continuation
            return storage.snapshot
        }
        defer {
            lock.withLock {
                storage.snapshotWatchers[id] = nil
            }
        }

        continuation.yield(initialSnapshot)
        return try await updatesHandler(.init(stream))
    }

    func run() async throws {
        for try await _ in AsyncTimerSequence(interval: pollInterval, clock: .continuous)
            .cancelOnGracefulShutdown() {
            try await reloadIfNeeded()
        }
    }

    private func reloadIfNeeded() async throws {
        let loadedFile = try Self.loadSnapshot(from: fileURL, providerName: providerName)
        let watchers = lock.withLock { () -> (
            [AsyncStream<any ConfigSnapshot>.Continuation],
            [(AbsoluteConfigKey, [AsyncStream<Result<LookupResult, any Error>>.Continuation])],
        )? in
            guard storage.source != loadedFile.source else {
                return nil
            }

            storage.snapshot = loadedFile.snapshot
            storage.source = loadedFile.source
            return (
                Array(storage.snapshotWatchers.values),
                storage.valueWatchers.map { key, continuations in
                    (key, Array(continuations.values))
                },
            )
        }

        guard let watchers else { return }

        for continuation in watchers.0 {
            continuation.yield(loadedFile.snapshot)
        }
        for (key, continuations) in watchers.1 {
            let value = Result { try loadedFile.snapshot.value(forKey: key, type: .string) }
            for continuation in continuations {
                continuation.yield(value)
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
