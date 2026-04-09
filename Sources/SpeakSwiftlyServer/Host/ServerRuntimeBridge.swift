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

enum RuntimeQueueType: Sendable {
    case generation
    case playback
}

enum RuntimePlaybackAction: Sendable {
    case pause
    case resume
    case state
}

// MARK: - Runtime Protocol

protocol ServerRuntimeProtocol: Actor {
    func start()
    func shutdown() async
    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent>
    func generateSpeechLive(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle
    func generateAudioFile(
        text: String,
        with profileName: String,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?
    ) async -> RuntimeRequestHandle
    func generateAudioBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String
    ) async -> RuntimeRequestHandle
    func createVoiceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle
    func cloneVoiceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle
    func voiceProfiles() async -> RuntimeRequestHandle
    func deleteVoiceProfile(named profileName: String) async -> RuntimeRequestHandle
    func generationJob(id jobID: String) async -> RuntimeRequestHandle
    func generationJobs() async -> RuntimeRequestHandle
    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle
    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle
    func generatedFiles() async -> RuntimeRequestHandle
    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle
    func generatedBatches() async -> RuntimeRequestHandle
    func runtimeStatus() async -> RuntimeRequestHandle
    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle
    func reloadModels() async -> RuntimeRequestHandle
    func unloadModels() async -> RuntimeRequestHandle
    func queue(_ queueType: RuntimeQueueType) async -> RuntimeRequestHandle
    func playback(_ action: RuntimePlaybackAction) async -> RuntimeRequestHandle
    func clearQueue() async -> RuntimeRequestHandle
    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle
    func activeTextProfile() async -> TextForSpeech.Profile
    func baseTextProfile() async -> TextForSpeech.Profile
    func textProfile(id profileID: String) async -> TextForSpeech.Profile?
    func textProfiles() async -> [TextForSpeech.Profile]
    func effectiveTextProfile(id profileID: String?) async -> TextForSpeech.Profile
    func textProfilePersistenceURL() async -> URL?
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

    func generateSpeechLive(
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
        return .init(id: handle.id, operation: "generate_speech_live", profileName: profileName, events: handle.events)
    }

    func generateAudioFile(
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
        return .init(id: handle.id, operation: "generate_audio_file", profileName: profileName, events: handle.events)
    }

    func generateAudioBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String
    ) async -> RuntimeRequestHandle {
        let handle = await runtime.generate.batch(items, with: profileName)
        return .init(id: handle.id, operation: "generate_audio_batch", profileName: profileName, events: handle.events)
    }

    func createVoiceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let currentDirectoryPath = FileManager.default.currentDirectoryPath
        let previousDirectoryPath = currentDirectoryPath
        if let cwd, !cwd.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(cwd)
        }
        defer {
            FileManager.default.changeCurrentDirectoryPath(previousDirectoryPath)
        }
        let handle = await runtime.voices.create(
            design: profileName,
            from: text,
            vibe: vibe,
            voice: voiceDescription,
            outputPath: outputPath
        )
        return .init(id: handle.id, operation: "create_voice_profile", profileName: profileName, events: handle.events)
    }

    func cloneVoiceProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async -> RuntimeRequestHandle {
        let currentDirectoryPath = FileManager.default.currentDirectoryPath
        let previousDirectoryPath = currentDirectoryPath
        if let cwd, !cwd.isEmpty {
            FileManager.default.changeCurrentDirectoryPath(cwd)
        }
        defer {
            FileManager.default.changeCurrentDirectoryPath(previousDirectoryPath)
        }
        let handle = await runtime.voices.create(
            clone: profileName,
            from: URL(fileURLWithPath: referenceAudioPath),
            vibe: vibe,
            transcript: transcript
        )
        return .init(id: handle.id, operation: "clone_voice_profile", profileName: profileName, events: handle.events)
    }

    func voiceProfiles() async -> RuntimeRequestHandle {
        let handle = await runtime.voices.list()
        return .init(id: handle.id, operation: "list_voice_profiles", profileName: nil, events: handle.events)
    }

    func deleteVoiceProfile(named profileName: String) async -> RuntimeRequestHandle {
        let handle = await runtime.voices.delete(named: profileName)
        return .init(id: handle.id, operation: "delete_voice_profile", profileName: profileName, events: handle.events)
    }

    func generationJob(id jobID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.jobs.job(id: jobID)
        return .init(id: handle.id, operation: "get_generation_job", profileName: nil, events: handle.events)
    }

    func generationJobs() async -> RuntimeRequestHandle {
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

    func generatedFiles() async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.files()
        return .init(id: handle.id, operation: "list_generated_files", profileName: nil, events: handle.events)
    }

    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle {
        let handle = await runtime.artifacts.batch(id: batchID)
        return .init(id: handle.id, operation: "get_generated_batch", profileName: nil, events: handle.events)
    }

    func generatedBatches() async -> RuntimeRequestHandle {
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

    func queue(_ queueType: RuntimeQueueType) async -> RuntimeRequestHandle {
        switch queueType {
        case .generation:
            RuntimeRequestHandle(await runtime.jobs.generationQueue())
        case .playback:
            RuntimeRequestHandle(await runtime.player.list())
        }
    }

    func playback(_ action: RuntimePlaybackAction) async -> RuntimeRequestHandle {
        switch action {
        case .pause:
            RuntimeRequestHandle(await runtime.player.pause())
        case .resume:
            RuntimeRequestHandle(await runtime.player.resume())
        case .state:
            RuntimeRequestHandle(await runtime.player.state())
        }
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

    func textProfilePersistenceURL() async -> URL? {
        nil
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
}
