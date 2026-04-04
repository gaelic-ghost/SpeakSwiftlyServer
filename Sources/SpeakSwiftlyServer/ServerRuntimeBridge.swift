import Foundation
import SpeakSwiftlyCore

// MARK: - Runtime Bridge

struct RuntimeRequestHandle: Sendable {
    let id: String
    let operationName: String
    let profileName: String?
    let events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>

    init(
        id: String,
        operationName: String,
        profileName: String?,
        events: AsyncThrowingStream<WorkerRequestStreamEvent, Error>
    ) {
        self.id = id
        self.operationName = operationName
        self.profileName = profileName
        self.events = events
    }

    init(_ handle: WorkerRequestHandle) {
        self.id = handle.id
        self.operationName = handle.operationName
        self.profileName = handle.profileName
        self.events = handle.events
    }
}

protocol ServerRuntimeProtocol: Actor {
    func start()
    func shutdown() async
    func statusEvents() -> AsyncStream<WorkerStatusEvent>
    func queueSpeechHandle(text: String, profileName: String, as jobType: SpeechJobType, id: String) async -> RuntimeRequestHandle
    func createProfileHandle(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        id: String
    ) async -> RuntimeRequestHandle
    func listProfilesHandle(id: String) async -> RuntimeRequestHandle
    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle
    func listQueueHandle(_ queueType: WorkerQueueType, id requestID: String) async -> RuntimeRequestHandle
    func playbackHandle(_ action: PlaybackAction, id requestID: String) async -> RuntimeRequestHandle
    func clearQueueHandle(id requestID: String) async -> RuntimeRequestHandle
    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle
}

extension WorkerRuntime: ServerRuntimeProtocol {
    func queueSpeechHandle(text: String, profileName: String, as jobType: SpeechJobType, id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.queueSpeechHandle(text: text, profileName: profileName, as: jobType, id: id))
    }

    func createProfileHandle(
        profileName: String,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        id: String
    ) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(
            await self.createProfileHandle(
                profileName: profileName,
                text: text,
                voiceDescription: voiceDescription,
                outputPath: outputPath,
                id: id
            )
        )
    }

    func listProfilesHandle(id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.listProfilesHandle(id: id))
    }

    func removeProfileHandle(profileName: String, id: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.removeProfileHandle(profileName: profileName, id: id))
    }

    func listQueueHandle(_ queueType: WorkerQueueType, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.listQueueHandle(queueType, id: requestID))
    }

    func playbackHandle(_ action: PlaybackAction, id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.playbackHandle(action, id: requestID))
    }

    func clearQueueHandle(id requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.clearQueueHandle(id: requestID))
    }

    func cancelRequestHandle(with id: String, requestID: String) async -> RuntimeRequestHandle {
        RuntimeRequestHandle(await self.cancelRequestHandle(with: id, requestID: requestID))
    }
}
