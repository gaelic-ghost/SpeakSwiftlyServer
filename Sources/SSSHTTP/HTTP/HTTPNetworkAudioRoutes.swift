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
        let response: NetworkAudioReceiverSelectionResponse
        if let destinationID = payload.destinationID {
            response = try await host.selectNetworkAudioDestination(id: destinationID)
        } else if let endpoint = payload.endpoint?.endpoint {
            response = try await host.selectNetworkAudioDestination(endpoint: endpoint, name: payload.name)
        } else {
            throw ServerRequestError(
                .badRequest,
                message: "SpeakSwiftlyServer could not select a LAN audio receiver because the request body did not include destination_id or a complete endpoint object.",
            )
        }
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
