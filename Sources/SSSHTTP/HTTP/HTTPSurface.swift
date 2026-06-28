import Configuration
import Foundation
import Hummingbird
import NIOCore
import ServiceLifecycle
import SSSCore

package func buildHTTPApplication(
    configuration: HTTPConfig,
    host: ServerHost,
    serverName: String? = nil,
    transportName: String = "http",
    additionalListeningTransports: [String] = [],
    mountAdditionalRoutes: ((Router<BasicRequestContext>) -> Void)? = nil,
    services: [any Service] = [],
    beforeServerStarts startupProcesses: [@Sendable () async throws -> Void] = [],
    onServerRunning: (@Sendable (any Channel) async -> Void)? = nil,
) -> Application<Router<BasicRequestContext>.Responder> {
    let router = Router()
    router.addMiddleware {
        LogRequestsMiddleware(.info)
    }
    if configuration.enabled {
        registerHTTPRoutes(on: router, configuration: configuration, host: host)
        registerHTTPWebUIRoutes(on: router)
    }
    mountAdditionalRoutes?(router)

    var app = Application(
        router: router,
        configuration: applicationConfiguration(
            for: configuration,
            serverName: serverName,
        ),
        services: services,
        onServerRunning: { channel in
            await markConfiguredTransportsListening(
                configuration: configuration,
                host: host,
                primaryTransportName: transportName,
                primaryTransportPort: channel.localAddress?.port ?? configuration.port,
                additionalListeningTransports: additionalListeningTransports,
            )
            await onServerRunning?(channel)
        },
    )

    for startupProcess in startupProcesses {
        app.beforeServerStarts(perform: startupProcess)
    }

    return app
}

private func applicationConfiguration(
    for configuration: HTTPConfig,
    serverName: String?,
) -> ApplicationConfiguration {
    var values: [AbsoluteConfigKey: ConfigValue] = [
        .init(["host"]): .init(stringLiteral: configuration.host),
        .init(["port"]): .init(integerLiteral: configuration.port),
    ]
    if let serverName = serverName?.trimmingCharacters(in: .whitespacesAndNewlines), !serverName.isEmpty {
        values[.init(["serverName"])] = .init(stringLiteral: serverName)
    }

    return ApplicationConfiguration(
        reader: ConfigReader(
            provider: InMemoryProvider(values: values),
        ),
    )
}

package func markConfiguredTransportsListening(
    configuration: HTTPConfig,
    host: ServerHost,
    primaryTransportName: String = "http",
    primaryTransportPort: Int? = nil,
    additionalListeningTransports: [String],
) async {
    if configuration.enabled {
        await host.markTransportListening(
            name: primaryTransportName,
            port: primaryTransportPort ?? configuration.port,
        )
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
    registerHTTPNetworkAudioRoutes(on: router, host: host)
    registerHTTPRequestRoutes(on: router, host: host)
}
