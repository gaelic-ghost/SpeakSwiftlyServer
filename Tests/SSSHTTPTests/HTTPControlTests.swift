import Foundation
import HTTPTypes
import Hummingbird
import HummingbirdTesting
import SpeakSwiftly
import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
import SSSHTTP
import SSSMCP
import Testing

// MARK: - HTTP Control Tests

extension ServerTests {
    @Test func `configured HTTP authorities bracket IPv6 literal fallbacks`() {
        let ipv4Config = HTTPConfig(enabled: true, host: "127.0.0.1", port: 7337, sseHeartbeatSeconds: 0.05)
        #expect(configuredAuthority(ipv4Config) == "127.0.0.1:7337")

        let ipv6Config = HTTPConfig(enabled: true, host: "::1", port: 7337, sseHeartbeatSeconds: 0.05)
        #expect(configuredAuthority(ipv6Config) == "[::1]:7337")

        let bracketedIPv6Config = HTTPConfig(enabled: true, host: "[::1]", port: 7337, sseHeartbeatSeconds: 0.05)
        #expect(configuredAuthority(bracketedIPv6Config) == "[::1]:7337")
    }

    @available(macOS 14, *)
    @Test func `build HTTP application maps typed config into Hummingbird application configuration`() async {
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: MockRuntime(),
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )
        let httpConfig = HTTPConfig(
            enabled: true,
            host: "::1",
            port: 8088,
            sseHeartbeatSeconds: 0.05,
        )

        let app = buildHTTPApplication(
            configuration: httpConfig,
            host: host,
            serverName: "speak-swiftly-test",
        )

