import Foundation
import SpeakSwiftly
import SpeakSwiftlyServer
@testable import SSSCore
import SSSHTTP
import SSSMCP
import TextForSpeech

// MARK: - Mock Speech Generation

@available(macOS 14, *)
extension MockRuntime {
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let request = MockRequest(id: requestID, operation: "generate_speech", profileName: profileName)
        queuedSpeechInvocations.append(
            .init(
                text: text,
                profileName: profileName,
                textProfileID: textProfileID,
                requestContext: requestContext,
                qwenPreModelTextChunking: qwenPreModelTextChunking,
            ),
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a speech request continuation for request '\(requestID)'.")
        }

        if activeRequest == nil {
            startActiveRequest(request, continuation: continuation)
        } else {
            queuedRequests.append(.init(request: request, continuation: continuation))
            continuation.yield(
                .queued(
                    .init(
                        id: requestID,
                        reason: .waitingForActiveRequest,
                        queuePosition: queuedRequests.count,
                    ),
                ),
            )
        }

        return RuntimeRequestHandle(id: requestID, operation: request.operation, profileName: profileName, events: events)
    }

    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let artifactID = "\(requestID)-artifact-1"
        let createdAt = Date()
        let artifact = requireFixture("single generation artifact '\(artifactID)'") {
            try makeGenerationArtifact(
                artifactID: artifactID,
                createdAt: createdAt,
                voiceProfile: profileName,
                textProfile: textProfileID,
                sourceFormat: nil,
                requestContext: requestContext,
                sampleRate: 24000,
                filePath: mockArtifactPath("\(artifactID).wav"),
            )
        }
        generationArtifacts.append(artifact)
        let items = [
            GenerationJobItemFixture(
                artifactID: artifactID,
                text: text,
                textProfile: textProfileID,
                sourceFormat: nil,
                requestContext: requestContext,
            ),
        ]
        let artifacts = [
            GenerationArtifactFixture(
                artifactID: artifactID,
                kind: "audio_wav",
                createdAt: createdAt,
                filePath: artifact.filePath,
                sampleRate: artifact.sampleRate,
                voiceProfile: profileName,
                textProfile: textProfileID,
                sourceFormat: nil,
                requestContext: requestContext,
            ),
        ]
        generationJobs.append(
            requireFixture("single generation job '\(requestID)'") {
                try makeGenerationJob(
                    jobID: requestID,
                    jobKind: "file",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    voiceProfile: profileName,
                    textProfile: textProfileID,
                    speechBackend: "qwen3_smol",
                    state: "completed",
                    items: items,
                    artifacts: artifacts,
                    startedAt: createdAt,
                    completedAt: createdAt,
                    failedAt: nil,
                    expiresAt: nil,
                    retentionPolicy: "manual",
                )
            },
        )
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(.artifact(artifact)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generate_audio_file", profileName: profileName, events: events)
    }

    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let createdAt = Date()
        let artifacts = items.enumerated().map { index, item in
            requireFixture("batch generation artifact '\(item.artifactID ?? "\(requestID)-artifact-\(index + 1)")'") {
                try makeGenerationArtifact(
                    artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                    createdAt: createdAt,
                    voiceProfile: profileName,
                    textProfile: item.textProfile,
                    sourceFormat: nil,
                    requestContext: item.requestContext,
                    sampleRate: 24000,
                    filePath: mockArtifactPath("\(item.artifactID ?? "\(requestID)-artifact-\(index + 1)").wav"),
                )
            }
        }
        generationArtifacts.append(contentsOf: artifacts)
        let batchItems = items.enumerated().map { index, item in
            GenerationJobItemFixture(
                artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                text: item.text,
                textProfile: item.textProfile,
                sourceFormat: nil,
                requestContext: item.requestContext,
            )
        }
        let generationJob = requireFixture("batch generation job '\(requestID)'") {
            try makeGenerationJob(
                jobID: requestID,
                jobKind: "batch",
                createdAt: createdAt,
                updatedAt: createdAt,
                voiceProfile: profileName,
                textProfile: items.first?.textProfile,
                speechBackend: "qwen3_smol",
                state: "completed",
                items: batchItems,
                artifacts: artifacts.map {
                    GenerationArtifactFixture(
                        artifactID: $0.artifactID,
                        kind: $0.kind.rawValue,
                        createdAt: $0.createdAt,
                        filePath: $0.filePath,
                        sampleRate: $0.sampleRate,
                        voiceProfile: $0.voiceProfile,
                        textProfile: $0.textProfile,
                        sourceFormat: $0.sourceFormat,
                        requestContext: $0.requestContext,
                    )
                },
                startedAt: createdAt,
                completedAt: createdAt,
                failedAt: nil,
                expiresAt: nil,
                retentionPolicy: "manual",
            )
        }
        generationJobs.append(generationJob)
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(.generationJob(generationJob)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generate_batch", profileName: profileName, events: events)
    }
}

private func mockArtifactPath(_ fileName: String) -> String {
    URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent(fileName, isDirectory: false)
        .path
}
