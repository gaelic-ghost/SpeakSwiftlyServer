import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import TextForSpeech

// MARK: - Mock Runtime

@available(macOS 14, *)
actor MockRuntime: ServerRuntimeProtocol {
    struct MockRequest {
        let id: String
        let operation: String
        let profileName: String?
        let requestedSpeechBackend: SpeakSwiftly.SpeechBackend?

        init(
            id: String,
            operation: String,
            profileName: String?,
            requestedSpeechBackend: SpeakSwiftly.SpeechBackend? = nil,
        ) {
            self.id = id
            self.operation = operation
            self.profileName = profileName
            self.requestedSpeechBackend = requestedSpeechBackend
        }
    }

    struct QueuedSpeechInvocation: Equatable {
        let text: String
        let profileName: String
        let textProfileID: String?
        let normalizationContext: SpeechNormalizationContext?
        let sourceFormat: TextForSpeech.SourceFormat?
        let requestContext: SpeakSwiftly.RequestContext?
    }

    struct CreateCloneInvocation: Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let referenceAudioPath: String
        let transcript: String?
        let cwd: String?
    }

    struct CreateProfileInvocation: Equatable {
        let profileName: String
        let vibe: SpeakSwiftly.Vibe
        let text: String
        let voiceDescription: String
        let outputPath: String?
        let cwd: String?
    }

    struct RenameProfileInvocation: Equatable {
        let profileName: String
        let newProfileName: String
    }

    struct RerollProfileInvocation: Equatable {
        let profileName: String
    }

    struct QueuedRequestState {
        let request: MockRequest
        let continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    }

    enum SpeakBehavior {
        case completeImmediately
        case holdOpen
    }

    enum MutationRefreshBehavior {
        case applyMutations
        case leaveProfilesUnchanged
    }

    enum StartBehavior {
        case immediate
        case waitForRelease
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
    var activeSpeechBackend: SpeakSwiftly.SpeechBackend = .qwen3
    var textRuntime: TextForSpeech.Runtime
    let textRuntimePersistenceURL: URL
    var loadTextProfilesCallCount = 0
    var saveTextProfilesCallCount = 0
    var textProfileTransportError: SpeakSwiftly.Error?
    var generatedFiles = [SpeakSwiftly.GeneratedFile]()
    var generatedBatches = [SpeakSwiftly.GeneratedBatch]()
    var generationJobs = [SpeakSwiftly.GenerationJob]()
    var listVoiceProfilesCallCount = 0
    var scriptedProfileRefreshSnapshots = [[SpeakSwiftly.ProfileSummary]]()
    var generationQueueRequestCount = 0
    var playbackQueueRequestCount = 0
    var playbackStateRequestCount = 0
    var startCallCount = 0
    var shutdownCallCount = 0
    var startBehavior: StartBehavior
    var startReleaseContinuation: CheckedContinuation<Void, Never>?
    var startHasReachedBarrier = false
    var startBarrierWaiters = [CheckedContinuation<Void, Never>]()

    init(
        profiles: [SpeakSwiftly.ProfileSummary] = [sampleProfile()],
        speakBehavior: SpeakBehavior = .completeImmediately,
        mutationRefreshBehavior: MutationRefreshBehavior = .applyMutations,
        textProfileTransportError: SpeakSwiftly.Error? = nil,
        startBehavior: StartBehavior = .immediate,
        scriptedProfileRefreshSnapshots: [[SpeakSwiftly.ProfileSummary]] = [],
    ) {
        self.profiles = profiles
        self.speakBehavior = speakBehavior
        self.mutationRefreshBehavior = mutationRefreshBehavior
        self.textProfileTransportError = textProfileTransportError
        self.startBehavior = startBehavior
        self.scriptedProfileRefreshSnapshots = scriptedProfileRefreshSnapshots
        let persistenceURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("ServerTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        textRuntimePersistenceURL = persistenceURL
        textRuntime = requireFixture("MockRuntime text runtime bootstrap") {
            try TextForSpeech.Runtime(persistence: .file(persistenceURL))
        }
    }

    func start() async {
        startCallCount += 1
        guard startBehavior == .waitForRelease else {
            return
        }

        startHasReachedBarrier = true
        let barrierWaiters = startBarrierWaiters
        startBarrierWaiters.removeAll()
        for waiter in barrierWaiters {
            waiter.resume()
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                startReleaseContinuation = continuation
            }
        } onCancel: {
            Task {
                await self.cancelStartWait()
            }
        }
    }

    func shutdown() async {
        shutdownCallCount += 1
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

    func lifecycleCounts() -> (start: Int, shutdown: Int) {
        (startCallCount, shutdownCallCount)
    }

    func setScriptedProfileRefreshSnapshots(_ snapshots: [[SpeakSwiftly.ProfileSummary]]) {
        scriptedProfileRefreshSnapshots = snapshots
    }

    func waitUntilStartReachesBarrier() async {
        guard startBehavior == .waitForRelease else { return }
        guard !startHasReachedBarrier else { return }

        await withCheckedContinuation { continuation in
            if startHasReachedBarrier {
                continuation.resume()
            } else {
                startBarrierWaiters.append(continuation)
            }
        }
    }

    func allowStartToFinish() {
        startReleaseContinuation?.resume()
        startReleaseContinuation = nil
        startBehavior = .immediate
    }

    func cancelStartWait() {
        startReleaseContinuation?.resume()
        startReleaseContinuation = nil
    }
}
