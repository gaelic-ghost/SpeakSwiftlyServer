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
    func speak(
        text: String,
        with profileName: String,
        as jobType: SpeakSwiftly.Job,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
        id: String
    ) async -> RuntimeRequestHandle
    func createProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?,
        id: String
    ) async -> RuntimeRequestHandle
    func createClone(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
        id: String
    ) async -> RuntimeRequestHandle
    func profiles(id: String) async -> RuntimeRequestHandle
    func removeProfile(named profileName: String, id: String) async -> RuntimeRequestHandle
    func queue(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle
    func playback(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle
    func clearQueue(id requestID: String) async -> RuntimeRequestHandle
    func cancelRequest(_ id: String, requestID: String) async -> RuntimeRequestHandle
    func activeTextProfile() async -> TextForSpeech.Profile
    func baseTextProfile() async -> TextForSpeech.Profile
    func textProfile(named profileID: String) async -> TextForSpeech.Profile?
    func textProfiles() async -> [TextForSpeech.Profile]
    func effectiveTextProfile(named profileID: String?) async -> TextForSpeech.Profile
    func textProfilePersistenceURL() async -> URL?
    func loadTextProfiles() async throws
    func saveTextProfiles() async throws
    func createTextProfile(id: String, named name: String, replacements: [TextForSpeech.Replacement]) async throws -> TextForSpeech.Profile
    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws
    func useTextProfile(_ profile: TextForSpeech.Profile) async throws
    func removeTextProfile(named profileID: String) async throws
    func resetTextProfile() async throws
    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile
    func addTextReplacement(_ replacement: TextForSpeech.Replacement, toStoredTextProfileNamed profileID: String) async throws -> TextForSpeech.Profile
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement, inStoredTextProfileNamed profileID: String) async throws -> TextForSpeech.Profile
    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile
    func removeTextReplacement(id replacementID: String, fromStoredTextProfileNamed profileID: String) async throws -> TextForSpeech.Profile
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

    func speak(
        text: String,
        with profileName: String,
        as jobType: SpeakSwiftly.Job,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
        id: String
    ) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(
            await runtime.speak(
                text: text,
                with: profileName,
                as: jobType,
                textProfileName: textProfileName,
                textContext: normalizationContext,
                sourceFormat: sourceFormat,
                id: id
            )
        )
    }

    func createProfile(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(
            await runtime.createProfile(
                named: profileName,
                from: text,
                vibe: vibe,
                voice: voiceDescription,
                outputPath: outputPath,
                cwd: cwd,
                id: id
            )
        )
    }

    func createClone(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(
            await runtime.createClone(
                named: profileName,
                from: referenceAudioPath,
                vibe: vibe,
                transcript: transcript,
                cwd: cwd,
                id: id
            )
        )
    }

    func profiles(id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.profiles(id: id))
    }

    func removeProfile(named profileName: String, id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.removeProfile(named: profileName, id: id))
    }

    func queue(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.queue(queueType, id: requestID))
    }

    func playback(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.playback(action, id: requestID))
    }

    func clearQueue(id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.clearQueue(id: requestID))
    }

    func cancelRequest(_ id: String, requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await runtime.cancelRequest(id, requestID: requestID))
    }

    func activeTextProfile() async -> TextForSpeech.Profile {
        await runtime.normalizer.activeProfile()
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        await runtime.normalizer.baseProfile()
    }

    func textProfile(named profileID: String) async -> TextForSpeech.Profile? {
        await runtime.normalizer.profile(named: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        await runtime.normalizer.profiles()
    }

    func effectiveTextProfile(named profileID: String?) async -> TextForSpeech.Profile {
        await runtime.normalizer.effectiveProfile(named: profileID)
    }

    func textProfilePersistenceURL() async -> URL? {
        await runtime.normalizer.persistenceURL()
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

    func removeTextProfile(named profileID: String) async throws {
        try await runtime.normalizer.removeProfile(named: profileID)
    }

    func resetTextProfile() async throws {
        try await runtime.normalizer.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.addReplacement(replacement, toStoredProfileNamed: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.replaceReplacement(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.replaceReplacement(replacement, inStoredProfileNamed: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try await runtime.normalizer.removeReplacement(id: replacementID, fromStoredProfileNamed: profileID)
    }
}
