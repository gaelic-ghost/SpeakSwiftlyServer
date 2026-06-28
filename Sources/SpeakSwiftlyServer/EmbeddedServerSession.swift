import Foundation
import Hummingbird
import Logging
import ServiceLifecycle
import SpeakSwiftly
import SSSCore
import SSSHTTP
import SSSMCP

package struct EmbeddedServerLifecycleHooks {
    package let requestStop: @Sendable () async -> Void
    package let waitUntilStopped: @Sendable () async throws -> Void

    package init(
        requestStop: @escaping @Sendable () async -> Void,
        waitUntilStopped: @escaping @Sendable () async throws -> Void,
    ) {
        self.requestStop = requestStop
        self.waitUntilStopped = waitUntilStopped
    }
}

actor EmbeddedServerStopCoordinator {
    private var didRequestStop = false

    func requestStopIfNeeded() -> Bool {
        guard !didRequestStop else {
            return false
        }

        didRequestStop = true
        return true
    }
}

func embeddedServerEffectiveEnvironment(
    environment: [String: String],
    options: EmbeddedServer.Options,
    defaultProfile: ServerConfigDefaultProfile,
) -> [String: String] {
    var resolvedEnvironment = environment
    resolvedEnvironment[ServerConfigDefaultProfile.environmentKey] = defaultProfile.rawValue
    if let port = options.port {
        resolvedEnvironment["APP_PORT"] = String(port)
        resolvedEnvironment["APP_HTTP_PORT"] = String(port)
    }
    return resolvedEnvironment
}

