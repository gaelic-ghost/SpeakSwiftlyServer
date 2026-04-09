import Foundation
import Hummingbird
import HummingbirdTesting
import HTTPTypes
import MCP
import NIOCore
import SpeakSwiftlyCore
import Testing
import TextForSpeech
@testable import SpeakSwiftlyServer

@available(macOS 14, *)
actor EmbeddedSessionLifecycleProbe {
    private var requestStopCallCount = 0
    private var waitUntilStoppedCallCount = 0

    func recordRequestStop() {
        requestStopCallCount += 1
    }

    func recordWaitUntilStopped() {
        waitUntilStoppedCallCount += 1
    }

    func counts() -> (requestStop: Int, waitUntilStopped: Int) {
        (requestStopCallCount, waitUntilStoppedCallCount)
    }
}

func testConfiguration(
    sseHeartbeatSeconds: Double = 0.05,
    completedJobTTLSeconds: Double = 30,
    completedJobMaxCount: Int = 20,
    jobPruneIntervalSeconds: Double = 0.05
) -> ServerConfiguration {
    .init(
        name: "speak-swiftly-server-tests",
        environment: "test",
        host: "127.0.0.1",
        port: 7337,
        sseHeartbeatSeconds: sseHeartbeatSeconds,
        completedJobTTLSeconds: completedJobTTLSeconds,
        completedJobMaxCount: completedJobMaxCount,
        jobPruneIntervalSeconds: jobPruneIntervalSeconds
    )
}

func testHTTPConfig(_ configuration: ServerConfiguration) -> HTTPConfig {
    .init(
        enabled: true,
        host: configuration.host,
        port: configuration.port,
        sseHeartbeatSeconds: configuration.sseHeartbeatSeconds
    )
}

func sampleProfile() -> SpeakSwiftly.ProfileSummary {
    .init(
        profileName: "default",
        vibe: .femme,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        voiceDescription: "Warm and clear",
        sourceText: "A reference voice sample."
    )
}

struct GeneratedFileFixture: Codable {
    let artifactID: String
    let createdAt: Date
    let profileName: String
    let textProfileName: String?
    let sampleRate: Int
    let filePath: String

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case createdAt = "created_at"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case sampleRate = "sample_rate"
        case filePath = "file_path"
    }
}

struct GenerationArtifactFixture: Codable {
    let artifactID: String
    let kind: String
    let createdAt: Date
    let filePath: String
    let sampleRate: Int
    let profileName: String
    let textProfileName: String?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case kind
        case createdAt = "created_at"
        case filePath = "file_path"
        case sampleRate = "sample_rate"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
    }
}

struct GenerationJobItemFixture: Codable {
    let artifactID: String
    let text: String
    let textProfileName: String?
    let textContext: TextForSpeech.Context?
    let sourceFormat: TextForSpeech.SourceFormat?

    enum CodingKeys: String, CodingKey {
        case artifactID = "artifact_id"
        case text
        case textProfileName = "text_profile_name"
        case textContext = "text_context"
        case sourceFormat = "source_format"
    }
}

struct GenerationJobFailureFixture: Codable {
    let code: String
    let message: String
}

struct GenerationJobFixture: Codable {
    let jobID: String
    let jobKind: String
    let createdAt: Date
    let updatedAt: Date
    let profileName: String
    let textProfileName: String?
    let speechBackend: String
    let state: String
    let items: [GenerationJobItemFixture]
    let artifacts: [GenerationArtifactFixture]
    let failure: GenerationJobFailureFixture?
    let startedAt: Date?
    let completedAt: Date?
    let failedAt: Date?
    let expiresAt: Date?
    let retentionPolicy: String

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case jobKind = "job_kind"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case speechBackend = "speech_backend"
        case state
        case items
        case artifacts
        case failure
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case failedAt = "failed_at"
        case expiresAt = "expires_at"
        case retentionPolicy = "retention_policy"
    }
}

struct GeneratedBatchFixture: Codable {
    let batchID: String
    let profileName: String
    let textProfileName: String?
    let speechBackend: String
    let state: String
    let items: [GenerationJobItemFixture]
    let artifacts: [GeneratedFileFixture]
    let failure: GenerationJobFailureFixture?
    let createdAt: Date
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let failedAt: Date?
    let expiresAt: Date?
    let retentionPolicy: String

