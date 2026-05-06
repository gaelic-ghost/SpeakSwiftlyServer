import Configuration

struct SnapshotConfigProvider: ConfigProvider {
    let providerName = "SnapshotConfigProvider"
    let currentSnapshot: any ConfigSnapshot

    func value(forKey key: AbsoluteConfigKey, type: ConfigType) throws -> LookupResult {
        try currentSnapshot.value(forKey: key, type: type)
    }

    func fetchValue(forKey key: AbsoluteConfigKey, type: ConfigType) async throws -> LookupResult {
        try value(forKey: key, type: type)
    }

    func snapshot() -> any ConfigSnapshot {
        currentSnapshot
    }

    nonisolated(nonsending) func watchValue<Return: ~Copyable>(
        forKey key: AbsoluteConfigKey,
        type: ConfigType,
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<Result<LookupResult, any Error>, Never>) async throws -> Return,
    ) async throws -> Return {
        let stream = AsyncStream<Result<LookupResult, any Error>> { continuation in
            continuation.yield(Result { try currentSnapshot.value(forKey: key, type: type) })
            continuation.finish()
        }
        return try await updatesHandler(.init(stream))
    }

    nonisolated(nonsending) func watchSnapshot<Return: ~Copyable>(
        updatesHandler: nonisolated(nonsending) (_ updates: ConfigUpdatesAsyncSequence<any ConfigSnapshot, Never>) async throws -> Return,
    ) async throws -> Return {
        let stream = AsyncStream<any ConfigSnapshot> { continuation in
            continuation.yield(currentSnapshot)
            continuation.finish()
        }
        return try await updatesHandler(.init(stream))
    }
}