        #expect(app.configuration.address == .hostname("::1", port: 8088))
        #expect(app.configuration.serverName == "speak-swiftly-test")
    }

    @available(macOS 14, *)
    @Test func `build HTTP application support marks mounted transport routes as listening`() async {
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            httpConfig: testHTTPConfig(configuration),
            mcpConfig: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-mcp",
                title: "Speak Swiftly",
            ),
            runtime: MockRuntime(),
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )
        await host.markTransportStarting(name: "http")
        await host.markTransportStarting(name: "mcp")

        await markConfiguredTransportsListening(
            configuration: testHTTPConfig(configuration),
            host: host,
            additionalListeningTransports: ["mcp"],
        )

        let snapshot = await host.hostStateSnapshot()
        #expect(snapshot.transports.contains { $0.name == "http" && $0.state == "listening" })
        #expect(snapshot.transports.contains { $0.name == "mcp" && $0.state == "listening" })
    }

    @available(macOS 14, *)
    @Test func `routes expose queue inspection and control operations`() async throws {
        let runtime = MockRuntime(speakBehavior: .holdOpen)
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )

        await host.start()
        await runtime.publishStatus(.residentModelReady)
        try await waitUntilReady(host)

        let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
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

            let cancelResponse = try await client.execute(uri: "/requests/\(queuedJobID)", method: .delete)
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

            let scopedQueuedResponse = try await client.execute(
                uri: "/speech/live",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"text":"Queue scoped cancellation","profile_name":"default"}"#),
            )
            let scopedQueuedJobID = try #require(try jsonObject(from: scopedQueuedResponse.body)["request_id"] as? String)

            let scopedCancelResponse = try await client.execute(
                uri: "/requests/\(scopedQueuedJobID)?scope=generation",
                method: .delete,
            )
            let scopedCancelJSON = try jsonObject(from: scopedCancelResponse.body)
            #expect(scopedCancelResponse.status == .ok)
            #expect(scopedCancelJSON["cancelled_request_id"] as? String == scopedQueuedJobID)

            let scopedCancelledSnapshot = try await waitForJobSnapshot(scopedQueuedJobID, on: host)
            switch scopedCancelledSnapshot.terminalEvent {
                case let .failed(failure):
                    #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
                default:
                    Issue.record("Expected the scoped cancelled queued request to terminate with a request_cancelled failure.")
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
            #expect(clearJSON["cleared_count"] as? Int == 0)

            let stillQueuedResponse = try await client.execute(uri: "/generation/queue", method: .get)
            let stillQueuedJSON = try jsonObject(from: stillQueuedResponse.body)
            let stillQueued = try #require(stillQueuedJSON["queue"] as? [[String: Any]])
            #expect(stillQueued.count == 1)
            #expect(stillQueued.first?["id"] as? String == anotherQueuedJobID)

            let clearGenerationResponse = try await client.execute(uri: "/generation/queue", method: .delete)
            let clearGenerationJSON = try jsonObject(from: clearGenerationResponse.body)
            #expect(clearGenerationResponse.status == .ok)
            #expect(clearGenerationJSON["cleared_count"] as? Int == 1)

            let clearedSnapshot = try await waitForJobSnapshot(anotherQueuedJobID, on: host)
            switch clearedSnapshot.terminalEvent {
                case let .failed(failure):
                    #expect(failure.code == SpeakSwiftly.ErrorCode.requestCancelled.rawValue)
                default:
                    Issue.record("Expected the cleared queued request to terminate with a request_cancelled failure.")
            }

            let _: Bool = try await waitUntil(
                timeout: .seconds(1),
                pollInterval: .milliseconds(10),
            ) {
                let emptyQueueResponse = try await client.execute(uri: "/generation/queue", method: .get)
                let emptyQueueJSON = try jsonObject(from: emptyQueueResponse.body)
                let remainingQueue = try #require(emptyQueueJSON["queue"] as? [[String: Any]])
                return remainingQueue.isEmpty ? true : nil
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
    @Test func `routes expose recent generated audio replay controls`() async throws {
        let runtime = MockRuntime()
        let recentItem = SpeakSwiftly.RecentGeneratedAudioItem(
            id: "recent-1",
            requestID: "source-request-1",
            textPreview: "Replay this.",
            voiceProfileName: "default",
            createdAt: Date(timeIntervalSince1970: 1),
            completedAt: Date(timeIntervalSince1970: 2),
            sampleRate: 24000,
            channelCount: 1,
            durationSeconds: 0.25,
            artifactID: nil,
            artifactURL: nil,
            retentionPolicy: .recentCache,
            bufferState: .complete,
            bufferedChunkCount: 1,
            failureMessage: nil,
        )
        await runtime.replaceRecentGeneratedAudioSnapshot(.init(items: [recentItem], limit: 5, memorySecondsPerItem: 30))
        await runtime.replaceRecentGeneratedAudioChunks([
            "recent-1": [
                .init(
                    requestID: "source-request-1",
                    sequenceNumber: 0,
                    sampleRate: 24000,
                    channelCount: 1,
                    samples: [0.1, 0.2],
                ),
            ],
        ])
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )

        await host.start()
        await runtime.publishStatus(.residentModelReady)
        try await waitUntilReady(host)

        let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let listResponse = try await client.execute(uri: "/playback/recent-generated-audio", method: .get)
            let listJSON = try jsonObject(from: listResponse.body)
            #expect(listResponse.status == .ok)
            let recent = try #require(listJSON["recent_generated_audio"] as? [String: Any])
            let items = try #require(recent["items"] as? [[String: Any]])
            #expect(items.first?["id"] as? String == "recent-1")

            let chunksResponse = try await client.execute(uri: "/playback/recent-generated-audio/recent-1/chunks", method: .get)
            let chunksJSON = try jsonObject(from: chunksResponse.body)
            #expect(chunksResponse.status == .ok)
            #expect(chunksJSON["recent_audio_id"] as? String == "recent-1")
            let chunks = try #require(chunksJSON["chunks"] as? [[String: Any]])
            #expect(chunks.first?["sequenceNumber"] as? Int == 0)

            let replayResponse = try await client.execute(
                uri: "/playback/recent-generated-audio/recent-1/replay",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"replay_mode":"enqueue_after_current","request_context":{"source":"http","topic":"recent-route","prefacePolicy":"never"},"cwd":"./recent-cwd","repo_root":"."}"#),
            )
            let replayJSON = try jsonObject(from: replayResponse.body)
            #expect(replayResponse.status == .ok)
            let replayRequestID = try #require(replayJSON["request_id"] as? String)
            #expect(replayRequestID.isEmpty == false)
            let replayInvocation = try #require(await runtime.replayRecentAudioInvocations.last)
            #expect(replayInvocation.id == "recent-1")
            #expect(replayInvocation.mode == .enqueueAfterCurrent)
            #expect(
                replayInvocation.requestContext
                    == SpeakSwiftly.RequestContext(
                        reqPurpose: .speech,
                        source: "http",
                        topic: "recent-route",
                        cwd: "./recent-cwd",
                        repoRoot: ".",
                        attributes: [
                            "http.method": "POST",
                            "http.route": "/playback/recent-generated-audio/{recent_audio_id}/replay",
                            "server.app": "SpeakSwiftlyServer",
                            "surface": "http",
                        ],
                        prefacePolicy: .never,
                    ),
            )

            let replayAllResponse = try await client.execute(
                uri: "/playback/recent-generated-audio/replay-all",
                method: .post,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"replay_mode":"enqueue_next"}"#),
            )
            let replayAllJSON = try jsonObject(from: replayAllResponse.body)
            #expect(replayAllResponse.status == .ok)
            #expect((replayAllJSON["request_ids"] as? [String])?.count == 1)
            #expect(await (runtime.replayRecentAudioAllInvocations.last)?.mode == .enqueueNext)

            let defaultReplayResponse = try await client.execute(
                uri: "/playback/recent-generated-audio/recent-1/replay",
                method: .post,
            )
            let defaultReplayJSON = try jsonObject(from: defaultReplayResponse.body)
            #expect(defaultReplayResponse.status == .ok)
            #expect((defaultReplayJSON["request_id"] as? String)?.isEmpty == false)
            #expect(await (runtime.replayRecentAudioInvocations.last)?.mode == .enqueueNext)

            let defaultReplayAllResponse = try await client.execute(
                uri: "/playback/recent-generated-audio/replay-all",
                method: .post,
            )
            let defaultReplayAllJSON = try jsonObject(from: defaultReplayAllResponse.body)
            #expect(defaultReplayAllResponse.status == .ok)
            #expect((defaultReplayAllJSON["request_ids"] as? [String])?.count == 1)
            #expect(await (runtime.replayRecentAudioAllInvocations.last)?.mode == .enqueueNext)

            let clearResponse = try await client.execute(uri: "/playback/recent-generated-audio", method: .delete)
            let clearJSON = try jsonObject(from: clearResponse.body)
            #expect(clearResponse.status == .ok)
            let clearedRecent = try #require(clearJSON["recent_generated_audio"] as? [String: Any])
            #expect((clearedRecent["items"] as? [[String: Any]])?.isEmpty == true)
            #expect(await runtime.clearRecentGeneratedAudioCallCount == 1)
        }

        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `routes expose LAN audio receiver discovery and selection`() async throws {
        let configuration = testConfiguration()
        let host = await ServerHost(
            configuration: configuration,
            runtime: MockRuntime(),
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: MainActor.run { EmbeddedServer() },
        )
        let destination = SpeakSwiftly.NetworkAudioDestination(
            id: "Gale MacBook Receiver._spswift-audio._tcp.local.",
            name: "Gale MacBook Receiver",
            endpoint: .bonjourService(
                name: "Gale MacBook Receiver",
                type: SpeakSwiftly.NetworkAudioBonjour.serviceType,
                domain: SpeakSwiftly.NetworkAudioBonjour.domain,
            ),
            capabilities: .init(),
            lastSeen: Date(timeIntervalSince1970: 1_796_180_400),
        )
        await host.replaceNetworkAudioDestinations([destination])

        let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let destinationsResponse = try await client.execute(uri: "/network-audio/destinations", method: .get)
            let destinationsJSON = try jsonArray(from: destinationsResponse.body)
            #expect(destinationsResponse.status == .ok)
            #expect(destinationsJSON.first?["id"] as? String == destination.id)
            #expect(destinationsJSON.first?["name"] as? String == "Gale MacBook Receiver")

            let selectResponse = try await client.execute(
                uri: "/network-audio/selection",
                method: .put,
                headers: [.contentType: "application/json"],
                body: byteBuffer(#"{"destination_id":"Gale MacBook Receiver._spswift-audio._tcp.local."}"#),
            )
            let selectJSON = try jsonObject(from: selectResponse.body)
            #expect(selectResponse.status == .ok)
            let selection = try #require(selectJSON["selection"] as? [String: Any])
            #expect(selection["selected_destination_id"] as? String == destination.id)
            #expect(selection["shared_token_configured"] as? Bool == false)
            #expect(selection["selected_destination_endpoint_ready"] as? Bool == true)
            #expect(selection["lan_output_ready"] as? Bool == false)
            #expect(selection["lan_output_blocked_reasons"] as? [String] == ["network_audio_receiver_shared_token_missing"])

            let selectionResponse = try await client.execute(uri: "/network-audio/selection", method: .get)
            let selectionJSON = try jsonObject(from: selectionResponse.body)
            #expect(selectionResponse.status == .ok)
            #expect(selectionJSON["selected_destination_id"] as? String == destination.id)
            #expect(selectionJSON["lan_output_ready"] as? Bool == false)

            let blockedSmokeResponse = try await client.execute(
                uri: "/network-audio/selection/smoke-test",
                method: .post,
            )
            #expect(blockedSmokeResponse.status == .badRequest)
            #expect(String(buffer: blockedSmokeResponse.body).contains("network_audio_receiver_shared_token_missing"))

            let clearResponse = try await client.execute(uri: "/network-audio/selection", method: .delete)
            let clearJSON = try jsonObject(from: clearResponse.body)
            #expect(clearResponse.status == .ok)
            let clearedSelection = try #require(clearJSON["selection"] as? [String: Any])
            #expect(clearedSelection["selected_destination_id"] as? String == nil)
            #expect(clearedSelection["lan_output_ready"] as? Bool == false)
            #expect(clearedSelection["lan_output_blocked_reasons"] as? [String] == [
                "no_lan_audio_receiver_selected",
                "network_audio_receiver_shared_token_missing",
            ])
        }
    }

    @Test func `route smoke-tests selected LAN audio receiver over loopback`() async throws {
        let listener = SpeakSwiftly.NetworkAudioStreamListener(
            advertisement: SpeakSwiftly.NetworkAudioServiceAdvertisement(name: "Loopback receiver"),
            port: 0,
            sharedToken: "receiver-token",
            connectionReadinessTimeout: .seconds(2),
        )
        let inboundStreams = await listener.inboundStreams()
        try await listener.start()
        do {
            let port = try await waitForNetworkAudioListeningPort(listener)
            let configuration = testConfiguration()
            let host = await ServerHost(
                configuration: configuration,
                networkAudioReceiverConfig: .init(
                    enabled: false,
                    serviceName: "Loopback receiver",
                    port: 0,
                    sharedToken: "receiver-token",
                ),
                runtime: MockRuntime(),
                runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
                state: MainActor.run { EmbeddedServer() },
            )

            let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
            try await app.test(.router) { client in
                let selectResponse = try await client.execute(
                    uri: "/network-audio/selection",
                    method: .put,
                    headers: [.contentType: "application/json"],
                    body: byteBuffer("""
                    {
                      "name": "Loopback receiver",
                      "endpoint": {
                        "kind": "host_port",
                        "host": "127.0.0.1",
                        "port": \(port)
                      }
                    }
                    """),
                )
                let selectJSON = try jsonObject(from: selectResponse.body)
                #expect(selectResponse.status == .ok)
                let selection = try #require(selectJSON["selection"] as? [String: Any])
                #expect(selection["selected_destination_id"] as? String == "manual-host-port:127.0.0.1:\(port)")
                #expect(selection["lan_output_ready"] as? Bool == true)

                async let smokeResponse = client.execute(
                    uri: "/network-audio/selection/smoke-test",
                    method: .post,
                )

                var iterator = inboundStreams.makeAsyncIterator()
                let inbound = try #require(await iterator.next())
                var receivedChunks = [SpeakSwiftly.GeneratedAudioChunk]()
                for try await chunk in inbound.chunks {
                    receivedChunks.append(chunk)
                    if chunk.isFinal {
                        break
                    }
                }

                let response = try await smokeResponse
                let responseJSON = try jsonObject(from: response.body)
                #expect(response.status == .ok)
                let requestID = try #require(responseJSON["request_id"] as? String)
                #expect(requestID.hasPrefix("network-audio-smoke-"))
                #expect(responseJSON["destination_id"] as? String == "manual-host-port:127.0.0.1:\(port)")
                #expect(responseJSON["destination_name"] as? String == "Loopback receiver")
                #expect(responseJSON["sample_rate"] as? Int == 24000)
                #expect(responseJSON["channel_count"] as? Int == 1)
                #expect(responseJSON["sent_chunk_count"] as? Int == 2)
                #expect(inbound.requestID == requestID)
                #expect(inbound.handshake.senderName == configuration.name)
                #expect(receivedChunks.map(\.requestID).allSatisfy { $0 == requestID })
                #expect(receivedChunks.map(\.sequenceNumber) == [0, 1])
                #expect(receivedChunks.last?.isFinal == true)
            }
        } catch {
            await listener.stop()
            throw error
        }
        await listener.stop()
    }

    @available(macOS 14, *)
    @Test func `routes report not ready and missing jobs clearly`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            runtime: runtime,
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )

        await host.start()

        let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
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

            let invalidScope = try await client.execute(uri: "/requests/some-job?scope=storage", method: .delete)
            let invalidScopeJSON = try jsonObject(from: invalidScope.body)
            #expect(invalidScope.status == .badRequest)
            let invalidScopeError = try #require(invalidScopeJSON["error"] as? [String: Any])
            #expect((invalidScopeError["message"] as? String)?.contains("Expected one of: generation, playback") == true)
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
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
        )

        await host.start()
        await runtime.publishStatus(.residentModelFailed)

        let app = buildHTTPApplication(configuration: testHTTPConfig(configuration), host: host)
        try await app.test(.router) { client in
            let readyResponse = try await client.execute(uri: "/readyz", method: .get)
            let readyJSON = try jsonObject(from: readyResponse.body)
            #expect(readyResponse.status == .serviceUnavailable)
            #expect(readyJSON["status"] as? String == "not_ready")
            #expect(readyJSON["worker_mode"] as? String == "failed")
            #expect((readyJSON["startup_error"] as? String)?.contains("startup failure") == true)

            let statusResponse = try await client.execute(uri: "/overview", method: .get)
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

private func waitForNetworkAudioListeningPort(_ listener: SpeakSwiftly.NetworkAudioStreamListener) async throws -> UInt16 {
    for _ in 0..<100 {
        if case let .listening(port?) = await listener.state {
            return port
        }
        try await Task.sleep(for: .milliseconds(10))
    }

    Issue.record("Network audio listener did not report a loopback port in time.")
    throw CancellationError()
}
