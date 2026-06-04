import Foundation
import SpeakSwiftly

package struct RecentGeneratedAudioResponse: Encodable {
    package let recentGeneratedAudio: SpeakSwiftly.RecentGeneratedAudioSnapshot

    enum CodingKeys: String, CodingKey {
        case recentGeneratedAudio = "recent_generated_audio"
    }
}

package struct RecentGeneratedAudioChunksResponse: Encodable {
    package let recentAudioID: String
    package let chunks: [SpeakSwiftly.GeneratedAudioChunk]

    enum CodingKeys: String, CodingKey {
        case recentAudioID = "recent_audio_id"
        case chunks
    }
}

package struct ReplayRecentAudioRequestPayload: Decodable {
    package let replayMode: SpeakSwiftly.RecentGeneratedAudioReplayMode?
    package let requestContext: SpeechRequestContextPayload?
    package let cwd: String?
    package let repoRoot: String?

    enum CodingKeys: String, CodingKey {
        case replayMode = "replay_mode"
        case requestContext = "request_context"
        case cwd
        case repoRoot = "repo_root"
    }

    package init(
        replayMode: SpeakSwiftly.RecentGeneratedAudioReplayMode?,
        requestContext: SpeechRequestContextPayload?,
        cwd: String?,
        repoRoot: String?,
    ) {
        self.replayMode = replayMode
        self.requestContext = requestContext
        self.cwd = cwd
        self.repoRoot = repoRoot
    }

    package func resolvedRequestContext(defaults: SpeechRequestContextDefaults) -> SpeakSwiftly.RequestContext? {
        makeSpeechRequestContext(
            cwd: cwd,
            repoRoot: repoRoot,
            requestContext: requestContext,
            defaults: defaults,
        )
    }
}

package struct ReplayRecentAudioResponse: Encodable {
    package let requestID: String

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
    }
}

package struct ReplayRecentAudioAllResponse: Encodable {
    package let requestIDs: [String]

    enum CodingKeys: String, CodingKey {
        case requestIDs = "request_ids"
    }
}
