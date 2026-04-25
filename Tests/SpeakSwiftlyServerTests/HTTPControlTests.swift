import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - HTTP Control Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `routes expose queue inspection and control operations`() async throws {
        let runtime = MockRuntime(speakBehavior: .holdOpen)
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeConfigurationStore: testRuntimeConfigurationStore(),
            state: state,
        )

        await host.start()
        await runtime.publishStatus(.residentModelReady)
        try await waitUntilReady(host)

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let activeResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Hold the line","profile_name":"default"}"#),
            )
            let activeJobID = try #require(try jsonObject(from: activeResponse.body)["request_id"] as? String)

            let queuedResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Queue this request","profile_name":"default"}"#),
            )
            let queuedJobID = try #require(try jsonObject(from: queuedResponse.body)["request_id"] as? String)

            let queueResponse = try await client.execute(uri: "/generation/queue", method: .get)
            let queueJSON = try jsonObject(from: queueResponse.body)
            #expect(queueResponse.status == .ok)
            #expect(queueJSON["queue_type"] as? String == "generation")
            let activeRequest = try #require(queueJSON["active_request"] as? [String: Any])
            #expect(activeRequest["id"] as? String == activeJobID)
            let activeRequests = try #require(queueJSON["active_requests"] as? [[String: Any]])
            #expect(activeRequests.count == 1)
            #expect(activeRequests.first?["id"] as? String == activeJobID)
            let queuedRequests = try #require(queueJSON["queue"] as? [[String: Any]])
            #expect(queuedRequests.count == 1)
            #expect(queuedRequests.first?["id"] as? String == queuedJobID)
            #expect(queuedRequests.first?["queue_position"] as? Int == 1)

            let playbackStateResponse = try await client.execute(uri: "/playback/state", method: .get)
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

            let playbackQueueResponse = try await client.execute(uri: "/playback/queue", method: .get)
            let playbackQueueJSON = try jsonObject(from: playbackQueueResponse.body)
            #expect(playbackQueueResponse.status == .ok)
            #expect(playbackQueueJSON["queue_type"] as? String == "playback")
            #expect((playbackQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
            #expect((playbackQueueJSON["active_requests"] as? [[String: Any]])?.first?["id"] as? String == activeJobID)
            #expect((playbackQueueJSON["queue"] as? [[String: Any]])?.isEmpty == true)

            let cancelResponse = try await client.execute(uri: "/playback/requests/\(queuedJobID)", method: .delete)
            let cancelJSON = try jsonObject(from: cancelResponse.body)
            #expect(cancelResponse.status == .ok)
            #expect(cancelJSON["cancelled_request_id"] as? String == queuedJobID)

            let cancelledSnapshot = try await waitForJobSnapshot(queuedJobID, on: host)
            switch cancelledSnapshot.terminalEvent {
                case let .failed(failure):
                    #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
                default:
                    Issue.record("Expected the cancelled queued request to terminate with a request_cancelled failure.")
            }

            let anotherQueuedResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Queue another request","profile_name":"default"}"#),
            )
            let anotherQueuedJobID = try #require(try jsonObject(from: anotherQueuedResponse.body)["request_id"] as? String)

            let clearResponse = try await client.execute(uri: "/playback/queue", method: .delete)
            let clearJSON = try jsonObject(from: clearResponse.body)
            #expect(clearResponse.status == .ok)
            #expect(clearJSON["cleared_count"] as? Int == 1)

            let clearedSnapshot = try await waitForJobSnapshot(anotherQueuedJobID, on: host)
            switch clearedSnapshot.terminalEvent {
                case let .failed(failure):
                    #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
                default:
                    Issue.record("Expected the cleared queued request to terminate with a request_cancelled failure.")
            }

            let emptyQueueResponse = try await client.execute(uri: "/generation/queue", method: .get)
            let emptyQueueJSON = try jsonObject(from: emptyQueueResponse.body)
            let remainingQueue = try #require(emptyQueueJSON["queue"] as? [[String: Any]])
            #expect(remainingQueue.isEmpty)
            #expect((emptyQueueJSON["active_request"] as? [String: Any])?["id"] as? String == activeJobID)
            #expect((emptyQueueJSON["active_requests"] as? [[String: Any]])?.first?["id"] as? String == activeJobID)
        }

        try await runtime.finishHeldSpeak(id: waitForActiveRequestID(on: host))
        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `routes report not ready and missing jobs clearly`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeConfigurationStore: testRuntimeConfigurationStore(),
            state: state,
        )

        await host.start()

        let app = assembleHBApp(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let readyResponse = try await client.execute(uri: "/readyz", method: .get)
            let readyJSON = try jsonObject(from: readyResponse.body)
            #expect(readyResponse.status == .serviceUnavailable)
            #expect(readyJSON["status"] as? String == "not_ready")

            let speakResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Too soon","profile_name":"default"}"#),
            )
            let speakJSON = try jsonObject(from: speakResponse.body)
            #expect(speakResponse.status == .serviceUnavailable)
            let speakError = try #require(speakJSON["error"] as? [String: Any])
            #expect((speakError["message"] as? String)?.contains("cannot accept new work") == true)

            let missingJob = try await client.execute(uri: "/requests/missing-job", method: .get)
            let missingJSON = try jsonObject(from: missingJob.body)
            #expect(missingJob.status == .notFound)
            let missingJobError = try #require(missingJSON["error"] as? [String: Any])
            #expect((missingJobError["message"] as? String)?.contains("expired from in-memory retention") == true)

            let missingEvents = try await client.execute(uri: "/requests/missing-job/events", method: .get)
            let missingEventsJSON = try jsonObject(from: missingEvents.body)
            #expect(missingEvents.status == .notFound)
            let missingEventsError = try #require(missingEventsJSON["error"] as? [String: Any])
            #expect((missingEventsError["message"] as? String)?.contains("expired from in-memory retention") == true)
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `routes report worker startup failure clearly`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeConfigurationStore: testRuntimeConfigurationStore(),
            state: state,
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

            let statusResponse = try await client.execute(uri: "/runtime/host", method: .get)
            let statusJSON = try jsonObject(from: statusResponse.body)
            #expect(statusResponse.status == .ok)
            #expect(statusJSON["worker_mode"] as? String == "failed")
            #expect(statusJSON["worker_stage"] as? String == "resident_model_failed")
            #expect((statusJSON["worker_failure_summary"] as? String)?.contains("startup failure") == true)

            let speakResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Still broken","profile_name":"default"}"#),
            )
            let speakJSON = try jsonObject(from: speakResponse.body)
            #expect(speakResponse.status == .serviceUnavailable)
            let speakError = try #require(speakJSON["error"] as? [String: Any])
            #expect((speakError["message"] as? String)?.contains("startup failure") == true)
        }

        await host.shutdown()
    }
}
