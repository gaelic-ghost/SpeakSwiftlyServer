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
                author: .user,
                seedID: nil,
                seedVersion: nil,
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
                    author: .user,
                    seedID: nil,
                    seedVersion: nil,
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

    func createSystemVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        seed: SpeakSwiftly.ProfileSeed,
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
                author: .system,
                seedID: seed.seedID,
                seedVersion: seed.seedVersion,
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
                    author: .system,
                    seedID: seed.seedID,
                    seedVersion: seed.seedVersion,
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
        return RuntimeRequestHandle(id: requestID, operation: "create_system_voice_profile_from_description", profileName: profileName, events: events)
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
                    author: .user,
                    seedID: nil,
                    seedVersion: nil,
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
        if holdNextListVoiceProfiles {
            holdNextListVoiceProfiles = false
            listVoiceProfilesHasReachedHold = true
            let holdWaiters = listVoiceProfilesHoldWaiters
            listVoiceProfilesHoldWaiters.removeAll()
            for waiter in holdWaiters {
                waiter.resume()
            }
            await withCheckedContinuation { continuation in
                listVoiceProfilesHoldContinuation = continuation
            }
        }
        listVoiceProfilesCallCount += 1
        if !listVoiceProfilesFailureMessages.isEmpty {
            let message = listVoiceProfilesFailureMessages.removeFirst()
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(throwing: SpeakSwiftly.Error(code: .internalError, message: message))
            }
            return RuntimeRequestHandle(id: requestID, operation: "list_voice_profiles", profileName: nil, events: events)
        }
        if !scriptedProfileRefreshSnapshots.isEmpty {
            profiles = scriptedProfileRefreshSnapshots.removeFirst()
        }
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
                    author: profile.author,
                    seedID: profile.seedID,
                    seedVersion: profile.seedVersion,
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
        if mutationRefreshBehavior == .applyMutations {
            profiles = profiles.map { profile in
                guard profile.profileName == profileName else { return profile }

                return SpeakSwiftly.ProfileSummary(
                    profileName: profile.profileName,
                    vibe: profile.vibe,
                    createdAt: profile.createdAt.addingTimeInterval(60),
                    voiceDescription: "\(profile.voiceDescription) (rerolled)",
                    sourceText: "\(profile.sourceText) (rerolled)",
                    transcriptSource: profile.transcriptSource,
                    transcriptResolvedAt: profile.transcriptResolvedAt,
                    transcriptionModelRepo: profile.transcriptionModelRepo,
                )
            }
        }
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
        generationJobs[index] = requireFixture("expired generation job '\(current.jobID)'") {
            try makeGenerationJob(
                jobID: current.jobID,
                jobKind: current.jobKind.rawValue,
                createdAt: current.createdAt,
                updatedAt: Date(),
                voiceProfile: current.voiceProfile,
                textProfile: current.textProfile,
                speechBackend: current.speechBackend.rawValue,
                state: "expired",
                items: current.items.map {
                    GenerationJobItemFixture(
                        artifactID: $0.artifactID,
                        text: $0.text,
                        textProfile: $0.textProfile,
                        inputTextContext: $0.inputTextContext,
                        requestContext: $0.requestContext,
                    )
                },
                artifacts: current.artifacts.map {
                    GenerationArtifactFixture(
                        artifactID: $0.artifactID,
                        kind: $0.kind.rawValue,
                        createdAt: $0.createdAt,
                        filePath: $0.filePath,
                        sampleRate: $0.sampleRate,
                        voiceProfile: $0.voiceProfile,
                        textProfile: $0.textProfile,
                        inputTextContext: $0.inputTextContext,
                        requestContext: $0.requestContext,
                    )
                },
                failure: current.failure.map { .init(code: $0.code, message: $0.message) },
                startedAt: current.startedAt,
                completedAt: current.completedAt,
                failedAt: current.failedAt,
                expiresAt: current.expiresAt,
                retentionPolicy: current.retentionPolicy.rawValue,
            )
        }
        let expiredJob = generationJobs[index]
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generationJob: expiredJob, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "expire_generation_job", profileName: nil, events: events)
    }

    func generationArtifact(id artifactID: String) async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let file = generatedFiles.first { $0.artifactID == artifactID }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFile: file, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "get_generation_artifact", profileName: nil, events: events)
    }

    func listGenerationArtifacts() async -> RuntimeRequestHandle {
        let requestID = UUID().uuidString
        let files = generatedFiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, generatedFiles: files, activeRequests: nil)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "list_generation_artifacts", profileName: nil, events: events)
    }
}
