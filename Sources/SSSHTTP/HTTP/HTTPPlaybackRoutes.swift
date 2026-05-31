import Hummingbird
import SSSCore

package func registerHTTPPlaybackRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("playback/state") { _, _ -> PlaybackStateResponse in
        await host.playbackStateSnapshot()
    }

    router.get("playback/queue") { _, _ -> QueueSnapshotResponse in
        await host.playbackQueueSnapshot()
    }

    router.post("playback/pause") { _, _ -> PlaybackStateResponse in
        try await host.pausePlayback()
    }

    router.post("playback/resume") { _, _ -> PlaybackStateResponse in
        try await host.resumePlayback()
    }

    router.delete("playback/queue") { _, _ -> QueueClearedResponse in
        try await host.clearQueue(.playback)
    }
}
