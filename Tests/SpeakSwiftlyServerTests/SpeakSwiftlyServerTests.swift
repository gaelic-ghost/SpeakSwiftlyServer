import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftlyCore
import Testing
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
    private var statusContinuation: AsyncStream<SpeakSwiftly.StatusEvent>.Continuation?
    private var activeRequest: MockRequest?
    private var activeContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
    private var queuedRequests = [QueuedRequestState]()
    private var queuedSpeechInvocations = [QueuedSpeechInvocation]()
    private var createCloneInvocations = [CreateCloneInvocation]()
    private var createProfileInvocations = [CreateProfileInvocation]()
    private var playbackState: SpeakSwiftly.PlaybackState = .idle
    private var textRuntime = TextForSpeechRuntime()
    private var loadTextProfilesCallCount = 0
    private var saveTextProfilesCallCount = 0

    // MARK: - Lifecycle

    init(
        profiles: [SpeakSwiftly.ProfileSummary] = [sampleProfile()],
        speakBehavior: SpeakBehavior = .completeImmediately,
        mutationRefreshBehavior: MutationRefreshBehavior = .applyMutations
    ) {
        self.profiles = profiles
        self.speakBehavior = speakBehavior
        self.mutationRefreshBehavior = mutationRefreshBehavior
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

    // MARK: - Runtime Protocol

    func speak(
        text: String,
        with profileName: String,
        as jobType: SpeakSwiftly.Job,
        textProfileName: String?,
        normalizationContext: SpeechNormalizationContext?,
        sourceFormat: TextForSpeech.SourceFormat?,
        id: String
    ) async -> RuntimeRequestHandle {
        let request = MockRequest(id: id, operation: speechOperationName(for: jobType), profileName: profileName)
        queuedSpeechInvocations.append(
            .init(
                text: text,
                profileName: profileName,
                textProfileName: textProfileName,
                normalizationContext: normalizationContext,
                sourceFormat: sourceFormat
            )
        )
        var requestContinuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation?
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            requestContinuation = continuation
        }
        guard let continuation = requestContinuation else {
            fatalError("The mock runtime could not create a speech request continuation for request '\(id)'.")
        }

        continuation.yield(.acknowledged(.init(id: id)))

        if self.activeRequest == nil {
            self.startActiveRequest(request, continuation: continuation)
        } else {
            self.queuedRequests.append(.init(request: request, continuation: continuation))
            continuation.yield(
                .queued(
                    .init(
                        id: id,
                        reason: .waitingForActiveRequest,
                        queuePosition: self.queuedRequests.count
                    )
                )
            )
        }

        return RuntimeRequestHandle(id: id, operation: request.operation, profileName: profileName, events: events)
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
        createProfileInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                cwd: cwd
            )
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: voiceDescription,
                    sourceText: text
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operation: "create_profile", profileName: profileName, events: events)
    }

    func createClone(
        named profileName: String,
        vibe: SpeakSwiftly.Vibe,
        from referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        createCloneInvocations.append(
            .init(
                profileName: profileName,
                vibe: vibe,
                referenceAudioPath: referenceAudioPath,
                transcript: transcript,
                cwd: cwd
            )
        )
        if mutationRefreshBehavior == .applyMutations {
            profiles.append(
                SpeakSwiftly.ProfileSummary(
                    profileName: profileName,
                    vibe: vibe,
                    createdAt: Date(),
                    voiceDescription: "Imported reference audio clone.",
                    sourceText: transcript ?? "Imported clone transcript."
                )
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operation: "create_clone", profileName: profileName, events: events)
    }

    func profiles(id: String) async -> RuntimeRequestHandle {
        let profiles = self.profiles
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profiles: profiles)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operation: "list_profiles", profileName: nil, events: events)
    }

    func removeProfile(named profileName: String, id: String) async -> RuntimeRequestHandle {
        if mutationRefreshBehavior == .applyMutations {
            profiles.removeAll { $0.profileName == profileName }
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: id, profileName: profileName)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: id, operation: "remove_profile", profileName: profileName, events: events)
    }

    func queue(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle {
        let activeRequest: SpeakSwiftly.ActiveRequest? =
            switch queueType {
            case .generation:
                self.activeRequest.map(self.activeSummary(for:))
            case .playback:
                playbackState == .idle ? nil : self.activeRequest.map(self.activeSummary(for:))
            }
        let queue: [SpeakSwiftly.QueuedRequest] =
            switch queueType {
            case .generation:
                self.queuedSummaries()
            case .playback:
                []
            }
        let operationName = queueType == .generation ? "list_queue_generation" : "list_queue_playback"
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        activeRequest: activeRequest,
                        queue: queue
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: operationName, profileName: nil, events: events)
    }

    func playback(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
        switch action {
        case .pause:
            if activeRequest != nil {
                playbackState = .paused
            }
        case .resume:
            if activeRequest != nil {
                playbackState = .playing
            }
        case .state:
            break
        }
        let playbackState = self.playbackStateSummary()
        let operationName = playbackOperationName(for: action)
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    SpeakSwiftly.Success(
                        id: requestID,
                        playbackState: playbackState
                    )
                )
            )
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: operationName, profileName: nil, events: events)
    }

    func clearQueue(id requestID: String) async -> RuntimeRequestHandle {
        let clearedRequestIDs = queuedRequests.map(\.request.id)
        let clearedCount = clearedRequestIDs.count
        for queuedRequestID in clearedRequestIDs {
            cancelQueuedRequest(
                queuedRequestID,
                reason: "The request was cancelled because queued work was cleared from the mock SpeakSwiftly runtime."
            )
        }
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            continuation.yield(.completed(SpeakSwiftly.Success(id: requestID, clearedCount: clearedCount)))
            continuation.finish()
        }
        return RuntimeRequestHandle(id: requestID, operation: "clear_queue", profileName: nil, events: events)
    }

    func cancelRequest(_ id: String, requestID: String) async -> RuntimeRequestHandle {
        do {
            let cancelledRequestID = try cancelRequestNow(id)
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.yield(
                    .completed(
                        SpeakSwiftly.Success(
                            id: requestID,
                            cancelledRequestID: cancelledRequestID
                        )
                    )
                )
                continuation.finish()
            }
            return RuntimeRequestHandle(id: requestID, operation: "cancel_request", profileName: nil, events: events)
        } catch {
            let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
                continuation.finish(throwing: error)
            }
            return RuntimeRequestHandle(id: requestID, operation: "cancel_request", profileName: nil, events: events)
        }
    }

    func activeTextProfile() async -> TextForSpeech.Profile {
        textRuntime.customProfile
    }

    func baseTextProfile() async -> TextForSpeech.Profile {
        textRuntime.baseProfile
    }

    func textProfile(named profileID: String) async -> TextForSpeech.Profile? {
        textRuntime.profile(named: profileID)
    }

    func textProfiles() async -> [TextForSpeech.Profile] {
        textRuntime.storedProfiles()
    }

    func effectiveTextProfile(named profileID: String?) async -> TextForSpeech.Profile {
        textRuntime.effectiveProfile(named: profileID)
    }

    func textProfilePersistenceURL() async -> URL? {
        URL(fileURLWithPath: "/tmp/mock-text-profiles.json")
    }

    func loadTextProfiles() async throws {
        loadTextProfilesCallCount += 1
    }

    func saveTextProfiles() async throws {
        saveTextProfilesCallCount += 1
    }

    func createTextProfile(
        id: String,
        named name: String,
        replacements: [TextForSpeech.Replacement]
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.createProfile(id: id, named: name, replacements: replacements)
    }

    func storeTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.store(profile)
    }

    func useTextProfile(_ profile: TextForSpeech.Profile) async throws {
        textRuntime.use(profile)
    }

    func removeTextProfile(named profileID: String) async throws {
        textRuntime.removeProfile(named: profileID)
    }

    func resetTextProfile() async throws {
        textRuntime.reset()
    }

    func addTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        textRuntime.addReplacement(replacement)
    }

    func addTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        toStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.addReplacement(replacement, toStoredProfileNamed: profileID)
    }

    func replaceTextReplacement(_ replacement: TextForSpeech.Replacement) async throws -> TextForSpeech.Profile {
        try textRuntime.replaceReplacement(replacement)
    }

    func replaceTextReplacement(
        _ replacement: TextForSpeech.Replacement,
        inStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.replaceReplacement(replacement, inStoredProfileNamed: profileID)
    }

    func removeTextReplacement(id replacementID: String) async throws -> TextForSpeech.Profile {
        try textRuntime.removeReplacement(id: replacementID)
    }

    func removeTextReplacement(
        id replacementID: String,
        fromStoredTextProfileNamed profileID: String
    ) async throws -> TextForSpeech.Profile {
        try textRuntime.removeReplacement(id: replacementID, fromStoredProfileNamed: profileID)
    }

    // MARK: - Test Control

    func publishStatus(_ stage: SpeakSwiftly.StatusStage) {
        statusContinuation?.yield(.init(stage: stage))
    }

    func finishHeldSpeak(id: String) {
        guard activeRequest?.id == id, let continuation = activeContinuation else { return }
        continuation.yield(
            SpeakSwiftly.RequestEvent.progress(
                .init(id: id, stage: .playbackFinished)
            )
        )
            continuation.yield(
                SpeakSwiftly.RequestEvent.completed(
                    .init(id: id)
            )
        )
        continuation.finish()
        playbackState = .idle
        activeContinuation = nil
        activeRequest = nil
        startNextQueuedRequestIfNeeded()
    }

    func latestQueuedSpeechInvocation() -> QueuedSpeechInvocation? {
        queuedSpeechInvocations.last
    }

    func latestCreateProfileInvocation() -> CreateProfileInvocation? {
        createProfileInvocations.last
    }

    func latestCreateCloneInvocation() -> CreateCloneInvocation? {
        createCloneInvocations.last
    }

    func textProfilePersistenceActionCounts() -> (load: Int, save: Int) {
        (loadTextProfilesCallCount, saveTextProfilesCallCount)
    }

    // MARK: - Internal Helpers

    private func startActiveRequest(
        _ request: MockRequest,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation
    ) {
        activeRequest = request
        playbackState = .playing
        continuation.yield(.started(.init(id: request.id, op: request.operation)))

        if speakBehavior == .completeImmediately {
            continuation.yield(.progress(.init(id: request.id, stage: .startingPlayback)))
            continuation.yield(.completed(.init(id: request.id)))
            continuation.finish()
            playbackState = .idle
            activeRequest = nil
            activeContinuation = nil
            startNextQueuedRequestIfNeeded()
        } else {
            activeContinuation = continuation
        }
    }

    private func startNextQueuedRequestIfNeeded() {
        guard activeRequest == nil, !queuedRequests.isEmpty else { return }
        let next = queuedRequests.removeFirst()
        startActiveRequest(next.request, continuation: next.continuation)
    }

    private func activeSummary(for request: MockRequest) -> SpeakSwiftly.ActiveRequest {
        .init(id: request.id, op: request.operation, profileName: request.profileName)
    }

    private func queuedSummaries() -> [SpeakSwiftly.QueuedRequest] {
        queuedRequests.enumerated().map { offset, queued in
            .init(
                id: queued.request.id,
                op: queued.request.operation,
                profileName: queued.request.profileName,
                queuePosition: offset + 1
            )
        }
    }

    private func speechOperationName(for jobType: SpeakSwiftly.Job) -> String {
        switch jobType {
        case .live:
            "queue_speech_live"
        case .file:
            "queue_speech_file"
        }
    }

    private func playbackOperationName(for action: SpeakSwiftly.PlaybackAction) -> String {
        switch action {
        case .pause:
            "playback_pause"
        case .resume:
            "playback_resume"
        case .state:
            "playback_state"
        }
    }

    private func playbackStateSummary() -> SpeakSwiftly.PlaybackStateSnapshot {
        .init(
            state: playbackState,
            activeRequest: playbackState == .idle ? nil : activeRequest.map(activeSummary(for:))
        )
    }

    private func cancelQueuedRequest(_ requestID: String, reason: String) {
        guard let index = queuedRequests.firstIndex(where: { $0.request.id == requestID }) else { return }
        let queued = queuedRequests.remove(at: index)
        queued.continuation.finish(
            throwing: SpeakSwiftly.Error(code: .requestCancelled, message: reason)
        )
    }

    private func cancelRequestNow(_ requestID: String) throws -> String {
        if activeRequest?.id == requestID {
            activeContinuation?.finish(
                throwing: SpeakSwiftly.Error(
                    code: .requestCancelled,
                    message: "The request was cancelled by the mock SpeakSwiftly runtime control surface."
                )
            )
            playbackState = .idle
            activeContinuation = nil
            activeRequest = nil
            startNextQueuedRequestIfNeeded()
            return requestID
        }

        if queuedRequests.contains(where: { $0.request.id == requestID }) {
            cancelQueuedRequest(
                requestID,
                reason: "The queued request was cancelled by the mock SpeakSwiftly runtime control surface."
            )
            return requestID
        }

        throw SpeakSwiftly.Error(
            code: .requestNotFound,
            message: "The mock SpeakSwiftly runtime could not find request '\(requestID)' to cancel."
        )
    }
}

