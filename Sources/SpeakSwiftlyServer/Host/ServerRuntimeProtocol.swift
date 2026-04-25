import Foundation
import SpeakSwiftly
import TextForSpeech

public typealias SpeechNormalizationContext = TextForSpeech.Context

func makeInputTextContext(
    normalizationContext: SpeechNormalizationContext?,
    sourceFormat: TextForSpeech.SourceFormat?,
) -> SpeakSwiftly.InputTextContext? {
    guard normalizationContext != nil || sourceFormat != nil else {
        return nil
    }

    return SpeakSwiftly.InputTextContext(
        context: normalizationContext,
        sourceFormat: sourceFormat,
    )
}

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
        operation = canonicalOperationName(handle.operation)
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
        case "get_runtime_configuration":
            "get_staged_runtime_config"
        case "set_runtime_configuration":
            "set_staged_config"
        case "get_text_profiles_state":
            "get_text_normalizer_snapshot"
        case "list_requests":
            "list_active_requests"
        default:
            operation
    }
}

protocol ServerRuntimeProtocol: Actor {
    func start() async
    func shutdown() async
    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent>
    func queueSpeechLive(
        text: String,
        with profileName: String,
        textProfileID: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
    ) async -> RuntimeRequestHandle
    func queueSpeechFile(
        text: String,
        with profileName: String,
        textProfileID: String?,
        normalizationContext: SpeechNormalizationContext?,
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
    func generatedFile(id artifactID: String) async -> RuntimeRequestHandle
    func listGeneratedFiles() async -> RuntimeRequestHandle
    func generatedBatch(id batchID: String) async -> RuntimeRequestHandle
    func listGeneratedBatches() async -> RuntimeRequestHandle
    func runtimeStatus() async -> RuntimeRequestHandle
    func switchSpeechBackend(to speechBackend: SpeakSwiftly.SpeechBackend) async -> RuntimeRequestHandle
    func reloadModels() async -> RuntimeRequestHandle
    func unloadModels() async -> RuntimeRequestHandle
    func runtimeOverview() async -> RuntimeRequestHandle
    func playbackState() async -> RuntimeRequestHandle
    func pausePlayback() async -> RuntimeRequestHandle
    func resumePlayback() async -> RuntimeRequestHandle
    func clearQueue() async -> RuntimeRequestHandle
    func cancelRequest(_ requestID: String) async -> RuntimeRequestHandle
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
