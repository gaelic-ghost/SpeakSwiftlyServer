import Foundation
import SpeakSwiftlyCore
import TextForSpeech

typealias SpeechNormalizationContext = TextForSpeech.Context

// MARK: - Runtime Bridge

struct RuntimeRequestHandle: Sendable {
    let id: String
    let operation: String
    let profileName: String?
    let events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>

    // MARK: - Initialization

    init(
        id: String,
        operation: String,
        profileName: String?,
        events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>
    ) {
        self.id = id
        self.operation = operation
        self.profileName = profileName
        self.events = events
    }

    init(_ handle: SpeakSwiftly.RequestHandle) {
        self.id = handle.id
        self.operation = handle.operation
        self.profileName = handle.profileName
        self.events = handle.events
    }
}

// MARK: - Runtime Protocol

protocol ServerRuntimeProtocol: Actor {
    func start()
    func shutdown() async
    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent>
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle
    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle
    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String
    ) async -> RuntimeRequestHandle
    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle
    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle
    func listVoiceProfiles() async -> RuntimeRequestHandle
    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle
    func generationJob(id jobID: String) async -> RuntimeRequestHandle
    func listGenerationJobs() async -> RuntimeRequestHandle
    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle
    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle
    func listGeneratedFiles() async -> RuntimeRequestHandle
    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle
    func listGeneratedBatches() async -> RuntimeRequestHandle
    func runtimeStatus() async -> RuntimeRequestHandle
    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle
    func reloadModels() async -> RuntimeRequestHandle
    func unloadModels() async -> RuntimeRequestHandle
    func generationQueue() async -> RuntimeRequestHandle
    func playbackQueue() async -> RuntimeRequestHandle
    func playbackState() async -> RuntimeRequestHandle
    func pausePlayback() async -> RuntimeRequestHandle
    func resumePlayback() async -> RuntimeRequestHandle
    func clearQueue() async -> RuntimeRequestHandle
    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle
    func activeTextProfile() async -> TextForSpeech.Profile
    func baseTextProfile() async -> TextForSpeech.Profile
    func textProfile(id profileID: String) async -> TextForSpeech.Profile?
    func textProfiles() async -> [TextForSpeech.Profile]
    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile
    func loadTextProfiles() async throws
    func saveTextProfiles() async throws
    func createTextProfile(id: String, named name: String, replacements: [TextForSpeech.Replacement]) async throws -> TextForSpeech.Profile
    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws
    func useTextProfile(_ profile: TextForSpeech.Profile) async throws
    func removeTextProfile(id profileID: String) async throws
    func resetTextProfile() async throws
    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile
    func addTextReplacement(_ replacement: TextForSpeech.Replacement, toStoredTextProfileID profileID: String) async throws -> TextForSpeech.Profile
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement, inStoredTextProfileID profileID: String) async throws -> TextForSpeech.Profile
    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile
    func removeTextReplacement(id replacementID: String, fromStoredTextProfileID profileID: String) async throws -> TextForSpeech.Profile
}

// MARK: - Runtime Adapter

actor ServerRuntimeAdapter: ServerRuntimeProtocol {
    private let runtime: SpeakSwiftly.Runtime

    init(runtime: SpeakSwiftly.Runtime) {
        self.runtime = runtime
    }

    func start() {
        Task {
            await runtime.start()
        }
    }

    func shutdown() async {
        await runtime.shutdown()
    }

    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent> {
        await runtime.statusEvents()
    }

    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.speech(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return .init(id: handle.id, operation: "queue_speech_live", profileName: profileName, events: handle.events)
    }

    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.audio(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            textContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return .init(id: handle.id, operation: "queue_speech_file", profileName: profileName, events: handle.events)
    }

    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.batch(items, with: profileName)
        return .init(id: handle.id, operation: "queue_speech_batch", profileName: profileName, events: handle.events)
    }

    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.create(
            design: profileName,
            from: text,
            vibe: vibe,
            voice: voiceDescription,
            outputPath: resolvedAbsoluteFilesystemPath(outputPath, cwd: cwd)
        )
        return .init(id: handle.id, operation: "create_voice_profile_from_description", profileName: profileName, events: handle.events)
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let resolvedReferenceAudioPath = resolvedAbsoluteFilesystemPath(referenceAudioPath, cwd: cwd) ?? referenceAudioPath
        let handle = await runtime.voices.create(
            clone: profileName,
            from: URL(fileURLWithPath: resolvedReferenceAudioPath),
            vibe: vibe,
            transcript: transcript
        )
        return .init(id: handle.id, operation: "create_voice_profile_from_audio", profileName: profileName, events: handle.events)
    }

    func listVoiceProfiles() async -> RuntimeRequestHandle {
        let handle = await runtime.voices.list()
        return .init(id: handle.id, operation: "list_voice_profiles", profileName: nil, events: handle.events)
    }

    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.delete(named: profileName)
        return .init(id: handle.id, operation: "delete_voice_profile", profileName: profileName, events: handle.events)
    }

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

    func generationQueue() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.jobs.generationQueue())
    }

    func playbackQueue() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.list())
    }

    func playbackState() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.state())
    }

    func pausePlayback() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.pause())
    }

    func resumePlayback() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.resume())
    }

    func clearQueue() async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.clearQueue())
    }

    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.player.cancelRequest(requestID))
    }

    func activeTextProfile() async -> TextForSpeech.Profile {
        await runtime.normalizer.activeProfile()
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        await runtime.normalizer.baseProfile()
    }

    func textProfile(id profileID: String) async -> TextForSpeech.Profile? {
        await runtime.normalizer.profile(id: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        await runtime.normalizer.profiles()
    }

    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile {
        await runtime.normalizer.effectiveProfile(id: profileID)
    }

    func loadTextProfiles() async throws {
        try await runtime.normalizer.loadProfiles()
    }

    func saveTextProfiles() async throws {
        try await runtime.normalizer.saveProfiles()
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement]
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.createProfile(id: id, named: name, replacements: replacements)
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws {
        try await runtime.normalizer.storeProfile(profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws {
        try await runtime.normalizer.useProfile(profile)
    }

    func removeTextProfile(id profileID: String) async throws {
        try await runtime.normalizer.removeProfile(id: profileID)
    }

    func resetTextProfile() async throws {
        try await runtime.normalizer.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.addReplacement(replacement, toStoredProfileID: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.replaceReplacement(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.replaceReplacement(replacement, inStoredProfileID: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileID profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.removeReplacement(id: replacementID, fromStoredProfileID: profileID)
    }

    private func resolvedAbsoluteFilesystemPath(
        _ path: String?,
        cwd: String?
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
