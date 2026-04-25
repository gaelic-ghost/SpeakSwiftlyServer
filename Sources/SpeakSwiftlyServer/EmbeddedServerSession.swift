import Foundation
import Hummingbird
import ServiceLifecycle

struct EmbeddedServerLifecycleHooks {
    let requestStop: @Sendable () async -> Void
    let waitUntilStopped: @Sendable () async throws -> Void
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
    defaultProfile: AppRuntimeDefaultProfile,
) -> [String: String] {
    var resolvedEnvironment = environment
    resolvedEnvironment[AppRuntimeDefaultProfile.environmentKey] = defaultProfile.rawValue
    if let port = options.port {
        resolvedEnvironment["APP_PORT"] = String(port)
        resolvedEnvironment["APP_HTTP_PORT"] = String(port)
    }
    if let runtimeProfileRootURL = options.runtimeProfileRootURL {
        resolvedEnvironment["SPEAKSWIFTLY_PROFILE_ROOT"] = runtimeProfileRootURL.standardizedFileURL.path
    }
    return resolvedEnvironment
}

func embeddedServerLiveBootstrap(
    environment: [String: String],
    server: EmbeddedServer,
) async throws -> EmbeddedServerLifecycleHooks {
    let configStore = try await ConfigStore(
        environment: environment,
        defaultProfile: .embeddedSession,
    )
    let config = try configStore.loadAppConfig()
    let host = await ServerHost.makeLive(appConfig: config, state: server, environment: environment)
    await MainActor.run {
        server.configureActions(
            .init(
                refreshVoiceProfiles: {
                    try await host.refreshVoiceProfiles()
                },
                queueLiveSpeech: { text, profileName, textProfileID, normalizationContext, sourceFormat, requestContext, qwenPreModelTextChunking in
                    guard let resolvedProfileName = await host.resolvedRequestedVoiceProfileName(profileName) else {
                        let errorMessage = await host.missingVoiceProfileNameMessage(for: "the live speech request")
                        throw ServerConfigurationError(errorMessage)
                    }

                    return try await host.queueSpeechLive(
                        text: text,
                        profileName: resolvedProfileName,
                        textProfileID: textProfileID,
                        normalizationContext: normalizationContext,
                        sourceFormat: sourceFormat,
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
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                resumePlayback: {
                    let response = try await host.resumePlayback()
                    return .init(
                        state: response.playback.state,
                        activeRequest: response.playback.activeRequest,
                        isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                        isRebuffering: response.playback.isRebuffering,
                        stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                        stableBufferTargetMS: response.playback.stableBufferTargetMS,
                    )
                },
                clearPlaybackQueue: {
                    let response = try await host.clearQueue()
                    return response.clearedCount
                },
                cancelPlaybackRequest: { requestID in
                    let response = try await host.cancelQueuedOrActiveRequest(requestID: requestID)
                    return response.cancelledRequestID
                },
            ),
        )
    }
    let mcpSurface = await MCPSurface.build(configuration: config.mcp, host: host)
    let hostReadinessGate = EmbeddedLifecycleReadinessGate()
    let mcpReadinessGate = mcpSurface.map { _ in EmbeddedLifecycleReadinessGate() }
    let hostDependentSiblingServiceCount =
        1 + // EmbeddedApplicationService
        (mcpSurface == nil ? 0 : 1) + // MCPLifecycleService
        (configStore.services.isEmpty ? 0 : 1) + // ConfigWatchService
        1 // HostPruneService
    let shutdownBarrier = EmbeddedLifecycleShutdownBarrier(targetCount: hostDependentSiblingServiceCount)
    let app = assembleHBApp(
        configuration: config.http,
        host: host,
        mcpSurface: mcpSurface,
        beforeServerStarts: [
            {
                try await hostReadinessGate.waitUntilReady()
            },
            {
                if let mcpReadinessGate {
                    try await mcpReadinessGate.waitUntilReady()
                }
            },
        ],
    )

    if config.http.enabled {
        await host.markTransportStarting(name: "http")
    }
    if config.mcp.enabled {
        await host.markTransportStarting(name: "mcp")
    }

    var services = configStore.services.map { service in
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
    if !configStore.services.isEmpty {
        services.append(
            .init(
                service: ConfigWatchService(
                    configStore: configStore,
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
    services.append(
        .init(
            service: EmbeddedApplicationService(
                application: app,
                shutdownBarrier: shutdownBarrier,
            ),
        ),
    )

    let serviceGroup = ServiceGroup(
        configuration: .init(
            services: services,
            logger: app.logger,
        ),
    )
    let runTask = Task<Void, Error> {
        do {
            try await serviceGroup.run()
            if config.http.enabled {
                await host.markTransportStopped(name: "http")
            }
            if config.mcp.enabled {
                await host.markTransportStopped(name: "mcp")
            }
        } catch {
            let message = "SpeakSwiftlyServer could not keep the embedded Hummingbird transport process running. Likely cause: \(error.localizedDescription)"
            if config.http.enabled {
                await host.markTransportFailed(name: "http", message: message)
            }
            if config.mcp.enabled {
                await host.markTransportFailed(name: "mcp", message: message)
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
