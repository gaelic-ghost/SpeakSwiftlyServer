import Foundation
import Observation

// MARK: - Observable State

@Observable
@MainActor
public final class ServerState {
    public internal(set) var overview = HostOverviewSnapshot(
        service: "speak-swiftly-server",
        environment: "development",
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

    public internal(set) var generationQueue = QueueStatusSnapshot(
        queueType: "generation",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil
    )

    public internal(set) var playbackQueue = QueueStatusSnapshot(
        queueType: "playback",
        activeCount: 0,
        queuedCount: 0,
        activeRequest: nil
    )

    public internal(set) var playback = PlaybackStatusSnapshot(
        state: "idle",
        activeRequest: nil
    )

    public internal(set) var currentGenerationJob: CurrentGenerationJobSnapshot?
    public internal(set) var transports = [TransportStatusSnapshot]()
    public internal(set) var recentErrors = [RecentErrorSnapshot]()
    public internal(set) var jobsByID: [String: JobSnapshot] = [:]

    public init() {}
}
