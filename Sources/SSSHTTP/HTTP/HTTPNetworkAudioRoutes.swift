import Hummingbird
import SSSCore

package func registerHTTPNetworkAudioRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("network-audio/destinations") { _, _ -> [NetworkAudioDestinationSnapshot] in
        await host.networkAudioDestinationSnapshots()
    }

    router.get("network-audio/selection") { _, _ -> Response in
        try await encodeJSONResponse(host.networkAudioReceiverSelectionSnapshot(), status: .ok)
    }

    router.put("network-audio/selection") { request, context -> Response in
        let payload = try await request.decode(as: NetworkAudioReceiverSelectionPayload.self, context: context)
        let response = try await host.selectNetworkAudioDestination(id: payload.destinationID)
        return try encodeJSONResponse(response, status: .ok)
    }

    router.delete("network-audio/selection") { _, _ -> Response in
        let response = await host.clearNetworkAudioDestinationSelection()
        return try encodeJSONResponse(response, status: .ok)
    }

    router.post("network-audio/selection/smoke-test") { _, _ -> Response in
        let response = try await host.smokeTestSelectedNetworkAudioDestination()
        return try encodeJSONResponse(response, status: .ok)
    }
}
