import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import TextForSpeech

// MARK: - Mock Speech Generation

@available(macOS 14, *)
extension MockRuntime {
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let request = MockRequest(id: requestID, operation: "generate_speech", profileName: profileName)
        queuedSpeechInvocations.append(
            .init(
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                normalizationContext: normalizationContext,
                sourceFormat: sourceFormat,
            ),
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a speech request continuation for request '\(requestID)'.")
        }

        continuation.yield(.acknowledged(.init(id: requestID)))

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
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let artifactID = "\(requestID)-artifact-1"
        let createdAt = Date()
        let generatedFile = requireFixture("single generated file artifact '\(artifactID)'") {
            try makeGeneratedFile(
                artifactID: artifactID,
                createdAt: createdAt,
                profileName: profileName,
                textProfileName: textProfileName,
                sampleRate: 24000,
                filePath: "/tmp/\(artifactID).wav",
            )
        }
        generatedFiles.append(generatedFile)
        let items = [
            GenerationJobItemFixture(
                artifactID: artifactID,
                text: text,
                textProfileName: textProfileName,
                textContext: normalizationContext,
                sourceFormat: sourceFormat,
            ),
        ]
        let artifacts = [
            GenerationArtifactFixture(
                artifactID: artifactID,
                kind: "audio_wav",
                createdAt: createdAt,
                filePath: generatedFile.filePath,
                sampleRate: generatedFile.sampleRate,
                profileName: profileName,
                textProfileName: textProfileName,
            ),
        ]
        generationJobs.append(
            requireFixture("single generation job '\(requestID)'") {
                try makeGenerationJob(
                    jobID: requestID,
                    jobKind: "file",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    profileName: profileName,
                    textProfileName: textProfileName,
                    speechBackend: "qwen3",
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
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFile: generatedFile, activeRequests: nil)))
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
            requireFixture("batch generated file artifact '\(item.artifactID ?? "\(requestID)-artifact-\(index + 1)")'") {
                try makeGeneratedFile(
                    artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                    createdAt: createdAt,
                    profileName: profileName,
                    textProfileName: item.textProfileName,
                    sampleRate: 24000,
                    filePath: "/tmp/\(item.artifactID ?? "\(requestID)-artifact-\(index + 1)").wav",
                )
            }
        }
        generatedFiles.append(contentsOf: artifacts)
        let batchItems = items.enumerated().map { index, item in
            GenerationJobItemFixture(
                artifactID: item.artifactID ?? "\(requestID)-artifact-\(index + 1)",
                text: item.text,
                textProfileName: item.textProfileName,
                textContext: item.textContext,
                sourceFormat: item.sourceFormat,
            )
        }
        let generatedBatch = requireFixture("generated batch '\(requestID)'") {
            try makeGeneratedBatch(
                batchID: requestID,
                profileName: profileName,
                textProfileName: items.first?.textProfileName,
                speechBackend: "qwen3",
                state: "completed",
                items: batchItems,
                artifacts: artifacts.map {
                    GeneratedFileFixture(
                        artifactID: $0.artifactID,
                        createdAt: $0.createdAt,
                        profileName: $0.profileName,
                        textProfileName: $0.textProfileName,
                        sampleRate: $0.sampleRate,
                        filePath: $0.filePath,
                    )
                },
                createdAt: createdAt,
                updatedAt: createdAt,
                startedAt: createdAt,
                completedAt: createdAt,
                failedAt: nil,
                expiresAt: nil,
                retentionPolicy: "manual",
            )
        }
        generatedBatches.append(generatedBatch)
        generationJobs.append(
            requireFixture("batch generation job '\(requestID)'") {
                try makeGenerationJob(
                    jobID: requestID,
                    jobKind: "batch",
                    createdAt: createdAt,
                    updatedAt: createdAt,
                    profileName: profileName,
                    textProfileName: items.first?.textProfileName,
                    speechBackend: "qwen3",
                    state: "completed",
                    items: batchItems,
                    artifacts: generatedBatch.artifacts.map {
                        GenerationArtifactFixture(
                            artifactID: $0.artifactID,
                            kind: "audio_wav",
                            createdAt: $0.createdAt,
                            filePath: $0.filePath,
                            sampleRate: $0.sampleRate,
                            profileName: $0.profileName,
                            textProfileName: $0.textProfileName,
                        )
                    },
                    startedAt: generatedBatch.startedAt,
                    completedAt: generatedBatch.completedAt,
                    failedAt: nil,
                    expiresAt: nil,
                    retentionPolicy: "manual",
                )
            },
        )
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatch: generatedBatch, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "generate_batch", profileName: profileName, events: events)
    }
}
