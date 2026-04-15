import Foundation
import Hummingbird
import ServiceLifecycle

// MARK: - HTTP Surface

func assembleHBApp(
    configuration: HTTPConfig,
    host: ServerHost,
    mcpSurface: MCPSurface? = nil,
    services: [any Service] = [],
    beforeServerStarts startupProcesses: [@Sendable () async throws -> Void] = [],
) -> Application<Router<BasicRequestContext>.Responder> {
    let router = Router()
    if configuration.enabled {
        registerHTTPRoutes(on: router, configuration: configuration, host: host)
    }
    mcpSurface?.mount(on: router)

    var app = Application(
        router: router,
        configuration: .init(address: .hostname(configuration.host, port: configuration.port)),
        services: services,
        onServerRunning: { _ in
            if configuration.enabled {
                await host.markTransportListening(name: "http")
            }
            if mcpSurface != nil {
                await host.markTransportListening(name: "mcp")
            }
        },
    )

    for startupProcess in startupProcesses {
        app.beforeServerStarts(perform: startupProcess)
    }

    return app
}

// MARK: - Route Registration

private func registerHTTPRoutes(
    on router: Router<BasicRequestContext>,
    configuration: HTTPConfig,
    host: ServerHost,
) {
    registerHTTPRuntimeRoutes(
        on: router,
        configuration: configuration,
        host: host,
    )
    registerHTTPVoiceRoutes(
        on: router,
        configuration: configuration,
        host: host,
    )
    registerHTTPTextProfileRoutes(on: router, host: host)
    registerHTTPSpeechRoutes(
        on: router,
        configuration: configuration,
        host: host,
    )
    registerHTTPGenerationRoutes(on: router, host: host)
    registerHTTPPlaybackRoutes(on: router, host: host)
    registerHTTPRequestRoutes(on: router, host: host)
}
