import Foundation
import SpeakSwiftly
import SpeakSwiftlyServer
import SSSCore
import SSSHTTP
import SSSMCP

// MARK: - Mock Runtime

@available(macOS 14, *)
package actor MockRuntime: SpeakSwiftlyRuntimeServing {
    package struct MockRequest {
        package let id: String
        package let operation: String
        package let profileName: String?
        package let requestedSpeechBackend: SpeakSwiftly.SpeechBackend?

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

    package struct QueuedSpeechInvocation: Equatable {
        package let text: String
        package let profileName: String
        package let textProfileID: String?
        package let requestContext: SpeakSwiftly.RequestContext?
        package let qwenPreModelTextChunking: Bool
    }

    package struct AudioStreamInvocation: Equatable {
        package let text: String
        package let profileName: String
        package let textProfileID: String?
        package let requestContext: SpeakSwiftly.RequestContext?
        package let qwenPreModelTextChunking: Bool
    }

    package struct CreateCloneInvocation: Equatable {
        package let profileName: String
        package let vibe: SpeakSwiftly.Vibe
        package let referenceAudioPath: String
        package let transcript: String?
        package let cwd: String?
    }

    package struct CreateProfileInvocation: Equatable {
        package let profileName: String
        package let vibe: SpeakSwiftly.Vibe
        package let text: String
        package let voiceDescription: String
        package let author: SpeakSwiftly.ProfileAuthor
        package let seedID: String?
        package let seedVersion: String?
        package let outputPath: String?
        package let cwd: String?
    }

    package struct RenameProfileInvocation: Equatable {
        package let profileName: String
        package let newProfileName: String
    }

    package struct RerollProfileInvocation: Equatable {
        package let profileName: String
    }

    package struct QueuedRequestState {
        package let request: MockRequest
        package let continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    }

    package enum SpeakBehavior {
        case completeImmediately
        case holdOpen
    }

    package enum MutationRefreshBehavior {
        case applyMutations
        case leaveProfilesUnchanged
    }

    package enum StartBehavior {
        case immediate
        case waitForRelease
    }

    package var profiles: [SpeakSwiftly.ProfileSummary]
    package var speakBehavior: SpeakBehavior
    package var mutationRefreshBehavior: MutationRefreshBehavior
    package var runtimeUpdateContinuation: AsyncStream<SpeakSwiftly.RuntimeUpdate>.Continuation?
    package var playbackUpdateContinuation: AsyncStream<SpeakSwiftly.PlaybackUpdate>.Continuation?
    package var activeRequest: MockRequest?
    package var activeContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
    package var queuedRequests = [QueuedRequestState]()
    package var recentGeneratedAudioSnapshot = SpeakSwiftly.RecentGeneratedAudioSnapshot(
        items: [],
        limit: 5,
        memorySecondsPerItem: 30,
    )
    package var recentGeneratedAudioChunks = [String: [SpeakSwiftly.GeneratedAudioChunk]]()
    package var replayRecentAudioInvocations = [(id: String, mode: SpeakSwiftly.RecentGeneratedAudioReplayMode, requestContext: SpeakSwiftly.RequestContext?)]()
    package var replayRecentAudioAllInvocations = [(mode: SpeakSwiftly.RecentGeneratedAudioReplayMode, requestContext: SpeakSwiftly.RequestContext?)]()
    package var clearRecentGeneratedAudioCallCount = 0
    package var queuedSpeechInvocations = [QueuedSpeechInvocation]()
    package var audioStreamInvocations = [AudioStreamInvocation]()
    package var scriptedAudioStreamChunks = [SpeakSwiftly.GeneratedAudioChunk]()
    package var createCloneInvocations = [CreateCloneInvocation]()
    package var createProfileInvocations = [CreateProfileInvocation]()
    package var renameProfileInvocations = [RenameProfileInvocation]()
    package var rerollProfileInvocations = [RerollProfileInvocation]()
    package var playbackState: SpeakSwiftly.PlaybackState = .idle
    package var runtimeState: SpeakSwiftly.RuntimeState = .residentModelReady
    package var activeSpeechBackend: SpeakSwiftly.SpeechBackend = .qwen3_smol
    package var textRuntime: SpeakSwiftly.Normalizer
    package let textRuntimePersistenceURL: URL
    package var loadTextProfilesCallCount = 0
    package var saveTextProfilesCallCount = 0
    package var textProfileTransportError: SpeakSwiftly.Error?
    package var generationArtifacts = [SpeakSwiftly.GenerationArtifact]()
    package var generationJobs = [SpeakSwiftly.GenerationJob]()
    package var listVoiceProfilesCallCount = 0
    package var holdNextListVoiceProfiles = false
    package var listVoiceProfilesHoldContinuation: CheckedContinuation<Void, Never>?
    package var listVoiceProfilesHasReachedHold = false
    package var listVoiceProfilesHoldWaiters = [CheckedContinuation<Void, Never>]()
    package var listVoiceProfilesFailureMessages = [String]()
    package var scriptedProfileRefreshSnapshots = [[SpeakSwiftly.ProfileSummary]]()
    package var generationQueueRequestCount = 0
    package var playbackQueueRequestCount = 0
    package var playbackStateRequestCount = 0
    package var startCallCount = 0
    package var shutdownCallCount = 0
    package var startBehavior: StartBehavior
    package var startReleaseContinuation: CheckedContinuation<Void, Never>?
    package var startHasReachedBarrier = false
    package var startBarrierWaiters = [CheckedContinuation<Void, Never>]()

    package init(
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
        textRuntime = requireFixture("MockRuntime text normalizer bootstrap") {
            try SpeakSwiftly.Normalizer(persistenceURL: persistenceURL)
        }
    }

    package func start() async {
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

    package func shutdown() async {
        shutdownCallCount += 1
        runtimeUpdateContinuation?.finish()
        playbackUpdateContinuation?.finish()
        activeContinuation?.finish()
        activeContinuation = nil
        activeRequest = nil
        playbackState = .idle
        for queued in queuedRequests {
            queued.continuation.finish()
        }
        queuedRequests.removeAll()
    }

    package func runtimeUpdates() async -> AsyncStream<SpeakSwiftly.RuntimeUpdate> {
        AsyncStream { continuation in
            self.runtimeUpdateContinuation = continuation
        }
    }

    package func runtimeSnapshot() async -> SpeakSwiftly.RuntimeSnapshot {
        runtimeSnapshotSummary()
    }

    package func generationSnapshot() async -> SpeakSwiftly.GenerateSnapshot {
        generationQueueRequestCount += 1
        return generationSnapshotSummary()
    }

    package func playbackUpdates() async -> AsyncStream<SpeakSwiftly.PlaybackUpdate> {
        AsyncStream { continuation in
            self.playbackUpdateContinuation = continuation
        }
    }

    package func playbackSnapshot() async -> SpeakSwiftly.PlaybackSnapshot {
        playbackQueueRequestCount += 1
        playbackStateRequestCount += 1
        return playbackSnapshotSummary()
    }

    package func lifecycleCounts() -> (start: Int, shutdown: Int) {
        (startCallCount, shutdownCallCount)
    }

    package func holdNextVoiceProfileRefresh() {
        holdNextListVoiceProfiles = true
        listVoiceProfilesHasReachedHold = false
    }

    package func waitUntilVoiceProfileRefreshIsHeld() async {
        guard !listVoiceProfilesHasReachedHold else { return }

        await withCheckedContinuation { continuation in
            if listVoiceProfilesHasReachedHold {
                continuation.resume()
            } else {
                listVoiceProfilesHoldWaiters.append(continuation)
            }
        }
    }

    package func releaseHeldVoiceProfileRefresh() {
        listVoiceProfilesHoldContinuation?.resume()
        listVoiceProfilesHoldContinuation = nil
    }

    package func failNextVoiceProfileRefresh(message: String) {
        listVoiceProfilesFailureMessages.append(message)
    }

    package func setScriptedProfileRefreshSnapshots(_ snapshots: [[SpeakSwiftly.ProfileSummary]]) {
        scriptedProfileRefreshSnapshots = snapshots
    }

    package func waitUntilStartReachesBarrier() async {
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

    package func allowStartToFinish() {
        startReleaseContinuation?.resume()
        startReleaseContinuation = nil
        startBehavior = .immediate
    }

    package func cancelStartWait() {
        startReleaseContinuation?.resume()
        startReleaseContinuation = nil
    }
}