    enum CodingKeys: String, CodingKey {
        case batchID = "batch_id"
        case profileName = "profile_name"
        case textProfileName = "text_profile_name"
        case speechBackend = "speech_backend"
        case state
        case items
        case artifacts
        case failure
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case failedAt = "failed_at"
        case expiresAt = "expires_at"
        case retentionPolicy = "retention_policy"
    }
}

func fixtureDecode<T: Decodable, Payload: Encodable>(_ payload: Payload, as type: T.Type) throws -> T {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    return try decoder.decode(type, from: encoder.encode(payload))
}

func makeGeneratedFile(
    artifactID: String,
    createdAt: Date,
    profileName: String,
    textProfileName: String?,
    sampleRate: Int,
    filePath: String
) throws -> SpeakSwiftly.GeneratedFile {
    try fixtureDecode(
        GeneratedFileFixture(
            artifactID: artifactID,
            createdAt: createdAt,
            profileName: profileName,
            textProfileName: textProfileName,
            sampleRate: sampleRate,
            filePath: filePath
        ),
        as: SpeakSwiftly.GeneratedFile.self
    )
}

func makeGenerationJob(
    jobID: String,
    jobKind: String,
    createdAt: Date,
    updatedAt: Date,
    profileName: String,
    textProfileName: String?,
    speechBackend: String,
    state: String,
    items: [GenerationJobItemFixture],
    artifacts: [GenerationArtifactFixture],
    failure: GenerationJobFailureFixture? = nil,
    startedAt: Date?,
    completedAt: Date?,
    failedAt: Date?,
    expiresAt: Date?,
    retentionPolicy: String
) throws -> SpeakSwiftly.GenerationJob {
    try fixtureDecode(
        GenerationJobFixture(
            jobID: jobID,
            jobKind: jobKind,
            createdAt: createdAt,
            updatedAt: updatedAt,
            profileName: profileName,
            textProfileName: textProfileName,
            speechBackend: speechBackend,
            state: state,
            items: items,
            artifacts: artifacts,
            failure: failure,
            startedAt: startedAt,
            completedAt: completedAt,
            failedAt: failedAt,
            expiresAt: expiresAt,
            retentionPolicy: retentionPolicy
        ),
        as: SpeakSwiftly.GenerationJob.self
    )
}

func makeGeneratedBatch(
    batchID: String,
    profileName: String,
    textProfileName: String?,
    speechBackend: String,
    state: String,
    items: [GenerationJobItemFixture],
    artifacts: [GeneratedFileFixture],
    failure: GenerationJobFailureFixture? = nil,
    createdAt: Date,
    updatedAt: Date,
    startedAt: Date?,
    completedAt: Date?,
    failedAt: Date?,
    expiresAt: Date?,
    retentionPolicy: String
) throws -> SpeakSwiftly.GeneratedBatch {
    try fixtureDecode(
        GeneratedBatchFixture(
            batchID: batchID,
            profileName: profileName,
            textProfileName: textProfileName,
            speechBackend: speechBackend,
            state: state,
            items: items,
            artifacts: artifacts,
            failure: failure,
            createdAt: createdAt,
            updatedAt: updatedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            failedAt: failedAt,
            expiresAt: expiresAt,
            retentionPolicy: retentionPolicy
        ),
        as: SpeakSwiftly.GeneratedBatch.self
    )
}

@available(macOS 14, *)
func waitUntilReady(_ host: ServerHost) async throws {
    _ = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let (ready, _) = await host.readinessSnapshot()
        return ready ? true : nil
    }
}

@available(macOS 14, *)
func waitForJobSnapshot(_ jobID: String, on host: ServerHost) async throws -> JobSnapshot {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            let snapshot = try await host.jobSnapshot(id: jobID)
            return snapshot.terminalEvent == nil ? nil : snapshot
        } catch {
            return nil
        }
    }
}

@available(macOS 14, *)
func waitUntilJobDisappears(_ jobID: String, on host: ServerHost) async throws {
    let _: Bool = try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        do {
            _ = try await host.jobSnapshot(id: jobID)
            return nil
        } catch {
            return true
        }
    }
}

