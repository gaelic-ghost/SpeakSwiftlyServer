import Foundation
import Observation

// MARK: - Observable State

@Observable
@MainActor
final class ServerState {
    var health = HealthSnapshot(
        status: "ok",
        service: "speak-swiftly-server",
        environment: "development",
        serverMode: "degraded",
        workerMode: "starting",
        workerStage: "starting",
        workerReady: false,
        startupError: nil
    )

    var readiness = ReadinessSnapshot(
        status: "not_ready",
        serverMode: "degraded",
        workerMode: "starting",
        workerStage: "starting",
        workerReady: false,
        startupError: nil,
        profileCacheState: "uninitialized",
        profileCacheWarning: nil,
        profileCount: 0,
        lastProfileRefreshAt: nil
    )

    var status = StatusSnapshot(
        service: "speak-swiftly-server",
        environment: "development",
        serverMode: "degraded",
        workerMode: "starting",
        workerStage: "starting",
        profileCacheState: "uninitialized",
        profileCacheWarning: nil,
        workerFailureSummary: nil,
        cachedProfiles: [],
        lastProfileRefreshAt: nil,
        host: "127.0.0.1",
        port: 7337
    )

    var jobsByID: [String: JobSnapshot] = [:]

    init() {}
}
