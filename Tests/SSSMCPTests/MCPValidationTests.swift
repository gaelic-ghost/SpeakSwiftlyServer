import Foundation
import MCP
import SpeakSwiftly
import SpeakSwiftlyServer
import SpeakSwiftlyServerTestSupport
@testable import SSSCore
import SSSHTTP
import SSSMCP
import Testing

// MARK: - MCP Validation Tests

extension ServerTests {
    @available(macOS 14, *)
    @Test func `embedded MCP uses configured default voice profile when profile name is omitted`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration(defaultVoiceProfileName: "default")
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            httpConfig: testHTTPConfig(configuration),
            mcpConfig: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP",
            ),
            runtime: runtime,
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
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
                    title: "SpeakSwiftly Test MCP",
                ),
                host: host,
            ),
        )

        try await mcpSurface.start()
        await host.markTransportListening(name: "mcp")
        let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
        try await drainMCPResponse(initializeMCPResponse)

        let initializedNotificationResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: initializeSessionID,
            ),
        )
        #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

        let successEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpCallToolRequestJSON(
                        name: "generate_speech",
                        arguments: [
                            "text": "Use the configured default profile",
                        ],
                    ),
                    sessionID: initializeSessionID,
                ),
            ),
        )
        let result = try #require(successEnvelope["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let firstContent = try #require(content.first)
        #expect((firstContent["text"] as? String)?.contains("accepted the live speech request") == true)

        let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
        #expect(queuedSpeechInvocation.profileName == "default")

        await mcpSurface.stop()
        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `embedded MCP uses runtime default voice when profile name is omitted`() async throws {
        let runtime = MockRuntime()
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            httpConfig: testHTTPConfig(configuration),
            mcpConfig: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP",
            ),
            runtime: runtime,
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
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
                    title: "SpeakSwiftly Test MCP",
                ),
                host: host,
            ),
        )

        try await mcpSurface.start()
        await host.markTransportListening(name: "mcp")
        let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
        try await drainMCPResponse(initializeMCPResponse)

        let initializedNotificationResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: initializeSessionID,
            ),
        )
        #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

        let successEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpCallToolRequestJSON(
                        name: "generate_speech",
                        arguments: [
                            "text": "No profile and no default",
                        ],
                    ),
                    sessionID: initializeSessionID,
                ),
            ),
        )
        let result = try #require(successEnvelope["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let firstContent = try #require(content.first)
        #expect((firstContent["text"] as? String)?.contains("accepted the live speech request") == true)
        let queuedSpeechInvocation = try #require(await runtime.latestQueuedSpeechInvocation())
        #expect(queuedSpeechInvocation.profileName == "default")

        await mcpSurface.stop()
        await host.shutdown()
    }

    @available(macOS 14, *)
    @Test func `embedded MCP sends remote generation chunks to local playback sink`() async throws {
        let runtime = MockRuntime()
        let collector = GeneratedAudioChunkCollector()
        let remoteChunks = [
            SpeakSwiftly.GeneratedAudioChunk(
                requestID: "mcp-remote-generation-1",
                sequenceNumber: 0,
                sampleRate: 24000,
                channelCount: 1,
                samples: [0.3, 0.4],
            ),
            SpeakSwiftly.GeneratedAudioChunk(
                requestID: "mcp-remote-generation-1",
                sequenceNumber: 1,
                sampleRate: 24000,
                channelCount: 1,
                samples: [],
                isFinal: true,
            ),
        ]
        let configuration = testConfiguration()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: configuration,
            httpConfig: testHTTPConfig(configuration),
            mcpConfig: .init(
                enabled: true,
                path: "/mcp",
                serverName: "speak-swiftly-test-mcp",
                title: "SpeakSwiftly Test MCP",
            ),
            runtime: runtime,
            remoteGenerationConfig: .init(
                allowRemoteStreamRequests: false,
                sharedToken: "remote-token",
            ),
            remoteGeneratedAudioStreamProvider: { request, service, sharedToken in
                #expect(request.text == "Remote generation probe")
                #expect(request.profileName == "default")
                #expect(service.serviceName == "GMM4")
                #expect(sharedToken == "remote-token")
                return RemoteSpeechStreamSession(
                    chunks: AsyncThrowingStream { continuation in
                        for chunk in remoteChunks {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    },
                )
            },
            remoteGeneratedAudioPlaybackSink: { chunks in
                for try await chunk in chunks {
                    await collector.append(chunk)
                }
            },
            runtimeStartupConfigurationStore: testRuntimeStartupConfigurationStore(),
            state: state,
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
                    title: "SpeakSwiftly Test MCP",
                ),
                host: host,
            ),
        )

        try await mcpSurface.start()
        await host.markTransportListening(name: "mcp")
        let initializeMCPResponse = await mcpSurface.handle(mcpPOSTRequest(body: mcpInitializeRequestJSON()))
        let initializeSessionID = try #require(mcpSessionID(from: initializeMCPResponse))
        try await drainMCPResponse(initializeMCPResponse)

        let initializedNotificationResponse = await mcpSurface.handle(
            mcpPOSTRequest(
                body: mcpInitializedNotificationJSON(),
                sessionID: initializeSessionID,
            ),
        )
        #expect(mcpStatusCode(from: initializedNotificationResponse) == 202)

        let successEnvelope = try await mcpEnvelope(
            from: mcpSurface.handle(
                mcpPOSTRequest(
                    body: mcpCallToolRequestJSON(
                        name: "generate_speech",
                        argumentsJSON: #"{"text":"Remote generation probe","generation_location":{"kind":"remote","remote":{"base_url":"http://GMM4.local:7338","service_name":"GMM4"}}}"#,
                    ),
                    sessionID: initializeSessionID,
                ),
            ),
        )
        let result = try #require(successEnvelope["result"] as? [String: Any])
        let content = try #require(result["content"] as? [[String: Any]])
        let firstContent = try #require(content.first)
        #expect((firstContent["text"] as? String)?.contains("accepted the live speech request") == true)
        #expect(await runtime.latestQueuedSpeechInvocation() == nil)

        let requestID = try #require(mcpToolPayload(from: successEnvelope)["request_id"] as? String)
        let snapshot = try await waitForJobSnapshot(requestID, on: host)
        #expect(snapshot.status == "completed")
        #expect(await collector.chunks() == remoteChunks)

        await mcpSurface.stop()
        await host.shutdown()
    }
}

private actor GeneratedAudioChunkCollector {
    private var values = [SpeakSwiftly.GeneratedAudioChunk]()

    func append(_ chunk: SpeakSwiftly.GeneratedAudioChunk) {
        values.append(chunk)
    }

    func chunks() -> [SpeakSwiftly.GeneratedAudioChunk] {
        values
    }
}
