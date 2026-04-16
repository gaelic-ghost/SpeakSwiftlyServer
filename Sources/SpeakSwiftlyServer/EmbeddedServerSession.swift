import Foundation
import Hummingbird
import ServiceLifecycle

// MARK: - Embedded Server Session

/// App-facing lifecycle wrapper for embedding the shared SpeakSwiftly server process inside a SwiftUI app.
///
/// `EmbeddedServerSession` keeps the transport and runtime ownership internal while exposing the
/// `@Observable` `ServerState` projection that app UI can read directly.
///
/// The wrapper itself is safe to move between tasks because mutable lifecycle coordination stays
/// behind actor-isolated members while the observable `ServerState` remains main-actor-owned.
public final class EmbeddedServerSession: @unchecked Sendable {
    /// Configuration options for the app-owned embedded session bootstrap path.
    public struct Options: Sendable {
        /// Optional localhost port override for the embedded HTTP transport.
        ///
        /// When this is set, the embedded session applies the same port to the shared transport
        /// default and the concrete HTTP listener unless the caller later overrides those values
        /// more specifically through the environment-driven config surface.
        public var port: Int?

        /// Optional runtime profile-root override for the embedded server and the underlying
        /// `SpeakSwiftly` runtime.
        ///
        /// Pass this when the host app wants one explicit persistence root, such as an app-owned
        /// Application Support subdirectory or an App Group container path.
        public var runtimeProfileRootURL: URL?

        public init(port: Int? = nil, runtimeProfileRootURL: URL? = nil) {
            self.port = port
            self.runtimeProfileRootURL = runtimeProfileRootURL
        }
    }

    struct LifecycleHooks {
        let requestStop: @Sendable () async -> Void
        let waitUntilStopped: @Sendable () async throws -> Void
    }

    actor StopCoordinator {
        private var didRequestStop = false

        func requestStopIfNeeded() -> Bool {
            guard !didRequestStop else {
                return false
            }

            didRequestStop = true
            return true
        }
    }

    /// The app-facing observable projection of the embedded host state.
    public let state: ServerState

    private let lifecycle: LifecycleHooks
    private let stopCoordinator = StopCoordinator()

    // MARK: - Initialization

    private init(
        state: ServerState,
        lifecycle: LifecycleHooks,
    ) {
        self.state = state
        self.lifecycle = lifecycle
    }

    /// Starts an embedded server session using the package's embedded-session default profile.
    ///
    /// Use this when an app wants to own the shared SpeakSwiftly host lifecycle directly and bind UI to ``state``.
    /// Pass ``Options`` to override the embedded HTTP port or the runtime profile root without having to rewrite
    /// global process environment state first.
    public static func start(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        options: Options = .init(),
    ) async throws -> EmbeddedServerSession {
        try await start(
            environment: environment,
            options: options,
            defaultProfile: .embeddedSession,
            bootstrap: liveBootstrap,
        )
    }

    static func start(
        environment: [String: String],
        options: Options = .init(),
        defaultProfile: AppRuntimeDefaultProfile = .embeddedSession,
        bootstrap: @escaping @Sendable ([String: String], ServerState) async throws -> LifecycleHooks,
    ) async throws -> EmbeddedServerSession {
        let state = await MainActor.run { ServerState() }
        let lifecycle = try await bootstrap(
            effectiveEnvironment(
                environment: environment,
                options: options,
                defaultProfile: defaultProfile,
            ),
            state,
        )
        return EmbeddedServerSession(state: state, lifecycle: lifecycle)
    }

    static func liveBootstrap(
        environment: [String: String],
        state: ServerState,
    ) async throws -> LifecycleHooks {
        let configStore = try await ConfigStore(
            environment: environment,
            defaultProfile: .embeddedSession,
        )
        let config = try configStore.loadAppConfig()
        let host = await ServerHost.makeLive(appConfig: config, state: state, environment: environment)
        await MainActor.run {
            state.configureActions(
                .init(
                    refreshVoiceProfiles: {
                        try await host.refreshVoiceProfiles()
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

        return LifecycleHooks(
            requestStop: {
                await serviceGroup.triggerGracefulShutdown()
            },
            waitUntilStopped: {
                _ = try await runTask.value
            },
        )
    }

    private static func effectiveEnvironment(
        environment: [String: String],
        options: Options,
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

    /// Gracefully stops the embedded session and waits for transport and host cleanup to finish.
    public func stop() async throws {
        if await stopCoordinator.requestStopIfNeeded() {
            await lifecycle.requestStop()
        }
        try await waitUntilStopped()
    }

    // MARK: - Internal Lifecycle

    func waitUntilStopped() async throws {
        try await lifecycle.waitUntilStopped()
    }
}