// MARK: - Route and MCP Tests

@available(macOS 14, *)
@Test func routesExposeHealthProfilesAndQueuedSpeechJobLifecycle() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
    try await app.test(.router) { client in
        let healthResponse = try await client.execute(uri: "/healthz", method: .get)
        let healthJSON = try jsonObject(from: healthResponse.body)
        #expect(healthResponse.status == .ok)
        #expect(healthJSON["status"] as? String == "ok")
        #expect(healthJSON["worker_ready"] as? Bool == true)

        let profilesResponse = try await client.execute(uri: "/profiles", method: .get)
        let profilesJSON = try jsonObject(from: profilesResponse.body)
        let profiles = try #require(profilesJSON["profiles"] as? [[String: Any]])
        #expect(profiles.count == 1)
        #expect(profiles.first?["profile_name"] as? String == "default")

        let createTextProfileResponse = try await client.execute(
            uri: "/text-profiles/stored",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"id":"swift-docs","name":"Swift Docs","replacements":[{"id":"replace-1","text":"SPM","replacement":"Swift Package Manager","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["swift_source"],"priority":3}]}"#
            )
        )
        let createTextProfileJSON = try jsonObject(from: createTextProfileResponse.body)
        let createdTextProfile = try #require(createTextProfileJSON["profile"] as? [String: Any])
        #expect(createTextProfileResponse.status == .ok)
        #expect(createdTextProfile["id"] as? String == "swift-docs")

        let textProfilesResponse = try await client.execute(uri: "/text-profiles", method: .get)
        let textProfilesJSON = try jsonObject(from: textProfilesResponse.body)
        let textProfiles = try #require(textProfilesJSON["text_profiles"] as? [String: Any])
        let storedTextProfiles = try #require(textProfiles["stored_profiles"] as? [[String: Any]])
        #expect(storedTextProfiles.contains { $0["id"] as? String == "swift-docs" })
        #expect(textProfiles["persistence_url"] as? String == "/tmp/mock-text-profiles.json")

        let loadTextProfilesResponse = try await client.execute(uri: "/text-profiles/load", method: .post)
        let loadTextProfilesJSON = try jsonObject(from: loadTextProfilesResponse.body)
        let loadedTextProfiles = try #require(loadTextProfilesJSON["text_profiles"] as? [String: Any])
        let loadedStoredProfiles = try #require(loadedTextProfiles["stored_profiles"] as? [[String: Any]])
        #expect(loadedStoredProfiles.contains { $0["id"] as? String == "swift-docs" })

        let saveTextProfilesResponse = try await client.execute(uri: "/text-profiles/save", method: .post)
        let saveTextProfilesJSON = try jsonObject(from: saveTextProfilesResponse.body)
        let savedTextProfiles = try #require(saveTextProfilesJSON["text_profiles"] as? [String: Any])
        #expect(savedTextProfiles["persistence_url"] as? String == "/tmp/mock-text-profiles.json")

        let useTextProfileResponse = try await client.execute(
            uri: "/text-profiles/active",
            method: .put,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"profile":{"id":"operator","name":"Operator","replacements":[{"id":"replace-2","text":"MCP","replacement":"Model Context Protocol","match":"exact_phrase","phase":"after_built_ins","is_case_sensitive":false,"formats":[],"priority":2}]}}"#
            )
        )
        let useTextProfileJSON = try jsonObject(from: useTextProfileResponse.body)
        let activeTextProfile = try #require(useTextProfileJSON["profile"] as? [String: Any])
        #expect(activeTextProfile["id"] as? String == "operator")

        let effectiveTextProfileResponse = try await client.execute(uri: "/text-profiles/effective/swift-docs", method: .get)
        let effectiveTextProfileJSON = try jsonObject(from: effectiveTextProfileResponse.body)
        let effectiveTextProfile = try #require(effectiveTextProfileJSON["profile"] as? [String: Any])
        let effectiveReplacements = try #require(effectiveTextProfile["replacements"] as? [[String: Any]])
        #expect(effectiveReplacements.contains { $0["id"] as? String == "replace-1" })

        let removeTextReplacementResponse = try await client.execute(
            uri: "/text-profiles/stored/swift-docs/replacements/replace-1",
            method: .delete
        )
        let removeTextReplacementJSON = try jsonObject(from: removeTextReplacementResponse.body)
        let trimmedTextProfile = try #require(removeTextReplacementJSON["profile"] as? [String: Any])
        let trimmedReplacements = try #require(trimmedTextProfile["replacements"] as? [[String: Any]])
        #expect(trimmedReplacements.isEmpty)
        let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
        #expect(persistenceActionCounts.load == 1)
        #expect(persistenceActionCounts.save == 1)

        let cloneResponse = try await client.execute(
            uri: "/profiles/clone",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"profile_name":"clone-default","vibe":"femme","reference_audio_path":"./Fixtures/reference.wav","transcript":"Cloned route test transcript.","cwd":"/tmp/http-clone-cwd"}"#
            )
        )
        let cloneJSON = try jsonObject(from: cloneResponse.body)
        let cloneJobID = try #require(cloneJSON["job_id"] as? String)
        #expect(cloneResponse.status == .accepted)
        _ = try await waitForJobSnapshot(cloneJobID, on: host)

        let cloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
        #expect(cloneInvocation.profileName == "clone-default")
        #expect(cloneInvocation.referenceAudioPath == "./Fixtures/reference.wav")
        #expect(cloneInvocation.transcript == "Cloned route test transcript.")
        #expect(cloneInvocation.cwd == "/tmp/http-clone-cwd")

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Route test","profile_name":"default","text_profile_name":"swift-docs","cwd":"./Sources","repo_root":"../SpeakSwiftlyServer","text_format":"markdown","nested_source_format":"swift_source","source_format":"python_source"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        let speakJobID = try #require(speakJSON["job_id"] as? String)
        #expect(speakResponse.status == .accepted)
        #expect((speakJSON["job_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["events_url"] as? String)?.contains(speakJobID) == true)
        #expect((speakJSON["job_url"] as? String)?.hasPrefix("http://") == true)
        let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
        #expect(
            queuedSpeechInvocation.normalizationContext
                == SpeechNormalizationContext(
                    cwd: "./Sources",
                    repoRoot: "../SpeakSwiftlyServer",
                    textFormat: .markdown,
                    nestedSourceFormat: .swift
                )
        )
        #expect(queuedSpeechInvocation.textProfileName == "swift-docs")
        #expect(queuedSpeechInvocation.sourceFormat == .python)

        _ = try await waitForJobSnapshot(speakJobID, on: host)

        let jobsResponse = try await client.execute(uri: "/jobs", method: .get)
        let jobsJSON = try jsonObject(from: jobsResponse.body)
        let jobs = try #require(jobsJSON["jobs"] as? [[String: Any]])
        #expect(jobsResponse.status == .ok)
        #expect(jobs.contains { $0["job_id"] as? String == speakJobID })

        let foregroundJobResponse = try await client.execute(uri: "/jobs/\(speakJobID)", method: .get)
        let foregroundJobJSON = try jsonObject(from: foregroundJobResponse.body)
        #expect(foregroundJobResponse.status == .ok)
        #expect(foregroundJobJSON["job_id"] as? String == speakJobID)
        #expect(foregroundJobJSON["status"] as? String == "completed")
        let foregroundHistory = try #require(foregroundJobJSON["history"] as? [[String: Any]])
        #expect(foregroundHistory.contains { $0["event"] as? String == "started" })
        #expect(foregroundHistory.filter { $0["ok"] as? Bool == true }.count == 2)
    }

    await host.shutdown()
}