func embeddedServerLiveBootstrap(
    environment: [String: String],
    server: EmbeddedServer,
) async throws -> EmbeddedServerLifecycleHooks {
    let bootstrapOptions = await MainActor.run { server.bootstrapOptions }
    let defaultPersistence = ServerConfigPersistence.defaultForCurrentUser()
    let configurationURL = bootstrapOptions.configurationURL ?? defaultPersistence.configurationURL
    let profileRootURL = bootstrapOptions.runtimeProfileRootURL ?? defaultPersistence.profileRootURL
    let serverConfigStore = try await ServerConfigStore(
        environment: environment,
        defaultProfile: nil,
        configurationURL: configurationURL,
    )
    let config = try serverConfigStore.loadAppConfig()
    let host = await ServerHost.makeLive(
        appConfig: config,
        state: server,
        environment: environment,
        configurationURL: configurationURL,
        profileRootURL: profileRootURL,
    )
    await MainActor.run {
        server.configureActions(
            .init(
                refreshVoiceProfiles: {
                    try await host.refreshVoiceProfiles()
                },
                queueLiveSpeech: { text, profileName, textProfileID, requestContext, qwenPreModelTextChunking in
                    guard let resolvedProfileName = await host.resolvedRequestedVoiceProfileName(profileName) else {
                        let errorMessage = await host.missingVoiceProfileNameMessage(for: "the live speech request")
                        throw ServerConfigurationError(errorMessage)
                    }

                    return try await host.queueSpeechLive(
                        text: text,
                        profileName: resolvedProfileName,
                        textProfileID: textProfileID,
                        requestContext: requestContext,
                        qwenPreModelTextChunking: qwenPreModelTextChunking,
                    )
                },
                setDefaultVoiceProfileName: { profileName in
                    try await host.setDefaultVoiceProfileName(profileName)
                },
                clearDefaultVoiceProfileName: {
                    try await host.clearDefaultVoiceProfileName()
                },
                switchSpeechBackend: { speechBackend in
                    _ = try await host.switchSpeechBackend(to: speechBackend)
                    return await host.hostStateSnapshot()
                },
                reloadModels: {
                    _ = try await host.reloadModels()
                    return await host.hostStateSnapshot()
                },
                unloadModels: {
                    _ = try await host.unloadModels()
                    return await host.hostStateSnapshot()
                },
                pausePlayback: {
                    let response = try await host.pausePlayback()
                    return response.playback
                },
                resumePlayback: {
                    let response = try await host.resumePlayback()
                    return response.playback
                },
                clearPlaybackQueue: {
                    let response = try await host.clearQueue(SpeakSwiftly.QueueType.playback)
                    return response.clearedCount
                },
                cancelPlaybackRequest: { requestID in
                    let response = try await host.cancelQueuedOrActiveRequest(
                        SpeakSwiftly.QueueType.playback,
                        requestID: requestID,
                    )
                    return response.cancelledRequestID
                },
            ),
        )
    }
    let mcpSurface = await MCPSurface.build(configuration: config.mcp, host: host)
    let hostReadinessGate = EmbeddedLifecycleReadinessGate()
    let mcpReadinessGate = mcpSurface.map { _ in EmbeddedLifecycleReadinessGate() }
    let localhostHTTPConfig = config.listeners.localhost
    let lanHTTPConfig = config.listeners.lan.http
    let hostDependentSiblingServiceCount =
        ((localhostHTTPConfig.enabled || lanHTTPConfig.enabled) ? 1 : 0) + // HTTPListenerRuntimeControllerService
        (mcpSurface == nil ? 0 : 1) + // MCPLifecycleService
        (serverConfigStore.services.isEmpty ? 0 : 1) + // ConfigWatchService
        (config.networkAudioReceiver.enabled ? 1 : 0) + // NetworkAudioReceiverLifecycleService
        1 + // NetworkAudioDestinationBrowserLifecycleService
        1 // HostPruneService
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: hostDependentSiblingServiceCount)
    let listenerController = HTTPListenerRuntimeController(
        host: host,
        localhostConfiguration: localhostHTTPConfig,
        lanConfiguration: config.listeners.lan,
        mcpConfig: config.mcp,
        serverName: config.server.name,
        mountLocalhostAdditionalRoutes: { router in
            mcpSurface?.mount(on: router)
        },
        localhostBeforeServerStarts: [
            {
                try await hostReadinessGate.waitUntilReady()
            },
            {
                if let mcpReadinessGate {
                    try await mcpReadinessGate.waitUntilReady()
                }
            },
        ],
        lanBeforeServerStarts: [
            {
                try await hostReadinessGate.waitUntilReady()
            },
        ],
        logger: Logger(label: "SpeakSwiftlyServer.HTTPListeners"),
    )
    await host.configureHTTPListenerRuntimeControl(listenerController.runtimeControl)

    let legacyStartupTransports = localhostHTTPConfig.enabled ? ["http"] : []
    for transportName in legacyStartupTransports {
        await host.markTransportStarting(name: transportName)
    }
    if localhostHTTPConfig.enabled {
        await host.markTransportStarting(name: HTTPListenersConfig.localhostTransportName)
    }
    if config.mcp.enabled {
        await host.markTransportStarting(name: "mcp")
    }
    if lanHTTPConfig.enabled {
        await host.markTransportStarting(name: HTTPListenersConfig.lanTransportName)
    }
    if config.networkAudioReceiver.enabled {
        await host.markTransportStarting(name: NetworkAudioReceiverConfig.transportName)
    }
    await host.markTransportStarting(name: NetworkAudioDiscoveryTransport.name)

    var services = serverConfigStore.services.map { service in
        ServiceGroupConfiguration.ServiceConfiguration(service: service)
    }
    services.append(
        .init(
            service: HostLifecycleService(
                host: host,
                readinessGate: hostReadinessGate,
                shutdownBarrier: shutdownBarrier,
                startupTimeout: HostLifecycleService.defaultStartupTimeout,
            ),
        ),
    )
    if !serverConfigStore.services.isEmpty {
        services.append(
            .init(
                service: ConfigWatchService(
                    serverConfigStore: serverConfigStore,
                    host: host,
                    shutdownBarrier: shutdownBarrier,
                ),
                successTerminationBehavior: .ignore,
                failureTerminationBehavior: .ignore,
                serviceName: "ConfigWatchService(non-fatal)",
            ),
        )
    }
    services.append(
        .init(
            service: HostPruneService(
                host: host,
                shutdownBarrier: shutdownBarrier,
            ),
        ),
    )
    if config.networkAudioReceiver.enabled {
        services.append(
            .init(
                service: NetworkAudioReceiverLifecycleService(
                    host: host,
                    config: config.networkAudioReceiver,
                    shutdownBarrier: shutdownBarrier,
                ),
                serviceName: "NetworkAudioReceiverLifecycleService",
            ),
        )
    }
    services.append(
        .init(
            service: NetworkAudioDestinationBrowserLifecycleService(
                host: host,
                shutdownBarrier: shutdownBarrier,
            ),
            serviceName: "NetworkAudioDestinationBrowserLifecycleService",
        ),
    )
    if let mcpSurface, let mcpReadinessGate {
        services.append(
            .init(
                service: MCPLifecycleService(
                    surface: mcpSurface,
                    readinessGate: mcpReadinessGate,
                    shutdownBarrier: shutdownBarrier,
                ),
            ),
        )
    }
    if localhostHTTPConfig.enabled || lanHTTPConfig.enabled {
        services.append(
            .init(
                service: HTTPListenerRuntimeControllerService(
                    controller: listenerController,
                    shutdownBarrier: shutdownBarrier,
                ),
                serviceName: "HTTPListenerRuntimeControllerService",
            ),
        )
    }

    let serviceGroup = ServiceGroup(
        configuration: .init(
            services: services,
            logger: Logger(label: "SpeakSwiftlyServer.EmbeddedSession"),
        ),
    )
    let runTask = Task<Void, Error> {
        do {
            try await serviceGroup.run()
            if localhostHTTPConfig.enabled {
                await host.markTransportStopped(name: "http")
                await host.markTransportStopped(name: HTTPListenersConfig.localhostTransportName)
            }
            if lanHTTPConfig.enabled {
                await host.markTransportStopped(name: HTTPListenersConfig.lanTransportName)
            }
            if config.mcp.enabled {
                await host.markTransportStopped(name: "mcp")
            }
            if config.networkAudioReceiver.enabled {
                await host.markTransportStopped(name: NetworkAudioReceiverConfig.transportName)
            }
        } catch {
            let message = "SpeakSwiftlyServer could not keep the embedded Hummingbird transport process running. Likely cause: \(error.localizedDescription)"
            if localhostHTTPConfig.enabled {
                await host.markTransportFailed(name: "http", message: message)
                await host.markTransportFailed(name: HTTPListenersConfig.localhostTransportName, message: message)
            }
            if lanHTTPConfig.enabled {
                await host.markTransportFailed(name: HTTPListenersConfig.lanTransportName, message: message)
            }
            if config.mcp.enabled {
                await host.markTransportFailed(name: "mcp", message: message)
            }
            if config.networkAudioReceiver.enabled {
                await host.markTransportFailed(name: NetworkAudioReceiverConfig.transportName, message: message)
            }
            throw error
        }
    }

    return EmbeddedServerLifecycleHooks(
        requestStop: {
            await serviceGroup.triggerGracefulShutdown()
        },
        waitUntilStopped: {
            _ = try await runTask.value
        },
    )
}
