import Hummingbird

// MARK: - Runtime Routes

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

    router.get("runtime/host") { _, _ -> StatusSnapshot in
        await host.statusSnapshot()
    }

    router.get("runtime/status") { _, _ -> RuntimeStatusResponse in
        try await host.runtimeStatus()
    }

    router.get("runtime/configuration") { _, _ -> RuntimeConfigurationSnapshot in
        await host.runtimeConfigurationSnapshot()
    }

    router.put("runtime/configuration") { request, context -> RuntimeConfigurationSnapshot in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        return try await host.saveRuntimeConfiguration(speechBackend: payload.speechBackendModel())
    }

    router.post("runtime/backend") { request, context -> RuntimeBackendResponse in
        let payload = try await request.decode(as: RuntimeConfigurationUpdatePayload.self, context: context)
        return try await host.switchSpeechBackend(to: payload.speechBackendModel())
    }

    router.post("runtime/models/reload") { _, _ -> RuntimeStatusResponse in
        try await host.reloadModels()
    }

    router.post("runtime/models/unload") { _, _ -> RuntimeStatusResponse in
        try await host.unloadModels()
    }
}
