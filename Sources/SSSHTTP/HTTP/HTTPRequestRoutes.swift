import HTTPTypes
import Hummingbird
import SSSCore

private func requestCancellationScope(from rawValue: String?) throws -> RequestCancellationScope? {
    guard let rawValue = RequestCancellationScope.normalized(rawValue) else {
        return nil
    }
    guard let scope = RequestCancellationScope(rawValue: rawValue) else {
        throw HTTPError(
            .badRequest,
            message: "Request cancellation scope '\(rawValue)' is not supported. Expected one of: \(RequestCancellationScope.supportedValuesDescription).",
        )
    }

    return scope
}

package func registerHTTPRequestRoutes(
    on router: Router<BasicRequestContext>,
    host: ServerHost,
) {
    router.get("requests") { _, _ -> RequestListResponse in
        await .init(requests: host.jobSnapshots())
    }

    router.get("requests/:request_id") { _, context -> JobSnapshot in
        let requestID = try context.parameters.require("request_id")
        return try await host.jobSnapshot(id: requestID)
    }

    router.get("requests/:request_id/events") { _, context -> Response in
        let requestID = try context.parameters.require("request_id")
        let body = try await ResponseBody(
            asyncSequence: host.sseStream(for: requestID),
        )
        var headers = HTTPFields()
        headers[.contentType] = "text/event-stream"
        headers[.cacheControl] = "no-cache"
        headers[.connection] = "keep-alive"
        return Response(status: .ok, headers: headers, body: body)
    }

    router.delete("requests/:request_id") { request, context -> QueueCancellationResponse in
        let requestID = try context.parameters.require("request_id")
        let scope = try requestCancellationScope(
            from: request.uri.queryParameters["scope"].map(String.init),
        )
        return try await host.cancelQueuedOrActiveRequest(requestID: requestID, scope: scope)
    }
}
