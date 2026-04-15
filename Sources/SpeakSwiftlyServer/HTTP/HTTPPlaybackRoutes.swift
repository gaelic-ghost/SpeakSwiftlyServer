import Hummingbird

// MARK: - Playback Routes

func registerHTTPPlaybackRoutes(
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
        try await host.clearQueue()
    }

    router.delete("playback/requests/:request_id") { _, context -> QueueCancellationResponse in
        let requestID = try context.parameters.require("request_id")
        return try await host.cancelQueuedOrActiveRequest(requestID: requestID)
    }
}
