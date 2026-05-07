import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing
import TextForSpeech

// MARK: - EmbeddedSessionLifecycleProbe

@available(macOS 14, *)
actor EmbeddedSessionLifecycleProbe {
    private var requestStopCallCount = 0
    private var waitUntilStoppedCallCount = 0

    func recordRequestStop() {
        requestStopCallCount += 1
    }

    func recordWaitUntilStopped() {
        waitUntilStoppedCallCount += 1
    }

    func counts() -> (requestStop: Int, waitUntilStopped: Int) {
        (requestStopCallCount, waitUntilStoppedCallCount)
    }
}

func testConfiguration(
    defaultVoiceProfileName: String? = nil,
    sseHeartbeatSeconds: Double = 0.05,
    completedJobTTLSeconds: Double = 30,
    completedJobMaxCount: Int = 20,
    jobPruneIntervalSeconds: Double = 0.05,
) -> ServerConfiguration {
    .init(
        name: "speak-swiftly-server-tests",
        environment: "test",
        defaultVoiceProfileName: defaultVoiceProfileName,
        host: "127.0.0.1",
        port: 7337,
        sseHeartbeatSeconds: sseHeartbeatSeconds,
        completedJobTTLSeconds: completedJobTTLSeconds,
        completedJobMaxCount: completedJobMaxCount,
        jobPruneIntervalSeconds: jobPruneIntervalSeconds,
    )
}

func testHTTPConfig(_ configuration: ServerConfiguration) -> HTTPConfig {
    .init(
        enabled: true,
        host: configuration.host,
        port: configuration.port,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds,
    )
}

func testRuntimeStartupConfigurationStore() -> RuntimeStartupConfigurationStore {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    return RuntimeStartupConfigurationStore(
        environment: [
            "SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.standardizedFileURL.path,
        ],
    )
}

func sampleProfile() -> SpeakSwiftly.ProfileSummary {
    .init(
        profileName: "default",
        vibe: .femme,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        voiceDescription: "Warm and clear",
        sourceText: "A reference voice sample.",
        transcriptSource: nil,
        transcriptResolvedAt: nil,
        transcriptionModelRepo: nil,
    )
}

func sampleSystemProfiles() -> [SpeakSwiftly.ProfileSummary] {
    [
        .init(
            profileName: "swift-signal",
            vibe: .femme,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            voiceDescription: "Bundled SpeakSwiftly signal voice.",
            sourceText: "Bundled system profile source text.",
            author: .system,
            seedID: "swift.signal",
            seedVersion: "1",
            transcriptSource: nil,
            transcriptResolvedAt: nil,
            transcriptionModelRepo: nil,
        ),
        .init(
            profileName: "swift-anchor",
            vibe: .masc,
            createdAt: Date(timeIntervalSince1970: 1_700_000_200),
            voiceDescription: "Bundled SpeakSwiftly anchor voice.",
            sourceText: "Bundled system profile source text.",
            author: .system,
            seedID: "swift.anchor",
            seedVersion: "1",
            transcriptSource: nil,
            transcriptResolvedAt: nil,
            transcriptionModelRepo: nil,
        ),
    ]
}

// MARK: - GenerationArtifactFixture

struct GenerationArtifactFixture: Codable {
    let artifactID: String
    let kind: String
    let createdAt: Date
    let filePath: String
    let sampleRate: Int
    let voiceProfile: String
    let textProfile: String?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestContext: TextForSpeech.RequestContext?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case kind
        case createdAt = "created_at"
        case filePath = "file_path"
        case sampleRate = "sample_rate"
        case voiceProfile = "voice_profile"
        case textProfile = "text_profile"
        case sourceFormat = "source_format"
        case requestContext = "request_context"
    }
}

// MARK: - GenerationJobItemFixture

struct GenerationJobItemFixture: Codable {
    let artifactID: String
    let text: String
    let textProfile: String?
    let sourceFormat: TextForSpeech.SourceFormat?
    let requestContext: TextForSpeech.RequestContext?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfile = "text_profile"
        case sourceFormat = "source_format"
        case requestContext = "request_context"
    }
}

// MARK: - GenerationJobFailureFixture

struct GenerationJobFailureFixture: Codable {
    let code: String
    let message: String
}

// MARK: - GenerationJobFixture

struct GenerationJobFixture: Codable {
    let jobID: String
    let jobKind: String
    let createdAt: Date
    let updatedAt: Date
    let voiceProfile: String
    let textProfile: String?
    let speechBackend: String
    let state: String
    let items: [GenerationJobItemFixture]
    let artifacts: [GenerationArtifactFixture]
    let failure: GenerationJobFailureFixture?
    let startedAt: Date?
    let completedAt: Date?
    let failedAt: Date?
    let expiresAt: Date?
    let retentionPolicy: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case jobKind = "job_kind"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case voiceProfile = "voice_profile"
        case textProfile = "text_profile"
        case speechBackend = "speech_backend"
        case state
        case items
        case artifacts
        case failure
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case failedAt = "failed_at"
        case expiresAt = "expires_at"
        case retentionPolicy = "retention_policy"
    }
}

func fixtureDecode<T: Decodable>(_ payload: some Encodable, as type: T.Type) throws -> T {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    return try decoder.decode(type, from: encoder.encode(payload))
}

func requireFixture<T>(
    _ description: String,
    _ build: () throws -> T,
) -> T {
    do {
        return try build()
    } catch {
        fatalError("The test fixture builder for \(description) failed unexpectedly: \(error)")
    }
}

func makeGenerationArtifact(
    artifactID: String,
    createdAt: Date,
    voiceProfile: String,
    textProfile: String?,
    sourceFormat: TextForSpeech.SourceFormat? = nil,
    requestContext: TextForSpeech.RequestContext? = nil,
    sampleRate: Int,
    filePath: String,
) throws -> SpeakSwiftly.GenerationArtifact {
    try fixtureDecode(
        GenerationArtifactFixture(
            artifactID: artifactID,
            kind: "audio_wav",
            createdAt: createdAt,
            filePath: filePath,
            sampleRate: sampleRate,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            sourceFormat: sourceFormat,
            requestContext: requestContext,
        ),
        as: SpeakSwiftly.GenerationArtifact.self,
    )
}

func makeGenerationJob(
    jobID: String,
    jobKind: String,
    createdAt: Date,
    updatedAt: Date,
    voiceProfile: String,
    textProfile: String?,
    speechBackend: String,
    state: String,
    items: [GenerationJobItemFixture],
    artifacts: [GenerationArtifactFixture],
    failure: GenerationJobFailureFixture? = nil,
    startedAt: Date?,
    completedAt: Date?,
    failedAt: Date?,
    expiresAt: Date?,
    retentionPolicy: String,
) throws -> SpeakSwiftly.GenerationJob {
    try fixtureDecode(
        GenerationJobFixture(
            jobID: jobID,
            jobKind: jobKind,
            createdAt: createdAt,
            updatedAt: updatedAt,
            voiceProfile: voiceProfile,
            textProfile: textProfile,
            speechBackend: speechBackend,
            state: state,
            items: items,
            artifacts: artifacts,
            failure: failure,
            startedAt: startedAt,
            completedAt: completedAt,
            failedAt: failedAt,
            expiresAt: expiresAt,
            retentionPolicy: retentionPolicy,
        ),
        as: SpeakSwiftly.GenerationJob.self,
    )
}
