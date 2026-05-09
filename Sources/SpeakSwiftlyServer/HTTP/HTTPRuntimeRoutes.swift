import Hummingbird

func registerHTTPRuntimeRoutes(
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

    router.put("configuration") { request, context -> RuntimeConfigurationSnapshot in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        return try await host.saveRuntimeConfiguration(
            speechBackend: payload.speechBackendModel(),
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
