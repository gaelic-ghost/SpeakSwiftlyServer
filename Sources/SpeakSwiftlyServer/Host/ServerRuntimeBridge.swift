import Foundation
import SpeakSwiftlyCore

// MARK: - Runtime Bridge

struct RuntimeRequestHandle: Sendable {
    let id: String
    let operationName: String
    let profileName: String?
    let events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>

    // MARK: - Initialization

    init(
        id: String,
        operationName: String,
        profileName: String?,
        events: AsyncThrowingStream<SpeakSwiftly.RequestEvent, Error>
    ) {
        self.id = id
        self.operationName = operationName
        self.profileName = profileName
        self.events = events
    }

    init(_ handle: SpeakSwiftly.RequestHandle) {
        self.id = handle.id
        self.operationName = handle.operation
        self.profileName = handle.profileName
        self.events = handle.events
    }
}

// MARK: - Runtime Protocol

protocol ServerRuntimeProtocol: Actor {
    func start()
    func shutdown() async
    func statusEvents() -> AsyncStream<SpeakSwiftly.StatusEvent>
    func queueSpeechHandle(text: String, profileName: String, as jobType: SpeakSwiftly.Job, id: String) async -> RuntimeRequestHandle
    func createProfileHandle(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        id: String
    ) async -> RuntimeRequestHandle
    func listProfilesHandle(id: String) async -> RuntimeRequestHandle
    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle
    func listQueueHandle(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle
    func playbackHandle(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle
    func clearQueueHandle(id requestID: String) async -> RuntimeRequestHandle
    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle
}

// MARK: - Runtime Adapter

extension SpeakSwiftly.Runtime: ServerRuntimeProtocol {
    func queueSpeechHandle(text: String, profileName: String, as jobType: SpeakSwiftly.Job, id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await speak(text: text, with: profileName, as: jobType, id: id))
    }

    func createProfileHandle(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(
            await createProfile(
                named: profileName,
                from: text,
                voice: voiceDescription,
                outputPath: outputPath,
                id: id
            )
        )
    }

    func listProfilesHandle(id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await profiles(id: id))
    }

    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await removeProfile(named: profileName, id: id))
    }

    func listQueueHandle(_ queueType: SpeakSwiftly.Queue, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await queue(queueType, id: requestID))
    }

    func playbackHandle(_ action: SpeakSwiftly.PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await playback(action, id: requestID))
    }

    func clearQueueHandle(id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await clearQueue(id: requestID))
    }

    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await cancelRequest(id, requestID: requestID))
    }
}
