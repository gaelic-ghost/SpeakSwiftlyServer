import Foundation
import Hummingbird
import SpeakSwiftly
import TextForSpeech

// MARK: - Job Submission

extension ServerHost {
    func queueSpeechLive(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.queueSpeechLive(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return await enqueuePublicJob(handle)
    }

    func queueSpeechFile(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.queueSpeechFile(
            text: text,
            with: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
        return await enqueuePublicJob(handle)
    }

    func queueSpeechBatch(
        items: [SpeakSwiftly.BatchItem],
        profileName: String
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
        cwd: String?
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.createVoiceProfileFromDescription(
            profileName: profileName,
            vibe: vibe,
            from: text,
            voice: voiceDescription,
            outputPath: outputPath,
            cwd: cwd
        )
        return await enqueuePublicJob(handle)
    }

    func createVoiceProfileFromAudio(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.createVoiceProfileFromAudio(
            profileName: profileName,
            vibe: vibe,
            from: referenceAudioPath,
            transcript: transcript,
            cwd: cwd
        )
        return await enqueuePublicJob(handle)
    }

    func submitRenameVoiceProfile(
        profileName: String,
        to newProfileName: String
    ) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.renameVoiceProfile(profileName: profileName, to: newProfileName)
        return await enqueuePublicJob(handle)
    }

    func submitRerollVoiceProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.rerollVoiceProfile(profileName: profileName)
        return await enqueuePublicJob(handle)
    }

    func submitDeleteVoiceProfile(profileName: String) async throws -> String {
        try ensureWorkerReady()
        let handle = await runtime.deleteVoiceProfile(profileName: profileName)
        return await enqueuePublicJob(handle)
    }

    func ensureWorkerReady() throws {
        guard workerMode == "ready" else {
            throw HTTPError(
                .serviceUnavailable,
                message: startupError ?? "SpeakSwiftly is not ready yet, so the server cannot accept new work right now."
            )
        }
    }

    func enqueuePublicJob(_ handle: RuntimeRequestHandle) async -> String {
        jobs[handle.id] = JobRecord(
            jobID: handle.id,
            op: handle.operation,
            profileName: handle.profileName,
            submittedAt: Date()
        )

        Task {
            await self.consume(handle: handle)
        }
        await requestPublish(mode: .coalesced, refreshRuntimeState: true)
        return handle.id
    }
}