// MARK: - MCP Tests

@available(macOS 14, *)
@Test func embeddedMCPRoutesListToolsAndReadSharedHostResources() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: "mcp")

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()
    await host.markTransportListening(name: "mcp")
    let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
    let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
    try await drainMCPResponse(initializeMCPResponse)

    let initializedNotificationResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: initializeSessionID
        )
    )
    #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

    let listToolsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListToolsRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listToolsResult = try #require(mcpResultPayload(from: listToolsEnvelope))
    let tools = try #require(listToolsResult["tools"] as? [[String: Any]])
    let toolNames = Set(tools.compactMap { $0["name"] as? String })
    #expect(toolNames == Set(MCPToolCatalog.definitions.map(\.name)))
    #expect(tools.contains { $0["name"] as? String == "queue_speech_live" })
    #expect(tools.contains { $0["name"] as? String == "create_clone" })
    #expect(tools.contains { $0["name"] as? String == "status" })

    let queueSpeechToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "queue_speech_live",
                    arguments: [
                        "text": "Inspect MCP resources",
                        "profile_name": "default",
                        "text_profile_name": "mcp-text",
                        "cwd": "./Tests",
                        "repo_root": "../SpeakSwiftlyServer",
                        "text_format": "cli_output",
                        "nested_source_format": "rust_source",
                        "source_format": "source_code",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let queueSpeechToolPayload = try mcpToolPayload(from: queueSpeechToolEnvelope)
    let jobID = try #require(queueSpeechToolPayload["job_id"] as? String)
    #expect(queueSpeechToolPayload["status_resource_uri"] as? String == "speak://status")
    #expect(queueSpeechToolPayload["job_resource_uri"] as? String == "speak://jobs/\(jobID)")
    let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
    #expect(
        queuedSpeechInvocation.normalizationContext
            == SpeechNormalizationContext(
                cwd: "./Tests",
                repoRoot: "../SpeakSwiftlyServer",
                textFormat: .cli,
                nestedSourceFormat: .rust
            )
    )
    #expect(queuedSpeechInvocation.textProfileName == "mcp-text")
    #expect(queuedSpeechInvocation.sourceFormat == .generic)

    let createCloneToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "create_clone",
                    arguments: [
                        "profile_name": "clone-from-mcp",
                        "vibe": "androgenous",
                        "reference_audio_path": "./Fixtures/mcp-reference.wav",
                        "transcript": "Imported from MCP",
                        "cwd": "/tmp/mcp-clone-cwd",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let createCloneToolPayload = try mcpToolPayload(from: createCloneToolEnvelope)
    let createCloneJobID = try #require(createCloneToolPayload["job_id"] as? String)
    #expect(createCloneToolPayload["job_resource_uri"] as? String == "speak://jobs/\(createCloneJobID)")
    let createCloneInvocation = try #require(await runtime.latestCreateCloneInvocation())
    #expect(createCloneInvocation.profileName == "clone-from-mcp")
    #expect(createCloneInvocation.vibe == .androgenous)
    #expect(createCloneInvocation.referenceAudioPath == "./Fixtures/mcp-reference.wav")
    #expect(createCloneInvocation.transcript == "Imported from MCP")
    #expect(createCloneInvocation.cwd == "/tmp/mcp-clone-cwd")

    let listResourcesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListResourcesRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listResourcesResult = try #require(mcpResultPayload(from: listResourcesEnvelope))
    let resources = try #require(listResourcesResult["resources"] as? [[String: Any]])
    let resourceURIs = Set(resources.compactMap { $0["uri"] as? String })
    #expect(resourceURIs == Set(MCPResourceCatalog.resources.map(\.uri)))
    #expect(resources.contains { $0["uri"] as? String == "speak://status" })
    #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles" })
    #expect(resources.contains { $0["uri"] as? String == "speak://profiles/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://text-profiles/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://playback/guide" })
    #expect(resources.contains { $0["uri"] as? String == "speak://jobs" })
    #expect(resources.contains { $0["uri"] as? String == "speak://runtime" })

    let listResourceTemplatesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListResourceTemplatesRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listResourceTemplatesResult = try #require(mcpResultPayload(from: listResourceTemplatesEnvelope))
    let templates = try #require(listResourceTemplatesResult["resourceTemplates"] as? [[String: Any]])
    let templateURIs = Set(templates.compactMap { $0["uriTemplate"] as? String })
    #expect(templateURIs == Set(MCPResourceCatalog.templates.map(\.uriTemplate)))
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://profiles/{profile_name}/detail" })
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://text-profiles/stored/{profile_id}" })
    #expect(templates.contains { $0["uriTemplate"] as? String == "speak://jobs/{job_id}" })

    let createTextProfileEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: #"{"jsonrpc":"2.0","id":"tool-text-profile-1","method":"tools/call","params":{"name":"create_text_profile","arguments":{"id":"mcp-text","name":"MCP Text","replacements":[{"id":"mcp-replacement","text":"CLI","replacement":"command line interface","match":"whole_token","phase":"before_built_ins","is_case_sensitive":false,"formats":["cli_output"],"priority":1}]}}}"#,
                sessionID: initializeSessionID
            )
        )
    )
    let createTextProfilePayload = try mcpToolPayload(from: createTextProfileEnvelope)
    #expect(createTextProfilePayload["id"] as? String == "mcp-text")

    let listTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "list_text_profiles",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let listTextProfilesPayload = try mcpToolPayload(from: listTextProfilesEnvelope)
    let listTextStoredProfiles = try #require(listTextProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(listTextStoredProfiles.contains { $0["id"] as? String == "mcp-text" })
    #expect(listTextProfilesPayload["persistence_url"] as? String == "/tmp/mock-text-profiles.json")

    let loadTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "load_text_profiles",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let loadTextProfilesPayload = try mcpToolPayload(from: loadTextProfilesEnvelope)
    let loadedStoredProfiles = try #require(loadTextProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(loadedStoredProfiles.contains { $0["id"] as? String == "mcp-text" })

    let saveTextProfilesEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "save_text_profiles",
                    arguments: [:]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let saveTextProfilesPayload = try mcpToolPayload(from: saveTextProfilesEnvelope)
    #expect(saveTextProfilesPayload["persistence_url"] as? String == "/tmp/mock-text-profiles.json")
    let persistenceActionCounts = await runtime.textProfilePersistenceActionCounts()
    #expect(persistenceActionCounts.load == 1)
    #expect(persistenceActionCounts.save == 1)

    let listPromptsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListPromptsRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let listPromptsResult = try #require(mcpResultPayload(from: listPromptsEnvelope))
    let prompts = try #require(listPromptsResult["prompts"] as? [[String: Any]])
    let promptNames = Set(prompts.compactMap { $0["name"] as? String })
    #expect(promptNames == Set(MCPPromptCatalog.prompts.map(\.name)))
    #expect(prompts.contains { $0["name"] as? String == "draft_profile_voice_description" })
    #expect(prompts.contains { $0["name"] as? String == "draft_text_profile" })
    #expect(prompts.contains { $0["name"] as? String == "draft_text_replacement" })
    #expect(prompts.contains { $0["name"] as? String == "draft_queue_playback_notice" })
    #expect(prompts.contains { $0["name"] as? String == "choose_surface_action" })

    let getPromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "draft_profile_voice_description",
                    arguments: [
                        "profile_goal": "gentle narration",
                        "voice_traits": "warm, steady, intimate",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let getPromptResult = try #require(mcpResultPayload(from: getPromptEnvelope))
    let promptMessages = try #require(getPromptResult["messages"] as? [[String: Any]])
    let firstPromptMessage = try #require(promptMessages.first)
    let promptContent = try #require(firstPromptMessage["content"] as? [String: Any])
    #expect((promptContent["text"] as? String)?.contains("gentle narration") == true)

    let textProfilePromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "draft_text_profile",
                    arguments: [
                        "user_goal": "expand acronyms in technical speech",
                        "profile_scope": "swift package walkthroughs",
                        "format_focus": "swift_source",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilePromptResult = try #require(mcpResultPayload(from: textProfilePromptEnvelope))
    let textProfilePromptMessages = try #require(textProfilePromptResult["messages"] as? [[String: Any]])
    let textProfilePromptContent = try #require(textProfilePromptMessages.first?["content"] as? [String: Any])
    #expect((textProfilePromptContent["text"] as? String)?.contains("expand acronyms in technical speech") == true)

    let statusToolEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpStatusToolRequestJSON(),
                sessionID: initializeSessionID
            )
        )
    )
    let statusToolPayload = try mcpToolPayload(from: statusToolEnvelope)
    #expect(statusToolPayload["worker_mode"] as? String == "ready")
    let transports = try #require(statusToolPayload["transports"] as? [[String: Any]])
    #expect(transports.contains { $0["name"] as? String == "mcp" && $0["state"] as? String == "listening" })

    let runtimeResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://runtime"),
                sessionID: initializeSessionID
            )
        )
    )
    let runtimeResourceResult = try #require(mcpResultPayload(from: runtimeResourceEnvelope))
    let contents = try #require(runtimeResourceResult["contents"] as? [[String: Any]])
    let firstContent = try #require(contents.first)
    let runtimeText = try #require(firstContent["text"] as? String)
    let runtimePayload = try jsonObject(from: Data(runtimeText.utf8))
    let runtimeTransports = try #require(runtimePayload["transports"] as? [[String: Any]])
    #expect(runtimeTransports.contains { $0["name"] as? String == "mcp" && $0["advertised_address"] as? String == "http://127.0.0.1:7337/mcp" })

    let jobsResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://jobs"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobsResourceResult = try #require(mcpResultPayload(from: jobsResourceEnvelope))
    let jobsContents = try #require(jobsResourceResult["contents"] as? [[String: Any]])
    let jobsText = try #require(jobsContents.first?["text"] as? String)
    let jobsPayload = try #require(try JSONSerialization.jsonObject(with: Data(jobsText.utf8)) as? [[String: Any]])
    #expect(jobsPayload.contains { $0["job_id"] as? String == jobID })

    let profileDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://profiles/default/detail"),
                sessionID: initializeSessionID
            )
        )
    )
    let profileDetailResult = try #require(mcpResultPayload(from: profileDetailEnvelope))
    let profileDetailContents = try #require(profileDetailResult["contents"] as? [[String: Any]])
    let profileDetailText = try #require(profileDetailContents.first?["text"] as? String)
    let profileDetailPayload = try jsonObject(from: Data(profileDetailText.utf8))
    #expect(profileDetailPayload["profile_name"] as? String == "default")

    let textProfilesResourceEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles"),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilesResourceResult = try #require(mcpResultPayload(from: textProfilesResourceEnvelope))
    let textProfilesContents = try #require(textProfilesResourceResult["contents"] as? [[String: Any]])
    let textProfilesText = try #require(textProfilesContents.first?["text"] as? String)
    let textProfilesPayload = try jsonObject(from: Data(textProfilesText.utf8))
    let storedProfilesPayload = try #require(textProfilesPayload["stored_profiles"] as? [[String: Any]])
    #expect(storedProfilesPayload.contains { $0["id"] as? String == "mcp-text" })

    let textProfilesGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let textProfilesGuideResult = try #require(mcpResultPayload(from: textProfilesGuideEnvelope))
    let textProfilesGuideContents = try #require(textProfilesGuideResult["contents"] as? [[String: Any]])
    let textProfilesGuideText = try #require(textProfilesGuideContents.first?["text"] as? String)
    #expect(textProfilesGuideText.contains("text_profile_name"))

    let voiceProfilesGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://profiles/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let voiceProfilesGuideResult = try #require(mcpResultPayload(from: voiceProfilesGuideEnvelope))
    let voiceProfilesGuideContents = try #require(voiceProfilesGuideResult["contents"] as? [[String: Any]])
    let voiceProfilesGuideText = try #require(voiceProfilesGuideContents.first?["text"] as? String)
    #expect(voiceProfilesGuideText.contains("create_clone"))
    #expect(voiceProfilesGuideText.contains("queue_speech_live"))

    let playbackGuideEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://playback/guide"),
                sessionID: initializeSessionID
            )
        )
    )
    let playbackGuideResult = try #require(mcpResultPayload(from: playbackGuideEnvelope))
    let playbackGuideContents = try #require(playbackGuideResult["contents"] as? [[String: Any]])
    let playbackGuideText = try #require(playbackGuideContents.first?["text"] as? String)
    #expect(playbackGuideText.contains("cancel_request"))
    #expect(playbackGuideText.contains("clear_queue"))

    let chooseActionPromptEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpGetPromptRequestJSON(
                    name: "choose_surface_action",
                    arguments: [
                        "user_goal": "Help the user decide whether to clone a voice or create a synthetic profile.",
                        "current_context": "The user has not provided reference audio yet.",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let chooseActionPromptResult = try #require(mcpResultPayload(from: chooseActionPromptEnvelope))
    let chooseActionPromptMessages = try #require(chooseActionPromptResult["messages"] as? [[String: Any]])
    let chooseActionPromptContent = try #require(chooseActionPromptMessages.first?["content"] as? [String: Any])
    let chooseActionPromptText = try #require(chooseActionPromptContent["text"] as? String)
    #expect(chooseActionPromptText.contains("action_type"))
    #expect(chooseActionPromptText.contains("create_profile"))

    let storedTextProfileEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://text-profiles/stored/mcp-text"),
                sessionID: initializeSessionID
            )
        )
    )
    let storedTextProfileResult = try #require(mcpResultPayload(from: storedTextProfileEnvelope))
    let storedTextProfileContents = try #require(storedTextProfileResult["contents"] as? [[String: Any]])
    let storedTextProfileText = try #require(storedTextProfileContents.first?["text"] as? String)
    let storedTextProfilePayload = try jsonObject(from: Data(storedTextProfileText.utf8))
    #expect(storedTextProfilePayload["id"] as? String == "mcp-text")

    let jobDetailEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpReadResourceRequestJSON(uri: "speak://jobs/\(jobID)"),
                sessionID: initializeSessionID
            )
        )
    )
    let jobDetailResult = try #require(mcpResultPayload(from: jobDetailEnvelope))
    let jobDetailContents = try #require(jobDetailResult["contents"] as? [[String: Any]])
    let jobDetailText = try #require(jobDetailContents.first?["text"] as? String)
    let jobDetailPayload = try jsonObject(from: Data(jobDetailText.utf8))
    #expect(jobDetailPayload["job_id"] as? String == jobID)

    let smokeSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp-smoke",
                title: "SpeakSwiftly Test MCP Smoke"
            ),
            host: host
        )
    )
    let smokeApp = assembleHBApp(
        configuration: testHTTPConfig(configuration),
        host: host,
        mcpSurface: smokeSurface
    )
    try await smokeSurface.start()
    try await smokeApp.test(.router) { client in
        let initializeResponse = try await client.execute(
            uri: "/mcp",
            method: .post,
            headers: [
                .contentType: "application/json",
                .accept: "application/json, text/event-stream",
            ],
            body: byteBuffer(mcpInitializeRequestJSON(id: "initialize-smoke"))
        )
        #expect(initializeResponse.status == .ok)
        #expect(mcpSessionID(from: initializeResponse)?.isEmpty == false)
    }
    await smokeSurface.stop()

    await runtime.finishHeldSpeak(id: jobID)
    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedMCPSupportsMultipleIndependentSessions() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()

    let firstInitializeResponse = await mcpSurface.handle(
        mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-first"))
    )
    let firstSessionID = try #require(mcpSessionID(from: firstInitializeResponse))
    try await drainMCPResponse(firstInitializeResponse)

    let secondInitializeResponse = await mcpSurface.handle(
        mcpPOSTRequest(body: mcpInitializeRequestJSON(id: "initialize-second"))
    )
    let secondSessionID = try #require(mcpSessionID(from: secondInitializeResponse))
    try await drainMCPResponse(secondInitializeResponse)

    #expect(firstSessionID != secondSessionID)

    let firstInitializedNotification = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: firstSessionID
        )
    )
    #expect(mcpStatusCode(from: firstInitializedNotification) == 202)

    let secondInitializedNotification = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: secondSessionID
        )
    )
    #expect(mcpStatusCode(from: secondInitializedNotification) == 202)

    let firstStatusEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpStatusToolRequestJSON(),
                sessionID: firstSessionID
            )
        )
    )
    let firstStatusPayload = try mcpToolPayload(from: firstStatusEnvelope)
    #expect(firstStatusPayload["worker_mode"] as? String == "ready")

    let secondToolsEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpListToolsRequestJSON(),
                sessionID: secondSessionID
            )
        )
    )
    let secondToolsResult = try #require(mcpResultPayload(from: secondToolsEnvelope))
    let secondTools = try #require(secondToolsResult["tools"] as? [[String: Any]])
    #expect(secondTools.contains { $0["name"] as? String == "status" })

    let deleteFirstSessionResponse = await mcpSurface.handle(
        mcpDELETERequest(sessionID: firstSessionID)
    )
    #expect(mcpStatusCode(from: deleteFirstSessionResponse) == 200)

    let deletedSessionResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpStatusToolRequestJSON(),
            sessionID: firstSessionID
        )
    )
    #expect(mcpStatusCode(from: deletedSessionResponse) == 404)

    let survivingSessionEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpStatusToolRequestJSON(),
                sessionID: secondSessionID
            )
        )
    )
    let survivingSessionPayload = try mcpToolPayload(from: survivingSessionEnvelope)
    #expect(survivingSessionPayload["worker_mode"] as? String == "ready")

    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func speakRouteRejectsUnsupportedFormatArgumentsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
    try await app.test(.router) { client in
        let response = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(
                #"{"text":"Bad format","profile_name":"default","text_format":"totally_invalid","source_format":"not_a_real_source"}"#
            )
        )
        let responseJSON = try jsonObject(from: response.body)
        let error = try #require(responseJSON["error"] as? [String: Any])
        let message = try #require(error["message"] as? String)

        #expect(response.status == .badRequest)
        #expect(message.contains("text_format"))
        #expect(message.contains("totally_invalid"))
        #expect(message.contains("plain"))
    }

    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedMCPRejectsUnsupportedFormatArgumentsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()
    await host.markTransportListening(name: "mcp")
    let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
    let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
    try await drainMCPResponse(initializeMCPResponse)

    let initializedNotificationResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: initializeSessionID
        )
    )
    #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

    let errorEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpCallToolRequestJSON(
                    name: "queue_speech_live",
                    arguments: [
                        "text": "Bad format",
                        "profile_name": "default",
                        "text_format": "totally_invalid",
                    ]
                ),
                sessionID: initializeSessionID
            )
        )
    )
    let error = try #require(errorEnvelope["error"] as? [String: Any])
    let message = try #require(error["message"] as? String)
    #expect(message.contains("text_format"))
    #expect(message.contains("totally_invalid"))
    #expect(message.contains("plain"))

    await host.shutdown()
}

