import Foundation
import SpeakSwiftlyCore
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - Mock Runtime

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct MockRequest: Sendable {
        let id: String
        let operation: String
        let profileName: String?
    }

    struct QueuedSpeechInvocation: Sendable, Equatable {
        let text: String
        let profileName: String
        let textProfileName: String?
        let normalizationContext: SpeechNormalizationContext?
        let sourceFormat: TextForSpeech.SourceFormat?
    }

    struct CreateCloneInvocation: Sendable, Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let referenceAudioPath: String
        let transcript: String?
        let cwd: String?
    }

    struct CreateProfileInvocation: Sendable, Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let text: String
        let voiceDescription: String
        let outputPath: String?
        let cwd: String?
    }

    struct RenameProfileInvocation: Sendable, Equatable {
        let profileName: String
        let newProfileName: String
    }

    struct RerollProfileInvocation: Sendable, Equatable {
        let profileName: String
    }

    struct QueuedRequestState: Sendable {
        let request: MockRequest
        let continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    }

    enum SpeakBehavior: Sendable {
        case completeImmediately
        case holdOpen
    }

    enum MutationRefreshBehavior: Sendable {
        case applyMutations
        case leaveProfilesUnchanged
    }

    var profiles: [SpeakSwiftly.ProfileSummary]
    var speakBehavior: SpeakBehavior
    var mutationRefreshBehavior: MutationRefreshBehavior
    var statusContinuation: AsyncStream<SpeakSwiftly.StatusEvent>.Continuation?
    var activeRequest: MockRequest?
    var activeContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
    var queuedRequests = [QueuedRequestState]()
    var queuedSpeechInvocations = [QueuedSpeechInvocation]()
    var createCloneInvocations = [CreateCloneInvocation]()
    var createProfileInvocations = [CreateProfileInvocation]()
    var renameProfileInvocations = [RenameProfileInvocation]()
    var rerollProfileInvocations = [RerollProfileInvocation]()
    var playbackState: SpeakSwiftly.PlaybackState = .idle
    var textRuntime: TextForSpeech.Runtime
    let textRuntimePersistenceURL: URL
    var loadTextProfilesCallCount = 0
    var saveTextProfilesCallCount = 0
    var generatedFiles = [SpeakSwiftly.GeneratedFile]()
    var generatedBatches = [SpeakSwiftly.GeneratedBatch]()
    var generationJobs = [SpeakSwiftly.GenerationJob]()
    var generationQueueRequestCount = 0
    var playbackQueueRequestCount = 0
    var playbackStateRequestCount = 0

    // MARK: - Lifecycle

    init(
        profiles: [SpeakSwiftly.ProfileSummary] = [sampleProfile()],
        speakBehavior: SpeakBehavior = .completeImmediately,
        mutationRefreshBehavior: MutationRefreshBehavior = .applyMutations
    ) {
        self.profiles = profiles
        self.speakBehavior = speakBehavior
        self.mutationRefreshBehavior = mutationRefreshBehavior
        self.textRuntimePersistenceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeakSwiftlyServerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        self.textRuntime = try! TextForSpeech.Runtime(persistence: .file(textRuntimePersistenceURL))
    }

    func start() {}

    func shutdown() async {
        statusContinuation?.finish()
        activeContinuation?.finish()
        activeContinuation = nil
        activeRequest = nil
        playbackState = .idle
        for queued in queuedRequests {
            queued.continuation.finish()
        }
        queuedRequests.removeAll()
    }

    func statusEvents() async -> AsyncStream<SpeakSwiftly.StatusEvent> {
        AsyncStream { continuation in
            self.statusContinuation = continuation
        }
    }

}
