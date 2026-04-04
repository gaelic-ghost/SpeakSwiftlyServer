import Foundation
import Hummingbird

// MARK: - Entry Point

@main
enum SpeakSwiftlyServer {
    static func main() async throws {
        let configStore = try await ConfigStore()
        let config = try configStore.loadAppConfig()
        let state = await MainActor.run { ServerState() }
        let host = await ServerHost.live(appConfig: config, state: state)
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
        defer {
            configWatchTask.cancel()
            Task {
                await host.shutdown()
            }
        }

        if config.http.enabled {
            await host.markTransportStarting(name: "http")
        }
        if config.mcp.enabled {
            await host.markTransportStarting(name: "mcp")
        }

        do {
            if let mcpSurface {
                try await mcpSurface.start()
            }
            try await app.runService()
            if config.http.enabled {
                await host.markTransportStopped(name: "http")
            }
            if config.mcp.enabled {
                await host.markTransportStopped(name: "mcp")
            }
            if let mcpSurface {
                await mcpSurface.stop()
            }
        } catch {
            let message = "SpeakSwiftlyServer could not keep the shared Hummingbird transport process running. Likely cause: \(error.localizedDescription)"
            if config.http.enabled {
                await host.markTransportFailed(name: "http", message: message)
            }
            if config.mcp.enabled {
                await host.markTransportFailed(name: "mcp", message: message)
            }
            if let mcpSurface {
                await mcpSurface.stop()
            }
            throw error
        }
    }
}
