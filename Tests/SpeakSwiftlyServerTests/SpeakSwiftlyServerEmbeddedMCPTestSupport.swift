import Foundation
import HTTPTypes
import HummingbirdTesting
import MCP
import NIOCore
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Embedded MCP Header Helpers

func mcpSessionID(from response: TestResponse) -> String? {
    guard let headerName = HTTPField.Name("Mcp-Session-Id") else {
        return nil
    }

    return response.headers[headerName]
}

func mcpHeaders(sessionID: String) -> HTTPFields {
    var headers = HTTPFields()
    headers[.contentType] = "application/json"
    headers[.accept] = "application/json, text/event-stream"
    if let sessionHeader = HTTPField.Name("Mcp-Session-Id") {
        headers[sessionHeader] = sessionID
    }
    return headers
}

// MARK: - Embedded MCP Envelope Helpers

func mcpEnvelope(from buffer: ByteBuffer) throws -> [String: Any] {
    try mcpEnvelope(from: Data(buffer.readableBytesView))
}

func mcpEnvelope(from response: MCP.HTTPResponse) async throws -> [String: Any] {
    switch response {
        case let .stream(stream, _):
            var data = Data()
            for try await chunk in stream {
                data.append(chunk)
            }
            guard data.isEmpty == false else {
                throw JSONError.emptyBody("The embedded MCP surface returned an empty streaming body for a JSON-RPC request.")
            }

            return try mcpEnvelope(from: data)

        case let .data(data, _):
            guard data.isEmpty == false else {
                throw JSONError.emptyBody("The embedded MCP surface returned an empty data body for a JSON-RPC request.")
            }

            return try mcpEnvelope(from: data)

        case .error:
            let data = response.bodyData ?? Data()
            guard data.isEmpty == false else {
                throw JSONError.emptyBody("The embedded MCP surface returned an empty error body for a JSON-RPC request.")
            }

            return try mcpEnvelope(from: data)

        case .accepted, .ok:
            throw JSONError.emptyBody("The embedded MCP surface returned status \(response.statusCode) without a JSON body.")
    }
}

func drainMCPResponse(_ response: MCP.HTTPResponse) async throws {
    switch response {
        case let .stream(stream, _):
            for try await _ in stream {}
        case .data, .accepted, .ok, .error:
            return
    }
}

func mcpEnvelope(from data: Data) throws -> [String: Any] {
    let body = String(decoding: data, as: UTF8.self)
    if let dataLine = body
        .split(separator: "\n")
        .reversed()
        .first(where: {
            $0.hasPrefix("data: ")
                && $0.dropFirst("data: ".count).isEmpty == false
        }) {
        let payload = dataLine.dropFirst("data: ".count)
        guard payload.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP response contained an empty data: payload. Raw body: \(body)")
        }

        return try jsonObject(from: Data(payload.utf8))
    }
    return try jsonObject(from: data)
}

func mcpToolPayload(from envelope: [String: Any]) throws -> [String: Any] {
    if let error = envelope["error"] as? [String: Any] {
        let message = (error["message"] as? String) ?? "The embedded MCP surface returned a JSON-RPC error without a message."
        throw JSONError.emptyBody("The embedded MCP surface returned a JSON-RPC error instead of a tool payload. Message: \(message)")
    }
    let result = try #require(mcpResultPayload(from: envelope))
    if let structuredContent = result["structuredContent"] as? [String: Any] {
        return structuredContent
    }
    if result["content"] == nil {
        return result
    }
    let content = try #require(result["content"] as? [[String: Any]])
    let text = try #require(content.first?["text"] as? String)
    return try jsonObject(from: Data(text.utf8))
}

func mcpResultPayload(from envelope: [String: Any]) -> [String: Any]? {
    (envelope["result"] as? [String: Any]) ?? envelope
}

// MARK: - Embedded MCP Request Builders

func mcpPOSTRequest(body: String, sessionID: String? = nil) -> MCP.HTTPRequest {
    var headers = [
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    ]
    if let sessionID {
        headers["Mcp-Session-Id"] = sessionID
    }
    return MCP.HTTPRequest(
        method: "POST",
        headers: headers,
        body: Data(body.utf8),
        path: "/mcp",
    )
}

func mcpGETRequest(sessionID: String) -> MCP.HTTPRequest {
    MCP.HTTPRequest(
        method: "GET",
        headers: [
            "Accept": "application/json, text/event-stream",
            "Mcp-Session-Id": sessionID,
        ],
        body: nil,
        path: "/mcp",
    )
}

func mcpDELETERequest(sessionID: String) -> MCP.HTTPRequest {
    MCP.HTTPRequest(
        method: "DELETE",
        headers: [
            "Accept": "application/json, text/event-stream",
            "Mcp-Session-Id": sessionID,
        ],
        body: nil,
        path: "/mcp",
    )
}
