import Foundation
import ServiceLifecycle
import SpeakSwiftly
import SSSCore

package struct NetworkAudioDestinationBrowserLifecycleService: Service {
    package let host: ServerHost
    package let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    package init(
        host: ServerHost,
        shutdownBarrier: EmbeddedLifecycleShutdownBarrier,
    ) {
        self.host = host
        self.shutdownBarrier = shutdownBarrier
    }

    package func run() async throws {
        try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            await host.markTransportStarting(name: NetworkAudioDiscoveryTransport.name)
            let browser = SpeakSwiftly.NetworkAudioDestinationBrowser()
            await browser.start()
            await host.markTransportBrowsing(name: NetworkAudioDiscoveryTransport.name)

            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await gracefulShutdown()
                    }
                    group.addTask {
                        try await monitorBrowserState(browser, host: host)
                    }
                    group.addTask {
                        for await destinations in await browser.updates() {
                            await host.replaceNetworkAudioDestinations(destinations)
                        }
                    }

                    try await group.next()
                    group.cancelAll()
                }
            } catch is CancellationError {
                // ServiceLifecycle cancellation is the normal shutdown path.
            } catch {
                let message = "SpeakSwiftlyServer LAN audio receiver discovery stopped after a Bonjour browser failure. Likely cause: \(error.localizedDescription)"
                await host.markTransportFailed(name: NetworkAudioDiscoveryTransport.name, message: message)
                throw error
            }

            await browser.stop()
            await host.replaceNetworkAudioDestinations([])
            await host.markTransportStopped(name: NetworkAudioDiscoveryTransport.name)
        }
    }
}

private func monitorBrowserState(
    _ browser: SpeakSwiftly.NetworkAudioDestinationBrowser,
    host: ServerHost,
) async throws {
    while !Task.isCancelled {
        switch await browser.state {
            case .idle, .browsing:
                try await hostLifecycleDelay(for: .milliseconds(250))
            case let .waiting(message):
                await host.recordRecentError(
                    source: "transport:\(NetworkAudioDiscoveryTransport.name)",
                    code: "network_audio_discovery_waiting",
                    message: "SpeakSwiftlyServer LAN audio receiver discovery is waiting for Bonjour to become available. Likely cause: \(message)",
                )
                try await hostLifecycleDelay(for: .seconds(1))
            case let .failed(message):
                throw ServerConfigurationError(message)
        }
    }
}
