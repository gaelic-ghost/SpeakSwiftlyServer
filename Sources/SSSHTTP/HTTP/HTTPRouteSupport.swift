import Foundation
import HTTPTypes
import Hummingbird
import NIOCore
import SSSCore

package func buildAcceptedRequestResponse(
    request: Request,
    configuration: HTTPConfig,
    requestID: String,
) throws -> Response {
    try encodeJSONResponse(
        RequestAcceptedResponse(
            requestID: requestID,
            requestURL: absoluteURL(for: request, configuration: configuration, path: "/requests/\(requestID)"),
            eventsURL: absoluteURL(for: request, configuration: configuration, path: "/requests/\(requestID)/events"),
        ),
        status: .accepted,
    )
}

package func absoluteURL(for request: Request, configuration: HTTPConfig, path: String) -> String {
    let scheme = request.head.scheme ?? "http"
    let authority = request.head.authority ?? "\(configuration.host):\(configuration.port)"
    return "\(scheme)://\(authority)\(path)"
}

package func encodeJSONResponse(_ value: some Encodable, status: HTTPResponse.Status) throws -> Response {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    var headers = HTTPFields()
    headers[.contentType] = "application/json; charset=utf-8"
    var buffer = ByteBufferAllocator().buffer(capacity: data.count)
    buffer.writeBytes(data)
    return Response(status: status, headers: headers, body: .init(byteBuffer: buffer))
}
