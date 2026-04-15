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
    Hello from the real resident SpeakSwiftlyServer playback path. This end to end test uses a longer utterance so we can observe startup buffering, queue floor recovery, drain timing, and steady streaming behavior with enough generated audio to make the diagnostics useful instead of noisy.
    """
    static let operatorControlPlaybackText = """
    Hello from the SpeakSwiftlyServer operator control lane. This coverage keeps the first request alive long enough to exercise pause and resume without falling into a trivially short utterance. After the opening section, the text shifts topics so the generated audio does not just repeat one sentence over and over while we are listening for queue mutations. We then move into a calmer wrap up that still leaves enough duration for queued cancellation and queue clearing to happen while the first playback-owned request continues draining toward completion.
    """
}

protocol E2ESuiteSupport {}

extension E2ESuiteSupport {
    static var testingProfileText: String { ServerE2E.testingProfileText }
    static var testingProfileVoiceDescription: String { ServerE2E.testingProfileVoiceDescription }
    static var operatorControlPlaybackText: String { ServerE2E.operatorControlPlaybackText }
    static var e2eTimeout: Duration { ServerE2E.e2eTimeout }
    static var isPlaybackTraceEnabled: Bool { ServerE2E.isPlaybackTraceEnabled }

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

    static func createVoiceDesignProfile(
        using client: E2EHTTPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "masc",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil,
    ) async throws {
        try await ServerE2E.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            vibe: vibe,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            cwd: cwd,
        )
    }

    static func createVoiceDesignProfile(
        using client: E2EMCPClient,
        server: ServerProcess,
        profileName: String,
        vibe: String = "masc",
        text: String,
        voiceDescription: String,
        outputPath: String? = nil,
        cwd: String? = nil,
    ) async throws {
        try await ServerE2E.createVoiceDesignProfile(
            using: client,
            server: server,
            profileName: profileName,
            vibe: vibe,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            cwd: cwd,
        )
    }

    static func assertProfileIsVisible(using client: E2EHTTPClient, profileName: String) async throws {
        try await ServerE2E.assertProfileIsVisible(using: client, profileName: profileName)
    }

    static func assertProfileIsVisible(using client: E2EMCPClient, profileName: String) async throws {
        try await ServerE2E.assertProfileIsVisible(using: client, profileName: profileName)
    }

    static func assertProfileIsNotVisible(using client: E2EHTTPClient, profileName: String) async throws {
        try await ServerE2E.assertProfileIsNotVisible(using: client, profileName: profileName)
    }

    static func submitSpeechJob(using client: E2EHTTPClient, text: String, profileName: String) async throws -> String {
        try await ServerE2E.submitSpeechJob(using: client, text: text, profileName: profileName)
    }

    static func waitForPlaybackState(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping @Sendable (E2EPlaybackStateSnapshot) -> Bool,
    ) async throws -> E2EPlaybackStateSnapshot {
        try await ServerE2E.waitForPlaybackState(using: client, timeout: timeout, matching: predicate)
    }

    static func waitForGenerationQueue(
        using client: E2EHTTPClient,
        timeout: Duration,
        matching predicate: @escaping @Sendable (E2EQueueSnapshotResponse) -> Bool,
    ) async throws -> E2EQueueSnapshotResponse {
        try await ServerE2E.waitForGenerationQueue(using: client, timeout: timeout, matching: predicate)
    }

    static func waitForMCPPlaybackState(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping @Sendable (E2EPlaybackStateSnapshot) -> Bool,
    ) async throws -> E2EPlaybackStateSnapshot {
        try await ServerE2E.waitForMCPPlaybackState(using: client, timeout: timeout, matching: predicate)
    }

    static func waitForMCPGenerationQueue(
        using client: E2EMCPClient,
        timeout: Duration,
        matching predicate: @escaping @Sendable (E2EQueueSnapshotResponse) -> Bool,
    ) async throws -> E2EQueueSnapshotResponse {
        try await ServerE2E.waitForMCPGenerationQueue(using: client, timeout: timeout, matching: predicate)
    }

    static func assertSpeechJobCancelled(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        ServerE2E.assertSpeechJobCancelled(snapshot, expectedJobID: jobID)
    }

    static func assertSpeechJobCompleted(_ snapshot: E2EJobSnapshot, expectedJobID jobID: String) {
        ServerE2E.assertSpeechJobCompleted(snapshot, expectedJobID: jobID)
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
struct HTTPWorkflowE2ETests: E2ESuiteSupport {}

@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1",
        "Set SPEAKSWIFTLYSERVER_E2E=1 to run live end-to-end coverage.",
    ),
)
struct MCPWorkflowE2ETests: E2ESuiteSupport {}

@Suite(
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SPEAKSWIFTLYSERVER_E2E"] == "1",
        "Set SPEAKSWIFTLYSERVER_E2E=1 to run live end-to-end coverage.",
    ),
)
struct ControlE2ETests: E2ESuiteSupport {}
