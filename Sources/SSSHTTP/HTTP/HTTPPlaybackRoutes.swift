import Hummingbird
import SpeakSwiftly
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

    router.get("playback/recent-generated-audio") { _, _ -> RecentGeneratedAudioResponse in
        await host.recentGeneratedAudioSnapshot()
    }

    router.get("playback/recent-generated-audio/:recent_audio_id/chunks") { _, context -> RecentGeneratedAudioChunksResponse in
        let recentAudioID = try context.parameters.require("recent_audio_id")
        return await host.recentGeneratedAudioChunks(for: recentAudioID)
    }

    router.post("playback/recent-generated-audio/:recent_audio_id/replay") { request, context -> ReplayRecentAudioResponse in
        let recentAudioID = try context.parameters.require("recent_audio_id")
        let payload = try await request.decode(as: ReplayRecentAudioRequestPayload.self, context: context)
        return try await host.replayRecentAudio(
            id: recentAudioID,
            mode: payload.replayMode ?? .enqueueNext,
            requestContext: payload.resolvedRequestContext(
                defaults: httpRecentGeneratedAudioRequestContextDefaults(
                    route: "/playback/recent-generated-audio/{recent_audio_id}/replay",
                ),
            ),
        )
    }

    router.post("playback/recent-generated-audio/replay-all") { request, context -> ReplayRecentAudioAllResponse in
        let payload = try await request.decode(as: ReplayRecentAudioRequestPayload.self, context: context)
        return try await host.replayRecentAudioAll(
            mode: payload.replayMode ?? .enqueueNext,
            requestContext: payload.resolvedRequestContext(
                defaults: httpRecentGeneratedAudioRequestContextDefaults(
                    route: "/playback/recent-generated-audio/replay-all",
                ),
            ),
        )
    }

    router.delete("playback/recent-generated-audio") { _, _ -> RecentGeneratedAudioResponse in
        await host.clearRecentGeneratedAudio()
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

private func httpRecentGeneratedAudioRequestContextDefaults(route: String) -> SpeechRequestContextDefaults {
    .init(
        reqPurpose: .speech,
        source: "http",
        topic: "recent-generated-audio-replay",
        attributes: [
            "surface": "http",
            "http.method": "POST",
            "http.route": route,
            "server.app": "SpeakSwiftlyServer",
        ],
    )
}
