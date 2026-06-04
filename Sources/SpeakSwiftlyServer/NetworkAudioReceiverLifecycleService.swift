import Foundation
import ServiceLifecycle
import SpeakSwiftly
import SSSCore

package actor NetworkAudioReceiverStreamCounter {
    private var activeRequestIDs = Set<String>()

    package init() {}

    package func start(requestID: String) -> Int {
        activeRequestIDs.insert(requestID)
        return activeRequestIDs.count
    }

    package func finish(requestID: String) -> Int {
        activeRequestIDs.remove(requestID)
        return activeRequestIDs.count
    }
}

package struct NetworkAudioReceiverLifecycleService: Service {
    package typealias PlaybackSink = @Sendable (SpeakSwiftly.NetworkAudioInboundStream) async throws -> Void

    package let host: ServerHost
    package let config: NetworkAudioReceiverConfig
    package let shutdownBarrier: EmbeddedLifecycleShutdownBarrier
    package let playbackSink: PlaybackSink

    package init(
        host: ServerHost,
        config: NetworkAudioReceiverConfig,
        shutdownBarrier: EmbeddedLifecycleShutdownBarrier,
        playbackSink: @escaping PlaybackSink = NetworkAudioReceiverLifecycleService.playInboundStream,
    ) {
        self.host = host
        self.config = config
        self.shutdownBarrier = shutdownBarrier
        self.playbackSink = playbackSink
    }

    private static func playInboundStream(_ inboundStream: SpeakSwiftly.NetworkAudioInboundStream) async throws {
        try await Task { @MainActor in
            let player = SpeakSwiftly.LocalGeneratedAudioPlayer()
            try await player.play(chunks: inboundStream.chunks)
        }.value
    }

    package func run() async throws {
        try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            guard config.enabled else {
                return
            }

            await host.markTransportStarting(name: NetworkAudioReceiverConfig.transportName)
            let listener = SpeakSwiftly.NetworkAudioStreamListener(
                advertisement: .init(name: config.serviceName),
                port: config.port,
                sharedToken: config.sharedToken ?? "",
                connectionReadinessTimeout: .seconds(15),
            )

            do {
                try await listener.start()
                let boundPort = try await waitUntilListening(listener)
                await host.markTransportListening(
                    name: NetworkAudioReceiverConfig.transportName,
                    port: Int(boundPort),
                )
            } catch {
                let message = "SpeakSwiftlyServer could not start the LAN audio receiver. Likely cause: \(error)"
                await host.markTransportFailed(name: NetworkAudioReceiverConfig.transportName, message: message)
                throw error
            }

            let streamCounter = NetworkAudioReceiverStreamCounter()
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await gracefulShutdown()
                    }
                    group.addTask {
                        try await monitorListenerState(listener)
                    }
                    group.addTask {
                        await consumeInboundStreams(
                            listener: listener,
                            host: host,
                            streamCounter: streamCounter,
                            playbackSink: playbackSink,
                        )
                    }

                    try await group.next()
                    group.cancelAll()
                }
            } catch is CancellationError {
                // ServiceLifecycle cancellation is the normal shutdown path.
            } catch {
                let message = "SpeakSwiftlyServer LAN audio receiver stopped after a transport failure. Likely cause: \(error)"
                await host.markTransportFailed(name: NetworkAudioReceiverConfig.transportName, message: message)
                throw error
            }

            await listener.stop()
            await host.markTransportStopped(name: NetworkAudioReceiverConfig.transportName)
        }
    }
}

private func waitUntilListening(_ listener: SpeakSwiftly.NetworkAudioStreamListener) async throws -> UInt16 {
    for _ in 0..<200 {
        switch await listener.state {
            case let .listening(port):
                return port ?? 0
            case let .failed(message):
                throw ServerConfigurationError(message)
            case .stopped:
                throw ServerConfigurationError(
                    "SpeakSwiftlyServer LAN audio receiver stopped before Network.framework reported a listening port.",
                )
            case .idle, .starting:
                try await hostLifecycleDelay(for: .milliseconds(25))
        }
    }

    throw EmbeddedLifecycleStartupTimeoutError(
        message: "SpeakSwiftlyServer timed out while waiting for the LAN audio receiver to begin listening after 5 second(s). Likely cause: Network.framework did not finish binding the TCP listener.",
    )
}

private func monitorListenerState(_ listener: SpeakSwiftly.NetworkAudioStreamListener) async throws {
    while !Task.isCancelled {
        switch await listener.state {
            case let .failed(message):
                throw ServerConfigurationError(message)
            case .stopped:
                return
            case .idle, .starting, .listening:
                try await hostLifecycleDelay(for: .milliseconds(250))
        }
    }
}

private func consumeInboundStreams(
    listener: SpeakSwiftly.NetworkAudioStreamListener,
    host: ServerHost,
    streamCounter: NetworkAudioReceiverStreamCounter,
    playbackSink: @escaping NetworkAudioReceiverLifecycleService.PlaybackSink,
) async {
    await withTaskGroup(of: Void.self) { group in
        for await inboundStream in await listener.inboundStreams() {
            group.addTask {
                let activeCount = await streamCounter.start(requestID: inboundStream.requestID)
                await host.markTransportActiveStreamCount(
                    name: NetworkAudioReceiverConfig.transportName,
                    activeStreamCount: activeCount,
                )

                do {
                    try await playbackSink(inboundStream)
                } catch is CancellationError {
                    // Shutdown cancelled playback for this inbound stream.
                } catch {
                    await host.recordRecentError(
                        source: "transport:\(NetworkAudioReceiverConfig.transportName)",
                        code: "network_audio_playback_failed",
                        message: "SpeakSwiftlyServer LAN audio receiver could not play inbound request '\(inboundStream.requestID)' from '\(inboundStream.remoteEndpointDescription)'. Likely cause: \(error)",
                    )
                }

                let remainingCount = await streamCounter.finish(requestID: inboundStream.requestID)
                await host.markTransportActiveStreamCount(
                    name: NetworkAudioReceiverConfig.transportName,
                    activeStreamCount: remainingCount,
                )
            }
        }
    }
}