@available(macOS 14, *)
@Test func embeddedMCPResourceSubscriptionsEmitUpdatedNotifications() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        httpConfig: testHTTPConfig(configuration),
        mcpConfig: .init(
            enabled: true,
            path: "/mcp",
            serverName: "speak-swiftly-test-mcp",
            title: "SpeakSwiftly Test MCP"
        ),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)
    await host.markTransportStarting(name: "http")
    await host.markTransportStarting(name: "mcp")

    let mcpSurface = try #require(
        await MCPSurface.build(
            configuration: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP"
            ),
            host: host
        )
    )

    try await mcpSurface.start()
    await host.markTransportListening(name: "mcp")

    let initializeResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
    let sessionID = try #require(mcpSessionID(from: initializeResponse))
    try await drainMCPResponse(initializeResponse)

    let initializedNotificationResponse = await mcpSurface.handle(
        mcpPOSTRequest(
            body: mcpInitializedNotificationJSON(),
            sessionID: sessionID
        )
    )
    #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

    let streamResponse = await mcpSurface.handle(mcpGETRequest(sessionID: sessionID))
    guard case .stream(let stream, _) = streamResponse else {
        Issue.record("Expected the embedded MCP GET transport to return a standalone streaming response.")
        await mcpSurface.stop()
        await host.shutdown()
        return
    }
    var streamIterator = stream.makeAsyncIterator()
    _ = try await nextMCPStreamEnvelope(from: &streamIterator)

    let subscribeEnvelope = try await mcpEnvelope(
        from: await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpSubscribeResourceRequestJSON(uri: "speak://runtime"),
                sessionID: sessionID
            )
        )
    )
    #expect(subscribeEnvelope["result"] != nil)

    await host.markTransportFailed(
        name: "http",
        message: "SpeakSwiftlyServer test transport failure for MCP resource subscription coverage."
    )

    let updatedNotification = try await nextMCPStreamEnvelope(from: &streamIterator)
    #expect(updatedNotification["method"] as? String == "notifications/resources/updated")
    let notificationParams = try #require(updatedNotification["params"] as? [String: Any])
    #expect(notificationParams["uri"] as? String == "speak://runtime")

    await mcpSurface.stop()
    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesExposeQueueInspectionAndControlOperations() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
    try await app.test(.router) { client in
        let activeResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Hold the line","profile_name":"default"}"#)
        )
        let activeJobID = try #require(try jsonObject(from: activeResponse.body)["job_id"] as? String)

        let queuedResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue this request","profile_name":"default"}"#)
        )
        let queuedJobID = try #require(try jsonObject(from: queuedResponse.body)["job_id"] as? String)

        let queueResponse = try await client.execute(uri: "/queue/generation", method: .get)
        let queueJSON = try jsonObject(from: queueResponse.body)
        #expect(queueResponse.status == .ok)
        #expect(queueJSON["queue_type"] as? String == "generation")
        let activeRequest = try #require(queueJSON["active_request"] as? [String: Any])
        #expect(activeRequest["id"] as? String == activeJobID)
        let queuedRequests = try #require(queueJSON["queue"] as? [[String: Any]])
        #expect(queuedRequests.count == 1)
        #expect(queuedRequests.first?["id"] as? String == queuedJobID)
        #expect(queuedRequests.first?["queue_position"] as? Int == 1)

        let playbackStateResponse = try await client.execute(uri: "/playback", method: .get)
        let playbackStateJSON = try jsonObject(from: playbackStateResponse.body)
        #expect(playbackStateResponse.status == .ok)
        let playback = try #require(playbackStateJSON["playback"] as? [String: Any])
        #expect(playback["state"] as? String == "playing")
        let playbackActiveRequest = try #require(playback["active_request"] as? [String: Any])
        #expect(playbackActiveRequest["id"] as? String == activeJobID)

        let pauseResponse = try await client.execute(uri: "/playback/pause", method: .post)
        let pauseJSON = try jsonObject(from: pauseResponse.body)
        #expect(pauseResponse.status == .ok)
        #expect((pauseJSON["playback"] as? [String: Any])?["state"] as? String == "paused")

        let resumeResponse = try await client.execute(uri: "/playback/resume", method: .post)
        let resumeJSON = try jsonObject(from: resumeResponse.body)
        #expect(resumeResponse.status == .ok)
        #expect((resumeJSON["playback"] as? [String: Any])?["state"] as? String == "playing")

        let playbackQueueResponse = try await client.execute(uri: "/queue/playback", method: .get)
        let playbackQueueJSON = try jsonObject(from: playbackQueueResponse.body)
        #expect(playbackQueueResponse.status == .ok)
        #expect(playbackQueueJSON["queue_type"] as? String == "playback")
        #expect((playbackQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
        #expect((playbackQueueJSON["queue"] as? [[String: Any]])?.isEmpty == true)

        let cancelResponse = try await client.execute(uri: "/queue/\(queuedJobID)", method: .delete)
        let cancelJSON = try jsonObject(from: cancelResponse.body)
        #expect(cancelResponse.status == .ok)
        #expect(cancelJSON["cancelled_request_id"] as? String == queuedJobID)

        let cancelledSnapshot = try await waitForJobSnapshot(queuedJobID, on: host)
        switch cancelledSnapshot.terminalEvent {
        case .failed(let failure):
            #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
        default:
            Issue.record("Expected the cancelled queued request to terminate with a request_cancelled failure.")
        }

        let anotherQueuedResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Queue another request","profile_name":"default"}"#)
        )
        let anotherQueuedJobID = try #require(try jsonObject(from: anotherQueuedResponse.body)["job_id"] as? String)

        let clearResponse = try await client.execute(uri: "/queue", method: .delete)
        let clearJSON = try jsonObject(from: clearResponse.body)
        #expect(clearResponse.status == .ok)
        #expect(clearJSON["cleared_count"] as? Int == 1)

        let clearedSnapshot = try await waitForJobSnapshot(anotherQueuedJobID, on: host)
        switch clearedSnapshot.terminalEvent {
        case .failed(let failure):
            #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
        default:
            Issue.record("Expected the cleared queued request to terminate with a request_cancelled failure.")
        }

        let emptyQueueResponse = try await client.execute(uri: "/queue/generation", method: .get)
        let emptyQueueJSON = try jsonObject(from: emptyQueueResponse.body)
        let remainingQueue = try #require(emptyQueueJSON["queue"] as? [[String: Any]])
        #expect(remainingQueue.isEmpty)
        #expect((emptyQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
    }

    await runtime.finishHeldSpeak(id: try await waitForActiveRequestID(on: host))
    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesReportNotReadyAndMissingJobsClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
    try await app.test(.router) { client in
        let readyResponse = try await client.execute(uri: "/readyz", method: .get)
        let readyJSON = try jsonObject(from: readyResponse.body)
        #expect(readyResponse.status == .serviceUnavailable)
        #expect(readyJSON["status"] as? String == "not_ready")

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Too soon","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        #expect(speakResponse.status == .serviceUnavailable)
        let speakError = try #require(speakJSON["error"] as? [String: Any])
        #expect((speakError["message"] as? String)?.contains("cannot accept new work") == true)

        let missingJob = try await client.execute(uri: "/jobs/missing-job", method: .get)
        let missingJSON = try jsonObject(from: missingJob.body)
        #expect(missingJob.status == .notFound)
        let missingJobError = try #require(missingJSON["error"] as? [String: Any])
        #expect((missingJobError["message"] as? String)?.contains("expired from in-memory retention") == true)

        let missingEvents = try await client.execute(uri: "/jobs/missing-job/events", method: .get)
        let missingEventsJSON = try jsonObject(from: missingEvents.body)
        #expect(missingEvents.status == .notFound)
        let missingEventsError = try #require(missingEventsJSON["error"] as? [String: Any])
        #expect((missingEventsError["message"] as? String)?.contains("expired from in-memory retention") == true)
    }

    await host.shutdown()
}

