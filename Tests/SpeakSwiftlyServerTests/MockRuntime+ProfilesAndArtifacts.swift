import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer

// MARK: - Mock Profiles And Artifacts

@available(macOS 14, *)
extension MockRuntime {
    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        createProfileInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: cwd,
            ),
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: voiceDescription,
                    sourceText: text,
                    transcriptSource: nil,
                    transcriptResolvedAt: nil,
                    transcriptionModelRepo: nil,
                ),
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "create_voice_profile_from_description", profileName: profileName, events: events)
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        createCloneInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                referenceAudioPath: referenceAudioPath,
                transcript: transcript,
                cwd: cwd,
            ),
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: "Imported reference audio clone.",
                    sourceText: transcript ?? "Imported clone transcript.",
                    transcriptSource: transcript == nil ? .inferred : .provided,
                    transcriptResolvedAt: Date(),
                    transcriptionModelRepo: nil,
                ),
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "create_voice_profile_from_audio", profileName: profileName, events: events)
    }

    func listVoiceProfiles() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        listVoiceProfilesCallCount += 1
        let profiles = profiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profiles: profiles, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_voice_profiles", profileName: nil, events: events)
    }

    func voiceProfileRefreshCount() -> Int {
        listVoiceProfilesCallCount
    }

    func renameVoiceProfile(profileName: String, to newProfileName: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        renameProfileInvocations.append(.init(profileName: profileName, newProfileName: newProfileName))
        if mutationRefreshBehavior == .applyMutations {
            profiles = profiles.map { profile in
                guard profile.profileName == profileName else { return profile }

                return SpeakSwiftly.ProfileSummary(
                    profileName: newProfileName,
                    vibe: profile.vibe,
                    createdAt: profile.createdAt,
                    voiceDescription: profile.voiceDescription,
                    sourceText: profile.sourceText,
                    transcriptSource: profile.transcriptSource,
                    transcriptResolvedAt: profile.transcriptResolvedAt,
                    transcriptionModelRepo: profile.transcriptionModelRepo,
                )
            }
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: newProfileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "update_voice_profile_name", profileName: newProfileName, events: events)
    }

    func rerollVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        rerollProfileInvocations.append(.init(profileName: profileName))
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "reroll_voice_profile", profileName: profileName, events: events)
    }

    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        if mutationRefreshBehavior == .applyMutations {
            profiles.removeAll { $0.profileName == profileName }
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, profileName: profileName, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "delete_voice_profile", profileName: profileName, events: events)
    }

    func generationJob(id jobID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let job = generationJobs.first { $0.jobID == jobID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJob: job, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generation_job", profileName: nil, events: events)
    }

    func listGenerationJobs() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let jobs = generationJobs
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJobs: jobs, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generation_jobs", profileName: nil, events: events)
    }

    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        guard let index = generationJobs.firstIndex(where: { $0.jobID == jobID }) else {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(
                    throwing: SpeakSwiftly.Error(
                        code: .generationJobNotFound,
                        message: "No mock generation job matched '\(jobID)'.",
                    ),
                )
            }
            return RuntimeRequestHandle(id: requestID, operation: "expire_generation_job", profileName: nil, events: events)
        }

        let current = generationJobs[index]
        generationJobs[index] = try! makeGenerationJob(
            jobID: current.jobID,
            jobKind: current.jobKind.rawValue,
            createdAt: current.createdAt,
            updatedAt: Date(),
            profileName: current.profileName,
            textProfileName: current.textProfileName,
            speechBackend: current.speechBackend.rawValue,
            state: "expired",
            items: current.items.map {
                GenerationJobItemFixture(
                    artifactID: $0.artifactID,
                    text: $0.text,
                    textProfileName: $0.textProfileName,
                    textContext: $0.textContext,
                    sourceFormat: $0.sourceFormat,
                )
            },
            artifacts: current.artifacts.map {
                GenerationArtifactFixture(
                    artifactID: $0.artifactID,
                    kind: $0.kind.rawValue,
                    createdAt: $0.createdAt,
                    filePath: $0.filePath,
                    sampleRate: $0.sampleRate,
                    profileName: $0.profileName,
                    textProfileName: $0.textProfileName,
                )
            },
            failure: current.failure.map { .init(code: $0.code, message: $0.message) },
            startedAt: current.startedAt,
            completedAt: current.completedAt,
            failedAt: current.failedAt,
            expiresAt: current.expiresAt,
            retentionPolicy: current.retentionPolicy.rawValue,
        )
        let expiredJob = generationJobs[index]
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJob: expiredJob, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "expire_generation_job", profileName: nil, events: events)
    }

    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let file = generatedFiles.first { $0.artifactID == artifactID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFile: file, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generated_file", profileName: nil, events: events)
    }

    func listGeneratedFiles() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let files = generatedFiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFiles: files, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generated_files", profileName: nil, events: events)
    }

    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let batch = generatedBatches.first { $0.batchID == batchID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatch: batch, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generated_batch", profileName: nil, events: events)
    }

    func listGeneratedBatches() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let batches = generatedBatches
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedBatches: batches, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generated_batches", profileName: nil, events: events)
    }
}
