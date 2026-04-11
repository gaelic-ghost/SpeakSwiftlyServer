import Foundation
import SpeakSwiftlyCore
import NIOCore
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - Host Wait Helpers

@available(macOS 14, *)
func waitUntilReady(_ host: ServerHost) async throws {
    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let (ready, _) = await host.readinessSnapshot()
        return ready ? true : nil
    }
}

@available(macOS 14, *)
func waitForJobSnapshot(_ jobID: String, on host: ServerHost) async throws -> JobSnapshot {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            let snapshot = try await host.jobSnapshot(id: jobID)
            return snapshot.terminalEvent == nil ? nil : snapshot
        } catch {
            return nil
        }
    }
}

@available(macOS 14, *)
func waitUntilJobDisappears(_ jobID: String, on host: ServerHost) async throws {
    let _: Bool = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            _ = try await host.jobSnapshot(id: jobID)
            return nil
        } catch {
            return true
        }
    }
}

func waitUntil<T: Sendable>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping @Sendable () async throws -> T?
) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(for: pollInterval)
    }
    throw TimeoutError()
}

@available(macOS 14, *)
func waitForActiveRequestID(on host: ServerHost) async throws -> String {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = await host.generationQueueSnapshot()
        return snapshot.activeRequest?.id
    }
}

struct TimeoutError: Error {}

// MARK: - Host Submission Helpers

extension ServerHost {
    func submitSpeak(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try await queueSpeechLive(
            text: text,
            profileName: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
    }

    func submitCreateProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async throws -> String {
        try await createVoiceProfileFromDescription(
            profileName: profileName,
            vibe: vibe,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            cwd: cwd
        )
    }

    func submitCreateClone(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async throws -> String {
        try await createVoiceProfileFromAudio(
            profileName: profileName,
            vibe: vibe,
            referenceAudioPath: referenceAudioPath,
            transcript: transcript,
            cwd: cwd
        )
    }

    func submitRemoveProfile(profileName: String) async throws -> String {
        try await submitDeleteVoiceProfile(profileName: profileName)
    }

    func submitRenameProfile(profileName: String, newProfileName: String) async throws -> String {
        try await submitRenameVoiceProfile(profileName: profileName, to: newProfileName)
    }

    func submitRerollProfile(profileName: String) async throws -> String {
        try await submitRerollVoiceProfile(profileName: profileName)
    }
}

extension JobSnapshot {
    var jobID: String { requestID }
}

// MARK: - Binary Payload Helpers

func byteBuffer(_ string: String) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
    buffer.writeString(string)
    return buffer
}

func string(from buffer: ByteBuffer) -> String {
    String(decoding: buffer.readableBytesView, as: UTF8.self)
}

func jsonObject(from buffer: ByteBuffer) throws -> [String: Any] {
    let data = Data(buffer.readableBytesView)
    return try jsonObject(from: data)
}

func jsonObject(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = json as? [String: Any] else {
        throw JSONError.notDictionary
    }
    return dictionary
}
