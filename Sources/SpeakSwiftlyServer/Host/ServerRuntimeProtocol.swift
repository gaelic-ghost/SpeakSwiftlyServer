import Foundation
import SpeakSwiftly
import TextForSpeech

struct RuntimeRequestHandle {
    let id: String
    let operation: String
    let profileName: String?
    let events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>

    // MARK: - Initialization

    init(
        id: String,
        operation: String,
        profileName: String?,
        events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>,
    ) {
        self.id = id
        self.operation = operation
        self.profileName = profileName
        self.events = events
    }

    init(_ handle: SpeakSwiftly.RequestHandle) {
        id = handle.id
        operation = canonicalOperationName(handle.kind.rawValue)
        profileName = handle.voiceProfile
        events = handle.events
    }
}

func canonicalOperationName(_ operation: String) -> String {
    switch operation {
        case "queue_speech_live":
            "generate_speech"
        case "queue_speech_file":
            "generate_audio_file"
        case "queue_speech_batch":
            "generate_batch"
        case "get_text_profiles_state":
            "text_profiles_snapshot"
        case "list_requests":
            "requests_snapshot"
        default:
            operation
    }
}

protocol ServerRuntimeProtocol: Actor {
    func start() async
    func shutdown() async
    func runtimeUpdates() async -> AsyncStream<SpeakSwiftly.RuntimeUpdate>
    func runtimeSnapshot() async -> SpeakSwiftly.RuntimeSnapshot
    func generationSnapshot() async -> SpeakSwiftly.GenerateSnapshot
    func playbackSnapshot() async -> SpeakSwiftly.PlaybackSnapshot
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileID: String?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    ) async -> RuntimeRequestHandle
    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileID: String?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
    ) async -> RuntimeRequestHandle
    func queueSpeechBatch(
        _ items: [SpeakSwiftly.BatchItem],
        with profileName: String,
    ) async -> RuntimeRequestHandle
    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle
    func createSystemVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from text: String,
        voice voiceDescription: String,
        seed: SpeakSwiftly.ProfileSeed,
        outputPath: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle
    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
    ) async -> RuntimeRequestHandle
    func listVoiceProfiles() async -> RuntimeRequestHandle
    func renameVoiceProfile(profileName: String, to newProfileName: String) async -> RuntimeRequestHandle
    func rerollVoiceProfile(profileName: String) async -> RuntimeRequestHandle
    func deleteVoiceProfile(profileName: String) async -> RuntimeRequestHandle
    func generationJob(id jobID: String) async -> RuntimeRequestHandle
    func listGenerationJobs() async -> RuntimeRequestHandle
    func expireGenerationJob(id jobID: String) async -> RuntimeRequestHandle
    func generationArtifact(id artifactID: String) async -> RuntimeRequestHandle
    func listGenerationArtifacts() async -> RuntimeRequestHandle
    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle
    func reloadModels() async -> RuntimeRequestHandle
    func unloadModels() async -> RuntimeRequestHandle
    func pausePlayback() async -> RuntimeRequestHandle
    func resumePlayback() async -> RuntimeRequestHandle
    func clearQueue() async -> RuntimeRequestHandle
    func clearQueue(_ queueType: SpeakSwiftly.QueueType) async -> RuntimeRequestHandle
    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle
    func cancel(_ queueType: SpeakSwiftly.QueueType, requestID: String) async -> RuntimeRequestHandle
    func builtInTextProfileStyle() async -> TextForSpeech.BuiltInProfileStyle
    func setBuiltInTextProfileStyle(_ style: TextForSpeech.BuiltInProfileStyle) async throws -> TextForSpeech.BuiltInProfileStyle
    func activeTextProfile() async throws -> SpeakSwiftly.TextProfileDetails
    func baseTextProfile() async -> TextForSpeech.Profile
    func textProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails?
    func textProfiles() async throws -> [SpeakSwiftly.TextProfileSummary]
    func effectiveTextProfile(id profileID: String?) async throws -> SpeakSwiftly.TextProfileDetails
    func loadTextProfiles() async throws
    func saveTextProfiles() async throws
    func createTextProfile(named name: String) async throws -> SpeakSwiftly.TextProfileDetails
    func renameTextProfile(id profileID: String, to name: String) async throws -> SpeakSwiftly.TextProfileDetails
    func setActiveTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails
    func removeTextProfile(id profileID: String) async throws
    func factoryResetTextProfiles() async throws
    func resetTextProfile(id profileID: String) async throws -> SpeakSwiftly.TextProfileDetails
    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails
    func addTextReplacement(_ replacement: TextForSpeech.Replacement, toStoredTextProfileID profileID: String) async throws -> SpeakSwiftly.TextProfileDetails
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> SpeakSwiftly.TextProfileDetails
    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement, inStoredTextProfileID profileID: String) async throws -> SpeakSwiftly.TextProfileDetails
    func removeTextReplacement(id replacementID: String) async throws -> SpeakSwiftly.TextProfileDetails
    func removeTextReplacement(id replacementID: String, fromStoredTextProfileID profileID: String) async throws -> SpeakSwiftly.TextProfileDetails
}
