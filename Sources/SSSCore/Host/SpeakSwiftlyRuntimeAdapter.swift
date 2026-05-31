import Foundation
import SpeakSwiftly
import TextForSpeech

package func resolvedAbsoluteFilesystemPath(
    _ path: String?,
    cwd: String?,
    currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
) -> String? {
    guard let path else {
        return nil
    }

    let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedPath.isEmpty == false else {
        return nil
    }

    if trimmedPath.hasPrefix("/") {
        return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
    }

    let trimmedCWD = cwd?.trimmingCharacters(in: .whitespacesAndNewlines)
    let resolvedBasePath: String = if let trimmedCWD, trimmedCWD.isEmpty == false {
        if trimmedCWD.hasPrefix("/") {
            trimmedCWD
        } else {
            URL(
                fileURLWithPath: trimmedCWD,
                relativeTo: URL(fileURLWithPath: currentDirectoryPath, isDirectory: true),
            )
            .standardizedFileURL
            .path
        }
    } else {
        currentDirectoryPath
    }

    return URL(
        fileURLWithPath: trimmedPath,
        relativeTo: URL(fileURLWithPath: resolvedBasePath, isDirectory: true),
    )
    .standardizedFileURL
    .path
}

package actor SpeakSwiftlyRuntimeAdapter: SpeakSwiftlyRuntimeServing {
    private let runtime: SpeakSwiftly.Runtime

    // MARK: - Initialization

    init(runtime: SpeakSwiftly.Runtime) {
        self.runtime = runtime
    }

    func start() async {
        await runtime.start()
    }

    func shutdown() async {
        await runtime.shutdown()
    }

    func runtimeUpdates() async -> AsyncStream<SpeakSwiftly.RuntimeUpdate> {
        await runtime.updates()
    }

    func runtimeSnapshot() async -> SpeakSwiftly.RuntimeSnapshot {
        await runtime.snapshot()
    }

    func generationSnapshot() async -> SpeakSwiftly.GenerateSnapshot {
        await runtime.generate.snapshot()
    }

    func playbackUpdates() async -> AsyncStream<SpeakSwiftly.PlaybackUpdate> {
        await runtime.playback.updates()
    }

    func playbackSnapshot() async -> SpeakSwiftly.PlaybackSnapshot {
        await runtime.playback.snapshot()
    }

    // MARK: - Speech Requests

    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.speech(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfileID,
            requestContext: requestContext,
            qwenPreModelTextChunking: qwenPreModelTextChunking,
        )
        return .init(id: handle.id, operation: "generate_speech", profileName: profileName, events: handle.events)
    }

    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.audio(
            text: text,
            voiceProfile: profileName,
            textProfile: textProfileID,
            requestContext: requestContext,
        )
        return .init(id: handle.id, operation: "generate_audio_file", profileName: profileName, events: handle.events)
    }

    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.batch(items, voiceProfile: profileName)
        return .init(id: handle.id, operation: "generate_batch", profileName: profileName, events: handle.events)
    }

    // MARK: - Voice Profiles

    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.create(
            design: profileName,
            from: text,
            vibe: vibe,
            voiceDescription: voiceDescription,
            outputPath: resolvedAbsoluteFilesystemPath(outputPath, cwd: cwd),
        )
        return .init(id: handle.id, operation: "create_voice_profile_from_description", profileName: profileName, events: handle.events)
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle {
        let resolvedReferenceAudioPath = resolvedAbsoluteFilesystemPath(referenceAudioPath, cwd: cwd) ?? referenceAudioPath
        let handle = await runtime.voices.create(
            clone: profileName,
            from: URL(fileURLWithPath: resolvedReferenceAudioPath),
            vibe: vibe,
            transcript: transcript,
        )
        return .init(id: handle.id, operation: "create_voice_profile_from_audio", profileName: profileName, events: handle.events)
    }

    func listVoiceProfiles() async -> RuntimeRequestHandle {
        let handle = await runtime.voices.list()
        return .init(id: handle.id, operation: "voice_profiles_snapshot", profileName: nil, events: handle.events)
    }

    func renameVoiceProfile(profileName: String, to newProfileName: String) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.rename(profileName, to: newProfileName)
        return .init(id: handle.id, operation: "update_voice_profile_name", profileName: newProfileName, events: handle.events)
    }

    func rerollVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.reroll(profileName)
        return .init(id: handle.id, operation: "reroll_voice_profile", profileName: profileName, events: handle.events)
    }

    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.delete(named: profileName)
        return .init(id: handle.id, operation: "delete_voice_profile", profileName: profileName, events: handle.events)
    }

    // MARK: - Runtime Jobs and Artifacts

    func generationJob(id jobID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.job(id: jobID)
        return .init(id: handle.id, operation: "generation_job_snapshot", profileName: nil, events: handle.events)
    }

    func listGenerationJobs() async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.list()
        return .init(id: handle.id, operation: "generation_jobs_snapshot", profileName: nil, events: handle.events)
    }

    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.expire(id: jobID)
        return .init(id: handle.id, operation: "expire_generation_job", profileName: nil, events: handle.events)
    }

    func generationArtifact(id artifactID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.artifact(id: artifactID)
        return .init(id: handle.id, operation: "get_generation_artifact", profileName: nil, events: handle.events)
    }

    func listGenerationArtifacts() async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts()
        return .init(id: handle.id, operation: "list_generation_artifacts", profileName: nil, events: handle.events)
    }

    // MARK: - Runtime Controls

    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle {
        let handle = await runtime.switchSpeechBackend(to: speechBackend)
        return .init(id: handle.id, operation: "switch_speech_backend", profileName: nil, events: handle.events)
    }

    func reloadModels() async -> RuntimeRequestHandle {
        let handle = await runtime.reloadModels()
        return .init(id: handle.id, operation: "reload_models", profileName: nil, events: handle.events)
    }

    func unloadModels() async -> RuntimeRequestHandle {
        let handle = await runtime.unloadModels()
        return .init(id: handle.id, operation: "unload_models", profileName: nil, events: handle.events)
    }

    func pausePlayback() async -> RuntimeRequestHandle {
        let handle = await runtime.playback.pause()
        return RuntimeRequestHandle(handle)
    }

    func resumePlayback() async -> RuntimeRequestHandle {
        let handle = await runtime.playback.resume()
        return RuntimeRequestHandle(handle)
    }

    func clearQueue() async -> RuntimeRequestHandle {
        let handle = await runtime.playback.clearQueue()
        return RuntimeRequestHandle(handle)
    }

    func clearQueue(_ queueType: SpeakSwiftly.QueueType) async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.clearQueue(queueType))
    }

    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.playback.cancelRequest(requestID)
        return RuntimeRequestHandle(handle)
    }

    func cancel(_ queueType: SpeakSwiftly.QueueType, requestID: String) async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.cancel(queueType, requestID: requestID))
    }

    // MARK: - Text Profiles

    func builtInTextProfileStyle() async -> TextForSpeech.BuiltInProfileStyle {
        await runtime.normalizer.style.getActive()
    }

    func setBuiltInTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws -> TextForSpeech.BuiltInProfileStyle {
        try await runtime.normalizer.style.setActive(to: style)
        return await runtime.normalizer.style.getActive()
    }

    func activeTextProfile() async throws -> SpeakSwiftly.TextProfileDetails {
        await runtime.normalizer.profiles.getActive()
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        let style = await runtime.normalizer.style.getActive()
        return .builtInBase(style: style)
    }

    func textProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails? {
        guard let details = try? await runtime.normalizer.profiles.get(id: profileID) else {
            return nil
        }

        return details
    }

    func textProfiles() async throws -> [SpeakSwiftly.TextProfileSummary] {
        await runtime.normalizer
            .profiles
            .list()
    }

    func effectiveTextProfile(id profileID: String?) async throws -> SpeakSwiftly.TextProfileDetails {
        if let profileID,
           let details = try? await runtime.normalizer.profiles.get(id: profileID) {
            return details
        }

        return await runtime.normalizer.profiles.getEffective()
    }

    func loadTextProfiles() async throws {
        try await runtime.normalizer.persistence.load()
    }

    func saveTextProfiles() async throws {
        try await runtime.normalizer.persistence.save()
    }

    func createTextProfile(named name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.create(name: name)
    }

    func renameTextProfile(id profileID: String, to name: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.rename(profile: profileID, to: name)
    }

    func setActiveTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.setActive(id: profileID)
        return await runtime.normalizer.profiles.getActive()
    }

    func removeTextProfile(id profileID: String) async throws {
        try await runtime.normalizer.profiles.delete(id: profileID)
    }

    func factoryResetTextProfiles() async throws {
        try await runtime.normalizer.profiles.factoryReset()
    }

    func resetTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.reset(id: profileID)
        return try await runtime.normalizer.profiles.get(id: profileID)
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.addReplacement(replacement, toProfile: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.patchReplacement(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.patchReplacement(replacement, inProfile: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String,
    ) async throws -> SpeakSwiftly.TextProfileDetails {
        try await runtime.normalizer.profiles.removeReplacement(
            id: replacementID,
            fromProfile: profileID,
        )
    }
}
