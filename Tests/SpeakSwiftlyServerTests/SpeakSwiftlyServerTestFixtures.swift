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

func testRuntimeConfigurationStore() -> RuntimeConfigurationStore {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    return RuntimeConfigurationStore(
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

// MARK: - GeneratedFileFixture

struct GeneratedFileFixture: Codable {
    let artifactID: String
    let createdAt: Date
    let profileName: String
    let textProfileName: String?
    let sampleRate: Int
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case createdAt = "created_at"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case sampleRate = "sample_rate"
        case filePath = "file_path"
    }
}

// MARK: - GenerationArtifactFixture

struct GenerationArtifactFixture: Codable {
    let artifactID: String
    let kind: String
    let createdAt: Date
    let filePath: String
    let sampleRate: Int
    let profileName: String
    let textProfileName: String?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case kind
        case createdAt = "created_at"
        case filePath = "file_path"
        case sampleRate = "sample_rate"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
    }
}

// MARK: - GenerationJobItemFixture

struct GenerationJobItemFixture: Codable {
    let artifactID: String
    let text: String
    let textProfileName: String?
    let textContext: TextForSpeech.Context?
    let sourceFormat: TextForSpeech.SourceFormat?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileName = "text_profile_name"
        case textContext = "text_context"
        case sourceFormat = "source_format"
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
    let profileName: String
    let textProfileName: String?
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
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
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

// MARK: - GeneratedBatchFixture

struct GeneratedBatchFixture: Codable {
    let batchID: String
    let profileName: String
    let textProfileName: String?
    let speechBackend: String
    let state: String
    let items: [GenerationJobItemFixture]
    let artifacts: [GeneratedFileFixture]
    let failure: GenerationJobFailureFixture?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let failedAt: Date?
    let expiresAt: Date?
    let retentionPolicy: String

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case speechBackend = "speech_backend"
        case state
        case items
        case artifacts
        case failure
        case createdAt = "created_at"
        case updatedAt = "updated_at"
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

func makeGeneratedFile(
    artifactID: String,
    createdAt: Date,
    profileName: String,
    textProfileName: String?,
    sampleRate: Int,
    filePath: String,
) throws -> SpeakSwiftly.GeneratedFile {
    try fixtureDecode(
        GeneratedFileFixture(
            artifactID: artifactID,
            createdAt: createdAt,
            profileName: profileName,
            textProfileName: textProfileName,
            sampleRate: sampleRate,
            filePath: filePath,
        ),
        as: SpeakSwiftly.GeneratedFile.self,
    )
}

func makeGenerationJob(
    jobID: String,
    jobKind: String,
    createdAt: Date,
    updatedAt: Date,
    profileName: String,
    textProfileName: String?,
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
            profileName: profileName,
            textProfileName: textProfileName,
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

func makeGeneratedBatch(
    batchID: String,
    profileName: String,
    textProfileName: String?,
    speechBackend: String,
    state: String,
    items: [GenerationJobItemFixture],
    artifacts: [GeneratedFileFixture],
    failure: GenerationJobFailureFixture? = nil,
    createdAt: Date,
    updatedAt: Date,
    startedAt: Date?,
    completedAt: Date?,
    failedAt: Date?,
    expiresAt: Date?,
    retentionPolicy: String,
) throws -> SpeakSwiftly.GeneratedBatch {
    try fixtureDecode(
        GeneratedBatchFixture(
            batchID: batchID,
            profileName: profileName,
            textProfileName: textProfileName,
            speechBackend: speechBackend,
            state: state,
            items: items,
            artifacts: artifacts,
            failure: failure,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            failedAt: failedAt,
            expiresAt: expiresAt,
            retentionPolicy: retentionPolicy,
        ),
        as: SpeakSwiftly.GeneratedBatch.self,
    )
}