@available(macOS 14, *)
@Test func routesReportWorkerStartupFailureClearly() async throws {
    let runtime = MockRuntime()
    let configuration = testConfiguration()
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: configuration,
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelFailed)

    let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
    try await app.test(.router) { client in
        let readyResponse = try await client.execute(uri: "/readyz", method: .get)
        let readyJSON = try jsonObject(from: readyResponse.body)
        #expect(readyResponse.status == .serviceUnavailable)
        #expect(readyJSON["status"] as? String == "not_ready")
        #expect(readyJSON["worker_mode"] as? String == "failed")
        #expect((readyJSON["startup_error"] as? String)?.contains("startup failure") == true)

        let statusResponse = try await client.execute(uri: "/status", method: .get)
        let statusJSON = try jsonObject(from: statusResponse.body)
        #expect(statusResponse.status == .ok)
        #expect(statusJSON["worker_mode"] as? String == "failed")
        #expect(statusJSON["worker_stage"] as? String == "resident_model_failed")
        #expect((statusJSON["worker_failure_summary"] as? String)?.contains("startup failure") == true)

        let speakResponse = try await client.execute(
            uri: "/speak",
            method: .post,
            headers: [.contentType: "application/json"],
            body: byteBuffer(#"{"text":"Still broken","profile_name":"default"}"#)
        )
        let speakJSON = try jsonObject(from: speakResponse.body)
        #expect(speakResponse.status == .serviceUnavailable)
        let speakError = try #require(speakJSON["error"] as? [String: Any])
        #expect((speakError["message"] as? String)?.contains("startup failure") == true)
    }

    await host.shutdown()
}

