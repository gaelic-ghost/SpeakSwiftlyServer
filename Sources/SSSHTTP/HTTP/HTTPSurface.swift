import Foundation
import Hummingbird
import ServiceLifecycle
import SSSCore

package func assembleHBApp(
    configuration: HTTPConfig,
    host: ServerHost,
    additionalListeningTransports: [String] = [],
    mountAdditionalRoutes: ((Router<BasicRequestContext>) -> Void)? = nil,
    services: [any Service] = [],
    beforeServerStarts startupProcesses: [@Sendable () async throws -> Void] = [],
) -> Application<Router<BasicRequestContext>.Responder> {
    let router = Router()
    if configuration.enabled {
        registerHTTPRoutes(on: router, configuration: configuration, host: host)
    }
    mountAdditionalRoutes?(router)

    var app = Application(
        router: router,
        configuration: .init(address: .hostname(configuration.host, port: configuration.port)),
        services: services,
        onServerRunning: { _ in
            await markConfiguredTransportsListening(
                configuration: configuration,
                host: host,
                additionalListeningTransports: additionalListeningTransports,
            )
        },
    )

    for startupProcess in startupProcesses {
        app.beforeServerStarts(perform: startupProcess)
    }

    return app
}

package func markConfiguredTransportsListening(
    configuration: HTTPConfig,
    host: ServerHost,
    additionalListeningTransports: [String],
) async {
    if configuration.enabled {
        await host.markTransportListening(name: "http")
    }
    for transportName in additionalListeningTransports where !transportName.isEmpty {
        await host.markTransportListening(name: transportName)
    }
}

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