func waitUntil<T: Sendable>(
    timeout: Duration,
    pollInterval: Duration,
    condition: @escaping @Sendable () async throws -> T?
) async throws -> T {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if let value = try await condition() {
            return value
        }
        try await Task.sleep(for: pollInterval)
    }
    throw TimeoutError()
}

@available(macOS 14, *)
func waitForActiveRequestID(on host: ServerHost) async throws -> String {
    try await waitUntil(timeout: .seconds(1), pollInterval: .milliseconds(10)) {
        let snapshot = try await host.generationQueueSnapshot()
        return snapshot.activeRequest?.id
    }
}

struct TimeoutError: Error {}

extension ServerHost {
    func submitSpeak(
        text: String,
        profileName: String,
        textProfileName: String? = nil,
        normalizationContext: SpeechNormalizationContext? = nil,
        sourceFormat: TextForSpeech.SourceFormat? = nil
    ) async throws -> String {
        try await queueSpeechLive(
            text: text,
            profileName: profileName,
            textProfileName: textProfileName,
            normalizationContext: normalizationContext,
            sourceFormat: sourceFormat
        )
    }

    func submitCreateProfile(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        text: String,
        voiceDescription: String,
        outputPath: String?,
        cwd: String?
    ) async throws -> String {
        try await createVoiceProfileFromDescription(
            profileName: profileName,
            vibe: vibe,
            text: text,
            voiceDescription: voiceDescription,
            outputPath: outputPath,
            cwd: cwd
        )
    }

    func submitCreateClone(
        profileName: String,
        vibe: SpeakSwiftly.Vibe,
        referenceAudioPath: String,
        transcript: String?,
        cwd: String?
    ) async throws -> String {
        try await createVoiceProfileFromAudio(
            profileName: profileName,
            vibe: vibe,
            referenceAudioPath: referenceAudioPath,
            transcript: transcript,
            cwd: cwd
        )
    }

    func submitRemoveProfile(profileName: String) async throws -> String {
        try await submitDeleteVoiceProfile(profileName: profileName)
    }
}

extension JobSnapshot {
    var jobID: String { requestID }
}

func byteBuffer(_ string: String) -> ByteBuffer {
    var buffer = ByteBufferAllocator().buffer(capacity: string.utf8.count)
    buffer.writeString(string)
    return buffer
}

func string(from buffer: ByteBuffer) -> String {
    String(decoding: buffer.readableBytesView, as: UTF8.self)
}

func jsonObject(from buffer: ByteBuffer) throws -> [String: Any] {
    let data = Data(buffer.readableBytesView)
    return try jsonObject(from: data)
}

func jsonObject(from data: Data) throws -> [String: Any] {
    let json = try JSONSerialization.jsonObject(with: data)
    guard let dictionary = json as? [String: Any] else {
        throw JSONError.notDictionary
    }
    return dictionary
}

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

func mcpEnvelope(from buffer: ByteBuffer) throws -> [String: Any] {
    try mcpEnvelope(from: Data(buffer.readableBytesView))
}

func mcpEnvelope(from response: MCP.HTTPResponse) async throws -> [String: Any] {
    switch response {
    case .stream(let stream, _):
        var data = Data()
        for try await chunk in stream {
            data.append(chunk)
        }
        guard data.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP surface returned an empty streaming body for a JSON-RPC request.")
        }
        return try mcpEnvelope(from: data)

    case .data(let data, _):
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
    case .stream(let stream, _):
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
        })
    {
        let payload = dataLine.dropFirst("data: ".count)
        guard payload.isEmpty == false else {
            throw JSONError.emptyBody("The embedded MCP response contained an empty data: payload. Raw body: \(body)")
        }
        return try jsonObject(from: Data(payload.utf8))
    }
    return try jsonObject(from: data)
}

func mcpToolPayload(from envelope: [String: Any]) throws -> [String: Any] {
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
        path: "/mcp"
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
        path: "/mcp"
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
        path: "/mcp"
    )
}

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

func mcpStatusToolRequestJSON() -> String {
    mcpCallToolRequestJSON(name: "status", arguments: [:], id: "status-1")
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