@available(macOS 14, *)
@Test func runtimeDegradationWhileSpeechJobsAreInFlightMarksJobsDegradedAndRejectsNewWork() async throws {
    let runtime = MockRuntime(speakBehavior: .holdOpen)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let activeJobID = try await host.submitSpeak(text: "Keep talking", profileName: "default")
    let queuedJobID = try await host.submitSpeak(text: "Wait your turn", profileName: "default")

    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: queuedJobID)
        return snapshot.history.contains {
            guard case .queued = $0 else { return false }
            return true
        } ? snapshot : nil
    }

    await runtime.publishStatus(.residentModelFailed)

    let degradedReadiness = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = await host.readinessSnapshot()
        return snapshot.1.workerMode == "failed" ? snapshot : nil
    }
    #expect(degradedReadiness.0 == false)
    #expect(degradedReadiness.1.workerMode == "failed")
    #expect(degradedReadiness.1.workerStage == "resident_model_failed")
    #expect(degradedReadiness.1.startupError?.contains("startup failure") == true)

    let activeSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: activeJobID)
        return snapshot.history.contains {
            guard case .workerStatus(let event) = $0 else { return false }
            return event.workerMode == "failed" && event.stage == "resident_model_failed"
        } ? snapshot : nil
    }
    #expect(activeSnapshot.terminalEvent == nil)

    let queuedSnapshot = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.jobSnapshot(id: queuedJobID)
        return snapshot.history.contains {
            guard case .workerStatus(let event) = $0 else { return false }
            return event.workerMode == "failed" && event.stage == "resident_model_failed"
        } ? snapshot : nil
    }
    #expect(queuedSnapshot.terminalEvent == nil)

    do {
        _ = try await host.submitSpeak(text: "Do not accept this", profileName: "default")
        Issue.record("Expected the degraded worker state to reject new speech work.")
    } catch {
        let message = String(describing: error)
        #expect(message.contains("startup failure"))
    }

    await runtime.finishHeldSpeak(id: activeJobID)
    await host.shutdown()
}

@available(macOS 14, *)
@Test func profileMutationFailureMarksCacheStaleAndFailsJob() async throws {
    let runtime = MockRuntime(mutationRefreshBehavior: .leaveProfilesUnchanged)
    let state = await MainActor.run { ServerState() }
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        state: state
    )

    await host.start()
    await runtime.publishStatus(.residentModelReady)
    try await waitUntilReady(host)

    let jobID = try await host.submitCreateProfile(
        profileName: "bright-guide",
        vibe: .femme,
        text: "Hello there",
        voiceDescription: "Warm and bright",
        outputPath: nil,
        cwd: nil
    )
    let snapshot = try await waitForJobSnapshot(jobID, on: host)

    switch snapshot.terminalEvent {
    case .failed(let failure):
        #expect(failure.code == "profile_refresh_mismatch")
        #expect(failure.message.contains("could not confirm the profile list"))
    default:
        Issue.record("Expected create_profile reconciliation failure to produce a failed terminal event.")
    }

    let status = await host.statusSnapshot()
    #expect(status.profileCacheState == "stale")
    #expect(status.profileCacheWarning?.contains("could not confirm the refreshed profile list") == true)

    await host.shutdown()
}
