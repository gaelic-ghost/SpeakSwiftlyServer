import Foundation
import HTTPTypes
import Hummingbird
import MCP
import NIOCore

enum MCPHTTPBridge {
    static func makeHTTPRequest(from request: Request) async throws -> MCP.HTTPRequest {
        let bodyBuffer = try await request.body.collect(upTo: 10 * 1024 * 1024)
        let bodyData = Data(bodyBuffer.readableBytesView)

        var headers = [String: String]()
        for field in request.headers {
            headers[field.name.rawName] = field.value
        }

        return MCP.HTTPRequest(
            method: request.method.rawValue,
            headers: headers,
            body: bodyData.isEmpty ? nil : bodyData,
            path: request.uri.path,
        )
    }

    static func makeResponse(from response: MCP.HTTPResponse) throws -> Response {
        var headers = HTTPFields()
        for (name, value) in response.headers {
            guard let headerName = HTTPField.Name(name) else { continue }

            headers[headerName] = value
        }

        switch response {
            case .accepted:
                return Response(status: .accepted, headers: headers)

            case .ok:
                return Response(status: .ok, headers: headers)

            case let .data(data, _):
                return Response(
                    status: .ok,
                    headers: headers,
                    body: ResponseBody(byteBuffer: byteBuffer(from: data)),
                )

            case let .stream(stream, _):
                let body = ResponseBody { writer in
                    for try await chunk in stream {
                        try await writer.write(byteBuffer(from: chunk))
                    }
                    try await writer.finish(nil)
                }
                return Response(status: .ok, headers: headers, body: body)

            case .error:
                return Response(
                    status: .init(code: response.statusCode),
                    headers: headers,
                    body: ResponseBody(byteBuffer: byteBuffer(from: response.bodyData ?? Data())),
                )
        }
    }

    static func byteBuffer(from data: Data) -> ByteBuffer {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        return buffer
    }
}
