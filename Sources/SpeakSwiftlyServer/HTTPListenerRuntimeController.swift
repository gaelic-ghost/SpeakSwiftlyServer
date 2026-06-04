import Foundation
import Hummingbird
import Logging
import ServiceLifecycle
import SSSCore
import SSSHTTP

package struct HTTPListenerRuntimeControllerService: Service {
    private let controller: HTTPListenerRuntimeController
    private let shutdownBarrier: EmbeddedLifecycleShutdownBarrier

    package init(
        controller: HTTPListenerRuntimeController,
        shutdownBarrier: EmbeddedLifecycleShutdownBarrier,
    ) {
        self.controller = controller
        self.shutdownBarrier = shutdownBarrier
    }

    package func run() async throws {
        try await withEmbeddedShutdownBarrier(shutdownBarrier) {
            try await controller.startConfiguredListeners()
            do {
                try await gracefulShutdown()
            } catch is CancellationError {
                // Continue into listener shutdown so Hummingbird and Bonjour both drain.
            }
            await controller.stopAllForServerShutdown()
        }
    }
}

package actor HTTPListenerRuntimeController {
    private struct ListenerDescriptor {
        let name: HTTPListenerRuntimeName
        let startupEnabled: Bool
        let configuration: HTTPConfig
        let transportName: String
        let additionalListeningTransports: [String]
        let advertisedAddress: String?
        let mountAdditionalRoutes: (@Sendable (Router<BasicRequestContext>) -> Void)?
        let beforeServerStarts: [@Sendable () async throws -> Void]
        let bonjourPublisher: HTTPListenerBonjourPublisher?
    }

    private struct RunningListener {
        let id: UUID
        let runTask: Task<Void, Error>
    }

    private let host: ServerHost
    private let logger: Logger
    private let descriptors: [HTTPListenerRuntimeName: ListenerDescriptor]
    private var runningListeners = [HTTPListenerRuntimeName: RunningListener]()

    package var runtimeControl: HTTPListenerRuntimeControl {
        .init(
            enable: { listener in
                try await self.enable(listener)
            },
            disable: { listener in
                try await self.disable(listener)
            },
        )
    }

    package init(
        host: ServerHost,
        localhostConfiguration: HTTPConfig,
        lanConfiguration: LANHTTPListenerConfig,
        mcpConfig: MCPConfig,
        mountLocalhostAdditionalRoutes: (@Sendable (Router<BasicRequestContext>) -> Void)? = nil,
        localhostBeforeServerStarts: [@Sendable () async throws -> Void] = [],
        lanBeforeServerStarts: [@Sendable () async throws -> Void] = [],
        logger: Logger = Logger(label: "SpeakSwiftlyServer.HTTPListenerRuntimeController"),
    ) {
        self.host = host
        self.logger = logger

        let localhostAliases = mcpConfig.enabled ? ["http", "mcp"] : ["http"]
        let runtimeLocalhostConfiguration = HTTPConfig(
            enabled: true,
            host: localhostConfiguration.host,
            port: localhostConfiguration.port,
            sseHeartbeatSeconds: localhostConfiguration.sseHeartbeatSeconds,
        )
        let localhostDescriptor = ListenerDescriptor(
            name: .localhost,
            startupEnabled: localhostConfiguration.enabled,
            configuration: runtimeLocalhostConfiguration,
            transportName: HTTPListenersConfig.localhostTransportName,
            additionalListeningTransports: localhostAliases,
            advertisedAddress: "http://\(localhostConfiguration.host):\(localhostConfiguration.port)",
            mountAdditionalRoutes: mountLocalhostAdditionalRoutes,
            beforeServerStarts: localhostBeforeServerStarts,
            bonjourPublisher: nil,
        )
        let runtimeLANConfiguration = HTTPConfig(
            enabled: true,
            host: lanConfiguration.host,
            port: lanConfiguration.port,
            sseHeartbeatSeconds: lanConfiguration.sseHeartbeatSeconds,
        )
        let lanAdvertisedAddress: String? = if lanConfiguration.advertiseBonjour {
            "\(lanConfiguration.serviceName).\(HTTPListenersConfig.lanBonjourType).\(HTTPListenersConfig.bonjourDomain)"
        } else if lanConfiguration.port == 0 {
            nil
        } else {
            "http://\(lanConfiguration.host):\(lanConfiguration.port)"
        }
        let lanDescriptor = ListenerDescriptor(
            name: .lan,
            startupEnabled: lanConfiguration.enabled,
            configuration: runtimeLANConfiguration,
            transportName: HTTPListenersConfig.lanTransportName,
            additionalListeningTransports: [],
            advertisedAddress: lanAdvertisedAddress,
            mountAdditionalRoutes: nil,
            beforeServerStarts: lanBeforeServerStarts,
            bonjourPublisher: lanConfiguration.advertiseBonjour
                ? HTTPListenerBonjourPublisher(serviceName: lanConfiguration.serviceName)
                : nil,
        )
        descriptors = [
            .localhost: localhostDescriptor,
            .lan: lanDescriptor,
        ]
    }

    package func startConfiguredListeners() async throws {
        for listener in HTTPListenerRuntimeName.allCases {
            guard let descriptor = descriptors[listener], descriptor.startupEnabled else {
                continue
            }

            _ = try await enable(listener)
        }
    }

    package func enable(_ listener: HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot {
        guard runningListeners[listener] == nil else {
            return try await host.transportStatus(named: listener.transportName)
        }

        let descriptor = try descriptor(for: listener)

        await markEnabled(descriptor, state: "starting", port: descriptor.configuration.port)
        let app = assembleApp(for: descriptor)
        let listenerRunID = UUID()
        let runTask = Task<Void, Error> {
            do {
                try await app.runService(gracefulShutdownSignals: [])
                await self.markStoppedIfCurrent(descriptor, listener: listener, id: listenerRunID)
            } catch {
                await self.markFailedIfCurrent(
                    descriptor,
                    listener: listener,
                    id: listenerRunID,
                    message: "SpeakSwiftlyServer could not keep the \(listener.rawValue) HTTP listener running. Likely cause: \(error.localizedDescription)",
                )
                throw error
            }
        }
        runningListeners[listener] = .init(id: listenerRunID, runTask: runTask)

        return try await waitForListenerStart(listener)
    }

    package func disable(_ listener: HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot {
        guard listener != .localhost else {
            throw ServerRequestError(
                .serviceUnavailable,
                message: "SpeakSwiftlyServer cannot disable the localhost HTTP listener at runtime yet because Hummingbird listener shutdown is not isolated enough to guarantee sibling LAN listeners keep running. Disable the LAN listener for LAN exposure control, or restart with app.listeners.localhost.enabled set to false for a startup-time localhost change.",
            )
        }

        let descriptor = try descriptor(for: listener)
        guard let running = runningListeners.removeValue(forKey: listener) else {
            await markDisabled(descriptor)
            return try await host.transportStatus(named: descriptor.transportName)
        }

        await markEnabled(descriptor, state: "stopping", port: try? host.transportStatus(named: descriptor.transportName).port)
        await descriptor.bonjourPublisher?.stop()
        await markDisabled(descriptor)
        running.runTask.cancel()
        _ = try? await running.runTask.value

        return try await host.transportStatus(named: descriptor.transportName)
    }

    package func stopAllForServerShutdown() async {
        let activeListeners = runningListeners
        runningListeners.removeAll()
        for (listener, running) in activeListeners {
            guard let descriptor = descriptors[listener] else { continue }

            running.runTask.cancel()
            await descriptor.bonjourPublisher?.stop()
            await markStopped(descriptor)
            Task {
                _ = try? await running.runTask.value
            }
        }
    }

    private func descriptor(for listener: HTTPListenerRuntimeName) throws -> ListenerDescriptor {
        guard let descriptor = descriptors[listener] else {
            throw ServerRequestError(
                .notFound,
                message: "SpeakSwiftlyServer could not find a runtime descriptor for the \(listener.rawValue) HTTP listener.",
            )
        }

        return descriptor
    }

    private func assembleApp(
        for descriptor: ListenerDescriptor,
    ) -> Application<Router<BasicRequestContext>.Responder> {
        assembleHBApp(
            configuration: descriptor.configuration,
            host: host,
            transportName: descriptor.transportName,
            additionalListeningTransports: descriptor.additionalListeningTransports,
            mountAdditionalRoutes: descriptor.mountAdditionalRoutes,
            beforeServerStarts: descriptor.beforeServerStarts,
            onServerRunning: { channel in
                guard let port = channel.localAddress?.port else { return }

                await descriptor.bonjourPublisher?.publish(port: port)
                await self.markEnabled(descriptor, state: "listening", port: port)
            },
        )
    }

    private func markEnabled(
        _ descriptor: ListenerDescriptor,
        state: String,
        port: Int?,
    ) async {
        await host.replaceTransportStatus(
            .init(
                name: descriptor.transportName,
                enabled: true,
                state: state,
                host: descriptor.configuration.host,
                port: port,
                path: nil,
                advertisedAddress: advertisedAddress(for: descriptor, port: port),
            ),
        )
        for alias in descriptor.additionalListeningTransports {
            await markAliasEnabled(alias, descriptor: descriptor, state: state, port: port)
        }
    }

    private func advertisedAddress(for descriptor: ListenerDescriptor, port: Int?) -> String? {
        guard descriptor.advertisedAddress == nil, let port, port > 0 else {
            return descriptor.advertisedAddress
        }

        return "http://\(descriptor.configuration.host):\(port)"
    }

    private func markAliasEnabled(
        _ alias: String,
        descriptor: ListenerDescriptor,
        state: String,
        port: Int?,
    ) async {
        let path = alias == "mcp" ? "/mcp" : nil
        let advertisedPort = port ?? descriptor.configuration.port
        let advertisedAddress = if alias == "mcp" {
            "http://\(descriptor.configuration.host):\(advertisedPort)/mcp"
        } else {
            "http://\(descriptor.configuration.host):\(advertisedPort)"
        }
        await host.replaceTransportStatus(
            .init(
                name: alias,
                enabled: true,
                state: state,
                host: descriptor.configuration.host,
                port: advertisedPort,
                path: path,
                advertisedAddress: advertisedAddress,
            ),
        )
    }

    private func markStopped(_ descriptor: ListenerDescriptor) async {
        await descriptor.bonjourPublisher?.stop()
        await host.markTransportStopped(name: descriptor.transportName)
        for alias in descriptor.additionalListeningTransports {
            await host.markTransportStopped(name: alias)
        }
    }

    private func markStoppedIfCurrent(
        _ descriptor: ListenerDescriptor,
        listener: HTTPListenerRuntimeName,
        id: UUID,
    ) async {
        guard runningListeners[listener]?.id == id else {
            return
        }

        runningListeners.removeValue(forKey: listener)
        await markStopped(descriptor)
    }

    private func markDisabled(_ descriptor: ListenerDescriptor) async {
        await descriptor.bonjourPublisher?.stop()
        await host.replaceTransportStatus(
            .init(
                name: descriptor.transportName,
                enabled: false,
                state: "disabled",
                host: nil,
                port: nil,
                path: nil,
                advertisedAddress: nil,
            ),
        )
        for alias in descriptor.additionalListeningTransports {
            await host.replaceTransportStatus(
                .init(
                    name: alias,
                    enabled: false,
                    state: "disabled",
                    host: nil,
                    port: nil,
                    path: nil,
                    advertisedAddress: nil,
                ),
            )
        }
    }

    private func markFailed(_ descriptor: ListenerDescriptor, message: String) async {
        await host.markTransportFailed(name: descriptor.transportName, message: message)
        for alias in descriptor.additionalListeningTransports {
            await host.markTransportFailed(name: alias, message: message)
        }
    }

    private func markFailedIfCurrent(
        _ descriptor: ListenerDescriptor,
        listener: HTTPListenerRuntimeName,
        id: UUID,
        message: String,
    ) async {
        guard runningListeners[listener]?.id == id else {
            return
        }

        runningListeners.removeValue(forKey: listener)
        await markFailed(descriptor, message: message)
    }

    private func waitForListenerStart(_ listener: HTTPListenerRuntimeName) async throws -> TransportStatusSnapshot {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            let snapshot = try await host.transportStatus(named: listener.transportName)
            if snapshot.state == "listening", (snapshot.port ?? 0) > 0 {
                return snapshot
            }
            if snapshot.state == "failed" {
                throw ServerRequestError(
                    .serviceUnavailable,
                    message: "SpeakSwiftlyServer could not enable the \(listener.rawValue) HTTP listener because the listener failed before it reported a bound port.",
                )
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        throw ServerRequestError(
            .serviceUnavailable,
            message: "SpeakSwiftlyServer timed out while enabling the \(listener.rawValue) HTTP listener before Hummingbird reported a bound port.",
        )
    }
}
