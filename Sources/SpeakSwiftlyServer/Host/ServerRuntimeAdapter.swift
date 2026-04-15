import Foundation
import SpeakSwiftly
import TextForSpeech

// MARK: - Runtime Adapter

actor ServerRuntimeAdapter: ServerRuntimeProtocol {
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

    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent> {
        await runtime.statusEvents()
    }

    // MARK: - Speech Requests

    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.speech(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: normalizationContext,
            sourceFormat: sourceFormat,
        )
        return .init(id: handle.id, operation: "generate_speech", profileName: profileName, events: handle.events)
    }

    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.audio(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: normalizationContext,
            sourceFormat: sourceFormat,
        )
        return .init(id: handle.id, operation: "generate_audio_file", profileName: profileName, events: handle.events)
    }

    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String,
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.batch(items, with: profileName)
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
            voice: voiceDescription,
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
        return .init(id: handle.id, operation: "list_voice_profiles", profileName: nil, events: handle.events)
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
        return .init(id: handle.id, operation: "get_generation_job", profileName: nil, events: handle.events)
    }

    func listGenerationJobs() async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.list()
        return .init(id: handle.id, operation: "list_generation_jobs", profileName: nil, events: handle.events)
    }

    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.expire(id: jobID)
        return .init(id: handle.id, operation: "expire_generation_job", profileName: nil, events: handle.events)
    }

    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.file(id: artifactID)
        return .init(id: handle.id, operation: "get_generated_file", profileName: nil, events: handle.events)
    }

    func listGeneratedFiles() async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.files()
        return .init(id: handle.id, operation: "list_generated_files", profileName: nil, events: handle.events)
    }

    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.batch(id: batchID)
        return .init(id: handle.id, operation: "get_generated_batch", profileName: nil, events: handle.events)
    }

    func listGeneratedBatches() async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.batches()
        return .init(id: handle.id, operation: "list_generated_batches", profileName: nil, events: handle.events)
    }

    // MARK: - Runtime Controls

    func runtimeStatus() async -> RuntimeRequestHandle {
        let handle = await runtime.status()
        return .init(id: handle.id, operation: "get_runtime_status", profileName: nil, events: handle.events)
    }

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

    func runtimeOverview() async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.overview())
    }

    func playbackState() async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.player.state())
    }

    func pausePlayback() async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.player.pause())
    }

    func resumePlayback() async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.player.resume())
    }

    func clearQueue() async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.player.clearQueue())
    }

    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle {
        await RuntimeRequestHandle(runtime.player.cancelRequest(requestID))
    }

    // MARK: - Text Profiles

    func builtInTextProfileStyle() async -> TextForSpeech.BuiltInProfileStyle {
        await runtime.normalizer.profiles.builtInStyle()
    }

    func setBuiltInTextProfileStyle(
        _ style: TextForSpeech.BuiltInProfileStyle,
    ) async throws -> TextForSpeech.BuiltInProfileStyle {
        try await runtime.normalizer.profiles.setBuiltInStyle(style)
        return await runtime.normalizer.profiles.builtInStyle()
    }

    func activeTextProfile() async -> TextForSpeech.Profile {
        await runtime.normalizer.profiles.active() ?? .default
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        await .builtInBase(style: runtime.normalizer.profiles.builtInStyle())
    }

    func textProfile(id profileID: String) async -> TextForSpeech.Profile? {
        await runtime.normalizer.profiles.stored(id: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        await runtime.normalizer.profiles.list()
    }

    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile {
        await runtime.normalizer.profiles.effective(id: profileID) ?? .default
    }

    func loadTextProfiles() async throws {
        try await runtime.normalizer.persistence.load()
    }

    func saveTextProfiles() async throws {
        try await runtime.normalizer.persistence.save()
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement],
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.create(id: id, name: name, replacements: replacements)
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws {
        try await runtime.normalizer.profiles.store(profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws {
        try await runtime.normalizer.profiles.use(profile)
    }

    func removeTextProfile(id profileID: String) async throws {
        try await runtime.normalizer.profiles.delete(id: profileID)
    }

    func resetTextProfile() async throws {
        try await runtime.normalizer.profiles.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.add(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String,
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.add(replacement, toStoredProfileID: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.replace(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String,
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.replace(replacement, inStoredProfileID: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String,
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.profiles.removeReplacement(
            id: replacementID,
            fromStoredProfileID: profileID,
        )
    }

    // MARK: - Path Resolution

    private func resolvedAbsoluteFilesystemPath(
        _ path: String?,
        cwd: String?,
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
        let resolvedBasePath =
            (trimmedCWD?.isEmpty == false ? trimmedCWD : nil)
                ?? FileManager.default.currentDirectoryPath
        return URL(fileURLWithPath: trimmedPath, relativeTo: URL(fileURLWithPath: resolvedBasePath, isDirectory: true))
            .standardizedFileURL
            .path
    }
}
