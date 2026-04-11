import Foundation
import Hummingbird
import ServiceLifecycle

// MARK: - Embedded Server Session

/// App-facing lifecycle wrapper for embedding the shared SpeakSwiftly server process inside a SwiftUI app.
///
/// `EmbeddedServerSession` keeps the transport and runtime ownership internal while exposing the
/// `@Observable` `ServerState` projection that app UI can read directly.
@MainActor
public final class EmbeddedServerSession {
    struct LifecycleHooks {
        let requestStop: @MainActor @Sendable () async -> Void
        let waitUntilStopped: @MainActor @Sendable () async throws -> Void
    }

    /// The app-facing observable projection of the embedded host state.
    public let state: ServerState

    private let lifecycle: LifecycleHooks
    private var didRequestStop = false

    // MARK: - Initialization

    private init(
        state: ServerState,
        lifecycle: LifecycleHooks
    ) {
        self.state = state
        self.lifecycle = lifecycle
    }

    // MARK: - Lifecycle

    /// Starts an embedded server session using the same environment-driven config loading path as the standalone server.
    public static func start(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws -> EmbeddedServerSession {
        try await start(environment: environment, bootstrap: liveBootstrap)
    }

    static func start(
        environment: [String: String],
        bootstrap: @escaping @Sendable ([String: String], ServerState) async throws -> LifecycleHooks
    ) async throws -> EmbeddedServerSession {
        let state = ServerState()
        let lifecycle = try await bootstrap(environment, state)
        return EmbeddedServerSession(state: state, lifecycle: lifecycle)
    }

    private static func liveBootstrap(
        environment: [String: String],
        state: ServerState
    ) async throws -> LifecycleHooks {
        let configStore = try await ConfigStore(environment: environment)
        let config = try configStore.loadAppConfig()
        let host = await ServerHost.live(appConfig: config, state: state)
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
                    pausePlayback: {
                        let response = try await host.pausePlayback()
                        return .init(
                            state: response.playback.state,
                            activeRequest: response.playback.activeRequest,
                            isStableForConcurrentGeneration: response.playback.isStableForConcurrentGeneration,
                            isRebuffering: response.playback.isRebuffering,
                            stableBufferedAudioMS: response.playback.stableBufferedAudioMS,
                            stableBufferTargetMS: response.playback.stableBufferTargetMS
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
                            stableBufferTargetMS: response.playback.stableBufferTargetMS
                        )
                    },
                    clearPlaybackQueue: {
                        let response = try await host.clearQueue()
                        return response.clearedCount
                    },
                    cancelPlaybackRequest: { requestID in
                        let response = try await host.cancelQueuedOrActiveRequest(requestID: requestID)
                        return response.cancelledRequestID
                    }
                )
            )
        }
        let mcpSurface = await MCPSurface.build(configuration: config.mcp, host: host)
        let app = assembleHBApp(
            configuration: config.http,
            host: host,
            mcpSurface: mcpSurface,
            services: configStore.services
        )

        let configWatchTask = Task {
            do {
                for try await update in configStore.updates() {
                    switch update {
                    case .reloaded(let updatedConfig):
                        await host.applyConfigurationUpdate(updatedConfig)
                    case .rejected(let message):
                        await host.markConfigurationReloadRejected(message)
                    }
                }
            } catch {
                await host.markConfigurationWatchFailed(error)
            }
        }

        if config.http.enabled {
            await host.markTransportStarting(name: "http")
        }
        if config.mcp.enabled {
            await host.markTransportStarting(name: "mcp")
        }

        let serviceGroup = ServiceGroup(
            services: [app],
            gracefulShutdownSignals: [],
            cancellationSignals: [],
            logger: app.logger
        )
        let runTask = Task<Void, Error> {
            var thrownError: (any Error)?

            do {
                if let mcpSurface {
                    try await mcpSurface.start()
                }
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
                thrownError = error
            }

            configWatchTask.cancel()
            if let mcpSurface {
                await mcpSurface.stop()
            }
            await host.shutdown()

            if let thrownError {
                throw thrownError
            }
        }

        return LifecycleHooks(
            requestStop: {
                configWatchTask.cancel()
                await serviceGroup.triggerGracefulShutdown()
            },
            waitUntilStopped: {
                _ = try await runTask.value
            }
        )
    }

    /// Gracefully stops the embedded session and waits for transport and host cleanup to finish.
    public func stop() async throws {
        guard !didRequestStop else {
            try await waitUntilStopped()
            return
        }

        didRequestStop = true
        await lifecycle.requestStop()
        try await waitUntilStopped()
    }

    // MARK: - Internal Lifecycle

    func waitUntilStopped() async throws {
        try await lifecycle.waitUntilStopped()
    }
}
