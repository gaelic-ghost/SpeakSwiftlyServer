import Hummingbird
import SSSCore

package func registerHTTPRuntimeRoutes(
    on router: Router<BasicRequestContext>,
    configuration: HTTPConfig,
    host: ServerHost,
) {
    router.get("healthz") { _, _ -> HealthSnapshot in
        await host.healthSnapshot()
    }

    router.get("readyz") { _, _ -> Response in
        let (ready, snapshot) = await host.readinessSnapshot()
        let status: HTTPResponse.Status = ready ? .ok : .serviceUnavailable
        return try encodeJSONResponse(snapshot, status: status)
    }

    router.get("overview") { _, _ -> StatusSnapshot in
        await host.statusSnapshot()
    }

    router.get("status") { _, _ -> RuntimeStatusResponse in
        try await host.runtimeStatus()
    }

    router.get("configuration") { _, _ -> RuntimeConfigurationSnapshot in
        await host.runtimeConfigurationSnapshot()
    }

    router.post("listeners/:listener/enable") { _, context -> Response in
        let listener = try HTTPListenerRuntimeName(pathComponent: context.parameters.require("listener"))
        let snapshot = try await host.enableHTTPListener(listener)
        return try encodeJSONResponse(snapshot, status: .ok)
    }

    router.post("listeners/:listener/disable") { _, context -> Response in
        let listener = try HTTPListenerRuntimeName(pathComponent: context.parameters.require("listener"))
        let snapshot = try await host.disableHTTPListener(listener)
        return try encodeJSONResponse(snapshot, status: .ok)
    }

    router.put("configuration") { request, context -> RuntimeConfigurationSnapshot in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        let currentConfiguration = await host.runtimeConfigurationSnapshot()
        return try await host.saveRuntimeConfiguration(
            speechBackend: payload.speechBackendModel(),
            duckMediaVolume: payload.duckMediaVolumeModel(
                default: RuntimeStartupConfiguration.duckMediaVolume(
                    currentConfiguration.nextDuckMediaVolume,
                    label: "current next_duck_media_volume",
                ),
            ),
        )
    }

    router.post("backend") { request, context -> Response in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        let requestID = try await host.submitSpeechBackendSwitch(to: payload.speechBackendModel())
        return try buildAcceptedRequestResponse(request: request, configuration: configuration, requestID: requestID)
    }

    router.post("models/reload") { _, _ -> RuntimeStatusResponse in
        try await host.reloadModels()
    }

    router.post("models/unload") { _, _ -> RuntimeStatusResponse in
        try await host.unloadModels()
    }
}
