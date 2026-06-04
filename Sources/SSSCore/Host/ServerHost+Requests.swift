import Foundation
import SpeakSwiftly

package extension ServerHost {
    func remoteGenerationConfiguration() -> RemoteGenerationConfig {
        remoteGenerationConfig
    }

    func queueSpeechLive(
        text: String,
        profileName: String,
        textProfileID: String? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
        generationLocation: GenerationLocation = .local,
    ) async throws -> String {
        try ensureWorkerReady()
        switch generationLocation {
            case .local:
                let handle = await runtime.queueSpeechLive(
                    text: text,
                    with: profileName,
                    textProfileID: textProfileID,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                )
                return await enqueuePublicJob(handle)
            case let .remote(service):
                return await enqueueRemoteSpeechLive(
                    text: text,
                    profileName: profileName,
                    textProfileID: textProfileID,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                    service: service,
                )
        }
    }

    func generateSpeechAudioStream(
        text: String,
        profileName: String,
        textProfileID: String? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
        qwenPreModelTextChunking: Bool = false,
    ) async throws -> RuntimeGeneratedAudioStream {
        try ensureWorkerReady()
        let stream = await runtime.generateAudioStream(
            text: text,
            with: profileName,
            textProfileID: textProfileID,
            requestContext: requestContext,
            qwenPreModelTextChunking: qwenPreModelTextChunking,
        )
        _ = await enqueuePublicJob(stream.handle)
        return stream
    }

    func enqueueRemoteSpeechLive(
        text: String,
        profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
        service: RemoteGenerationService,
    ) async -> String {
        let requestID = UUID().uuidString
        let events = AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error> { continuation in
            let task = Task {
                await runRemoteSpeechLive(
                    requestID: requestID,
                    text: text,
                    profileName: profileName,
                    textProfileID: textProfileID,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                    service: service,
                    continuation: continuation,
                )
            }
            registerRemoteGenerationRequestTask(task, requestID: requestID)
            continuation.onTermination = { _ in
                task.cancel()
                Task {
                    await self.clearRemoteGenerationRequestTask(id: requestID)
                }
            }
        }
        let handle = RuntimeRequestHandle(
            id: requestID,
            operation: "generate_speech",
            profileName: profileName,
            events: events,
        )
        return await enqueuePublicJob(handle)
    }

    func runRemoteSpeechLive(
        requestID: String,
        text: String,
        profileName: String,
        textProfileID: String?,
        requestContext: SpeakSwiftly.RequestContext?,
        qwenPreModelTextChunking: Bool,
        service: RemoteGenerationService,
        continuation: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>.Continuation,
    ) async {
        continuation.yield(.started(.init(id: requestID, kind: .generateSpeech)))
        continuation.yield(.progress(.init(id: requestID, stage: .bufferingAudio)))
        var remoteSession: RemoteSpeechStreamSession?
        defer {
            clearRemoteGenerationRequestTask(id: requestID)
        }
        do {
            guard let sharedToken = remoteGenerationConfig.sharedToken else {
                throw SpeakSwiftly.Error(
                    code: .invalidRequest,
                    message: "SpeakSwiftlyServer cannot route remote generation request '\(requestID)' to '\(service.serviceName ?? service.baseURL)' because app.remoteGeneration.sharedToken is empty in this server's configuration.",
                )
            }

            let session = remoteGeneratedAudioStreamProvider(
                .init(
                    text: text,
                    profileName: profileName,
                    textProfileID: textProfileID,
                    requestContext: requestContext,
                    qwenPreModelTextChunking: qwenPreModelTextChunking,
                ),
                service,
                sharedToken,
            )
            remoteSession = session
            try await routeRemoteGeneratedAudio(
                chunks: session.chunks,
                requestID: requestID,
            )
            try Task.checkCancellation()
            continuation.yield(.completed(.empty))
            continuation.finish()
        } catch is CancellationError {
            await cancelRemoteGenerationUpstream(
                remoteSession,
                requestID: requestID,
                service: service,
            )
            continuation.finish(
                throwing: SpeakSwiftly.Error(
                    code: .requestCancelled,
                    message: "SpeakSwiftlyServer cancelled remote generation request '\(requestID)' before playback finished.",
                ),
            )
        } catch let error as SpeakSwiftly.Error {
            continuation.finish(throwing: error)
        } catch {
            continuation.finish(
                throwing: SpeakSwiftly.Error(
                    code: .internalError,
                    message: "SpeakSwiftlyServer could not complete remote generation request '\(requestID)' from '\(service.serviceName ?? service.baseURL)'. Likely cause: \(error.localizedDescription)",
                ),
            )
        }
    }

    func registerRemoteGenerationRequestTask(_ task: Task<Void, Never>, requestID: String) {
        remoteGenerationRequestTasks[requestID] = task
        if jobs[requestID]?.terminalEvent != nil {
            task.cancel()
            remoteGenerationRequestTasks[requestID] = nil
        }
    }

    func clearRemoteGenerationRequestTask(id: String) {
        remoteGenerationRequestTasks[id] = nil
    }

    func cancelRemoteGenerationUpstream(
        _ remoteSession: RemoteSpeechStreamSession?,
        requestID: String,
        service: RemoteGenerationService,
    ) async {
        guard let remoteSession else {
            return
        }

        do {
            try await remoteSession.cancelUpstream()
        } catch let error as SpeakSwiftly.Error {
            recordRecentError(
                source: "remote_generation",
                code: error.code.rawValue,
                message: error.message,
            )
        } catch {
            recordRecentError(
                source: "remote_generation",
                code: SpeakSwiftly.ErrorCode.internalError.rawValue,
                message: "SpeakSwiftlyServer could not propagate cancellation for remote generation request '\(requestID)' to '\(service.serviceName ?? service.baseURL)'. Likely cause: \(error.localizedDescription)",
            )
        }
    }

    func routeRemoteGeneratedAudio(
        chunks: SpeakSwiftly.GeneratedAudioChunkStream,
        requestID: String,
    ) async throws {
        if let selectedDestination = networkAudioReceiverSelectionSnapshot().selectedDestination {
            try await sendRemoteGeneratedAudio(
                chunks: chunks,
                requestID: requestID,
                destination: selectedDestination,
            )
        } else {
            try await remoteGeneratedAudioPlaybackSink(chunks)
        }
    }

    func sendRemoteGeneratedAudio(
        chunks: SpeakSwiftly.GeneratedAudioChunkStream,
        requestID: String,
        destination: NetworkAudioDestinationSnapshot,
    ) async throws {
        guard let endpoint = destination.endpoint.endpoint else {
            throw SpeakSwiftly.Error(
                code: .invalidRequest,
                message: "SpeakSwiftlyServer cannot send remote generation request '\(requestID)' to selected LAN audio receiver '\(destination.id)' because its discovered endpoint is incomplete.",
            )
        }
        guard let sharedToken = networkAudioReceiverConfig.sharedToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sharedToken.isEmpty else {
            throw SpeakSwiftly.Error(
                code: .invalidRequest,
                message: "SpeakSwiftlyServer cannot send remote generation request '\(requestID)' to selected LAN audio receiver '\(destination.name)' because networkAudioReceiver.sharedToken is empty in this server's configuration.",
            )
        }

        let sender = SpeakSwiftly.NetworkAudioStreamSender(
            endpoint: endpoint,
            handshake: .init(
                requestID: requestID,
                senderName: configuration.name,
                sharedToken: sharedToken,
            ),
        )
        try await sender.send(chunks: chunks)
    }

    func queueSpeechFile(
        text: String,
        profileName: String,
        textProfileID: String? = nil,
        requestContext: SpeakSwiftly.RequestContext? = nil,
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.queueSpeechFile(
            text: text,
            with: profileName,
            textProfileID: textProfileID,
            requestContext: requestContext,
        )
        return await enqueuePublicJob(handle)
    }

    func queueSpeechBatch(
        items: [SpeakSwiftly.BatchItem],
        profileName: String,
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.queueSpeechBatch(items, with: profileName)
        return await enqueuePublicJob(handle)
    }

    func createVoiceProfileFromDescription(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?,
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.createVoiceProfileFromDescription(
            profileName: profileName,
            vibe: vibe,
            from: text,
            voice: voiceDescription,
            outputPath: outputPath,
            cwd: cwd,
        )
        return await enqueuePublicJob(handle, profileMutation: .create(profileName: profileName))
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        referenceAudioPath: String,
        transcript: String?,
        cwd: String?,
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.createVoiceProfileFromAudio(
            profileName: profileName,
            vibe: vibe,
            from: referenceAudioPath,
            transcript: transcript,
            cwd: cwd,
        )
        return await enqueuePublicJob(handle, profileMutation: .create(profileName: profileName))
    }

    func submitRenameVoiceProfile(
        profileName: String,
        to newProfileName: String,
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.renameVoiceProfile(profileName: profileName, to: newProfileName)
        return await enqueuePublicJob(handle, profileMutation: .rename(from: profileName, to: newProfileName))
    }

    func submitRerollVoiceProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.rerollVoiceProfile(profileName: profileName)
        return await enqueuePublicJob(handle, profileMutation: .reroll(profileName: profileName))
    }

    func submitDeleteVoiceProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.deleteVoiceProfile(profileName: profileName)
        return await enqueuePublicJob(handle, profileMutation: .delete(profileName: profileName))
    }

    func submitSpeechBackendSwitch(to speechBackend: SpeakSwiftly.SpeechBackend) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.switchSpeechBackend(to: speechBackend)
        return await enqueuePublicJob(
            handle,
            runtimeBackendSwitch: .init(requestedSpeechBackend: speechBackend),
        )
    }

    func ensureWorkerReady() throws {
        guard workerMode == "ready" else {
            throw ServerRequestError(
                .serviceUnavailable,
                message: startupError ?? "SpeakSwiftly is not ready yet, so the server cannot accept new work right now.",
            )
        }
    }

    func enqueuePublicJob(
        _ handle: RuntimeRequestHandle,
        profileMutation: ProfileMutationExpectation? = nil,
        runtimeBackendSwitch: RuntimeBackendSwitchExpectation? = nil,
    ) async -> String {
        jobs[handle.id] = JobRecord(
            jobID: handle.id,
            op: handle.operation,
            profileName: handle.profileName,
            profileMutation: profileMutation,
            runtimeBackendSwitch: runtimeBackendSwitch,
            submittedAt: Date(),
        )

        requestMonitorTasks[handle.id] = Task {
            await self.consume(handle: handle)
            self.clearRequestMonitorTask(id: handle.id)
        }
        await requestPublish(mode: .coalesced, refreshRuntimeState: true)
        return handle.id
    }

    func clearRequestMonitorTask(id: String) {
        requestMonitorTasks[id] = nil
    }
}
