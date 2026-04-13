import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftly
import Testing
import TextForSpeech
@testable import SpeakSwiftlyServer

// MARK: - MCP Test Helpers

func mcpSessionID(from response: MCP.HTTPResponse) -> String? {
    response.headers.first { $0.key.caseInsensitiveCompare("Mcp-Session-Id") == .orderedSame }?.value
}

func mcpStatusCode(from response: MCP.HTTPResponse) -> Int {
    response.statusCode
}

func mcpInitializeRequestJSON(id: String = "initialize-1") -> String {
    #"{"jsonrpc":"2.0","id":"\#(id)","method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"SpeakSwiftlyServerTests","version":"1.0"}}}"#
}

func mcpInitializedNotificationJSON() -> String {
    #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
}

func mcpListToolsRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"tools-1","method":"tools/list","params":{}}"#
}

func mcpListResourcesRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"resources-1","method":"resources/list","params":{}}"#
}

func mcpListResourceTemplatesRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"resource-templates-1","method":"resources/templates/list","params":{}}"#
}

func mcpListPromptsRequestJSON() -> String {
    #"{"jsonrpc":"2.0","id":"prompts-1","method":"prompts/list","params":{}}"#
}

func mcpRuntimeOverviewToolRequestJSON() -> String {
    mcpCallToolRequestJSON(name: "get_runtime_overview", arguments: [:], id: "runtime-overview-1")
}

func mcpCallToolRequestJSON(
    name: String,
    arguments: [String: String],
    id: String = "tool-1"
) -> String {
    let sortedArguments = arguments
        .sorted { $0.key < $1.key }
        .map { key, value in #""\#(key)":"\#(value)""# }
        .joined(separator: ",")
    return #"{"jsonrpc":"2.0","id":"\#(id)","method":"tools/call","params":{"name":"\#(name)","arguments":{\#(sortedArguments)}}}"#
}

func mcpReadResourceRequestJSON(uri: String) -> String {
    #"{"jsonrpc":"2.0","id":"read-resource-1","method":"resources/read","params":{"uri":"\#(uri)"}}"#
}

func mcpGetPromptRequestJSON(name: String, arguments: [String: String]) -> String {
    let sortedArguments = arguments
        .sorted { $0.key < $1.key }
        .map { key, value in #""\#(key)":"\#(value)""# }
        .joined(separator: ",")
    return #"{"jsonrpc":"2.0","id":"get-prompt-1","method":"prompts/get","params":{"name":"\#(name)","arguments":{\#(sortedArguments)}}}"#
}

func mcpSubscribeResourceRequestJSON(uri: String) -> String {
    #"{"jsonrpc":"2.0","id":"subscribe-resource-1","method":"resources/subscribe","params":{"uri":"\#(uri)"}}"#
}

func nextMCPStreamEnvelope(
    from iterator: inout AsyncThrowingStream<Data, Error>.AsyncIterator
) async throws -> [String: Any] {
    while let chunk = try await iterator.next() {
        let body = String(decoding: chunk, as: UTF8.self)
        if let dataLine = body
            .split(separator: "\n")
            .reversed()
            .first(where: { $0.hasPrefix("data: ") })
        {
            let payload = dataLine.dropFirst("data: ".count)
            if payload.isEmpty {
                return [:]
            }
            return try jsonObject(from: Data(payload.utf8))
        }
    }

    throw JSONError.emptyBody("The embedded MCP standalone stream ended before it delivered a JSON payload.")
}

enum JSONError: Error {
    case notDictionary
    case emptyBody(String)
}
