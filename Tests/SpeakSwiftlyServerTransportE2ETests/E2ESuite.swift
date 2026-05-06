import Foundation
import Testing
#if canImport(Darwin)
import Darwin
#endif

// MARK: - ServerE2E

enum ServerE2E {
    // MARK: - Test Fixtures

    static let testingProfileText = "Hello there from SpeakSwiftlyServer end-to-end coverage."
    static let testingProfileVoiceDescription = "A generic, warm, masculine, slow speaking voice."
    static let testingCloneSourceText = """
    This imported reference audio should let SpeakSwiftlyServer build a clone profile for end to end coverage with a clean transcript and steady speech.
    """
    static let testingPlaybackText = """
    Hello from the real resident SpeakSwiftlyServer playback path. This smoke coverage keeps one request long enough to prove the live server can accept work, hand it to the published SpeakSwiftly runtime, and retain a completed request snapshot afterward.
    """
}

protocol E2ESuiteSupport {}

extension E2ESuiteSupport {
    static var testingProfileText: String { ServerE2E.testingProfileText }
    static var testingProfileVoiceDescription: String { ServerE2E.testingProfileVoiceDescription }
    static var e2eTimeout: Duration { ServerE2E.e2eTimeout }

    static func randomPort(in range: Range<Int>) -> Int {
        ServerE2E.randomPort(in: range)
    }

    static func makeServer(
        port: Int,
        profileRootURL: URL,
        silentPlayback: Bool,
        playbackTrace: Bool = false,
        mcpEnabled: Bool,
        speechBackend: String? = nil,
    ) throws -> ServerProcess {
        try ServerE2E.makeServer(
            port: port,
            profileRootURL: profileRootURL,
            silentPlayback: silentPlayback,
            playbackTrace: playbackTrace,
            mcpEnabled: mcpEnabled,
            speechBackend: speechBackend,
        )
    }

    static func replacementJSON(
        id: String,
        text: String,
        replacement: String,
        match: String = "exact_phrase",
        phase: String = "before_built_ins",
        isCaseSensitive: Bool = false,
        formats: [String] = [],
        priority: Int = 0,
    ) -> [String: Any] {
        ServerE2E.replacementJSON(
            id: id,
            text: text,
            replacement: replacement,
            match: match,
            phase: phase,
            isCaseSensitive: isCaseSensitive,
            formats: formats,
            priority: priority,
        )
    }

    static func requirePromptText(in result: [String: Any]) throws -> String {
        try ServerE2E.requirePromptText(in: result)
    }

    static func requireObjectPayload(from payload: Any) throws -> [String: Any] {
        try ServerE2E.requireObjectPayload(from: payload)
    }

    static func requireArrayPayload(from payload: Any) throws -> [[String: Any]] {
        try ServerE2E.requireArrayPayload(from: payload)
    }
}

// MARK: - End-to-End Suites

@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1",
        "Set SPEAKSWIFTLYSERVER_E2E=1 to run live end-to-end coverage.",
    ),
)
struct ServerTransportE2ETests: E2ESuiteSupport {}
