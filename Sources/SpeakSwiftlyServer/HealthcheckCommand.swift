import Foundation

// MARK: - HealthcheckOptions

public struct HealthcheckOptions: Sendable {
    let baseURL: URL
    let mcpPath: String
    let timeoutSeconds: TimeInterval

    static func parse(arguments: [String]) throws -> HealthcheckOptions {
        var baseURLString = "http://127.0.0.1:7337"
        var mcpPath = "/mcp"
        var timeoutSeconds: TimeInterval = 3
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
                case "--base-url":
                    baseURLString = try LaunchAgentOptions.requireValue(
                        after: arguments,
                        index: index,
                        option: "--base-url",
                    )
                    index += 2

                case "--mcp-path":
                    mcpPath = try LaunchAgentOptions.requireValue(
                        after: arguments,
                        index: index,
                        option: "--mcp-path",
                    )
                    index += 2

                case "--timeout-seconds":
                    let rawValue = try LaunchAgentOptions.requireValue(
                        after: arguments,
                        index: index,
                        option: "--timeout-seconds",
                    )
                    guard let parsedValue = TimeInterval(rawValue), parsedValue > 0 else {
                        throw SpeakSwiftlyServerToolCommandError(
                            "\(speakSwiftlyServerToolName) expected `--timeout-seconds` to be a positive number of seconds, but received '\(rawValue)'.",
                        )
                    }

                    timeoutSeconds = parsedValue
                    index += 2

                default:
                    throw SpeakSwiftlyServerToolCommandError(
                        "\(speakSwiftlyServerToolName) did not recognize healthcheck option '\(arguments[index])'. Run `\(speakSwiftlyServerToolName) help` for supported flags.",
                    )
            }
        }

        guard let baseURL = URL(string: baseURLString) else {
            throw SpeakSwiftlyServerToolCommandError(
                "\(speakSwiftlyServerToolName) could not parse healthcheck base URL '\(baseURLString)'.",
            )
        }

        return .init(
            baseURL: baseURL,
            mcpPath: mcpPath.hasPrefix("/") ? mcpPath : "/\(mcpPath)",
            timeoutSeconds: timeoutSeconds,
        )
    }
}

// MARK: - SpeakSwiftlyServerHealthcheck

struct SpeakSwiftlyServerHealthcheck {
    let options: HealthcheckOptions

    fileprivate static func summary(
        httpHealth: HealthcheckHealthSnapshot,
        hostStatus: HealthcheckHostSnapshot,
        mcpResult: MCPInitializeResult,
    ) -> String {
        let httpTransportState = hostStatus.transports.first { $0.name == "http" }?.state ?? "missing"
        let mcpTransportState = hostStatus.transports.first { $0.name == "mcp" }?.state ?? "missing"

        return """
        SpeakSwiftlyServer healthcheck passed.
        HTTP health: \(httpHealth.status) (server_mode=\(httpHealth.serverMode), worker_stage=\(httpHealth.workerStage), worker_ready=\(httpHealth.workerReady ? "yes" : "no"))
        Host runtime: http=\(httpTransportState), mcp=\(mcpTransportState), default_voice_profile=\(hostStatus.defaultVoiceProfileName ?? "none")
        MCP initialize: ok (protocol_version=\(mcpResult.protocolVersion), session_id=\(mcpResult.sessionID))
        """
    }

    func run() async throws {
        let httpHealth = try await fetchHealth()
        let hostStatus = try await fetchHostStatus()
        let mcpResult = try await initializeMCP()
        print(Self.summary(httpHealth: httpHealth, hostStatus: hostStatus, mcpResult: mcpResult))
    }

    private func fetchHealth() async throws -> HealthcheckHealthSnapshot {
        let response = try await performJSONRequest(
            path: "/healthz",
            method: "GET",
            body: nil,
            responseType: HealthcheckHealthSnapshot.self,
        )
        guard response.statusCode == 200 else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck reached '\(endpointURL(path: "/healthz").absoluteString)', but the service reported HTTP \(response.statusCode) instead of 200. Body: \(response.bodyPreview)",
            )
        }

        return response.value
    }

    private func fetchHostStatus() async throws -> HealthcheckHostSnapshot {
        let response = try await performJSONRequest(
            path: "/runtime/host",
            method: "GET",
            body: nil,
            responseType: HealthcheckHostSnapshot.self,
        )
        guard response.statusCode == 200 else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck reached '\(endpointURL(path: "/runtime/host").absoluteString)', but the service reported HTTP \(response.statusCode) instead of 200. Body: \(response.bodyPreview)",
            )
        }

        return response.value
    }

    private func initializeMCP() async throws -> MCPInitializeResult {
        let requestBody = try JSONSerialization.data(
            withJSONObject: [
                "jsonrpc": "2.0",
                "id": "healthcheck",
                "method": "initialize",
                "params": [
                    "protocolVersion": "2025-11-25",
                    "capabilities": [:],
                    "clientInfo": [
                        "name": "SpeakSwiftlyServerTool healthcheck",
                        "version": "1.0",
                    ],
                ],
            ],
            options: [],
        )

        let response = try await performRawRequest(
            path: options.mcpPath,
            method: "POST",
            body: requestBody,
            contentType: "application/json",
            acceptHeader: "application/json, text/event-stream",
        )

        guard response.statusCode == 200 else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck reached MCP at '\(endpointURL(path: options.mcpPath).absoluteString)', but initialize returned HTTP \(response.statusCode). Body: \(response.bodyPreview)",
            )
        }

        let sessionID = response.httpResponse.value(forHTTPHeaderField: "MCP-Session-Id")
        guard let sessionID, sessionID.isEmpty == false else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer MCP accepted initialize at '\(endpointURL(path: options.mcpPath).absoluteString)', but the response was missing the required MCP-Session-Id header.",
            )
        }

        let payloadData = try extractInitializePayload(from: response)
        let payload = try JSONSerialization.jsonObject(with: payloadData)
        guard
            let json = payload as? [String: Any],
            let result = json["result"] as? [String: Any]
        else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer MCP initialize returned HTTP 200, but the response body did not contain a JSON-RPC result object. Body: \(response.bodyPreview)",
            )
        }
        guard let protocolVersion = result["protocolVersion"] as? String, protocolVersion.isEmpty == false else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer MCP initialize returned HTTP 200 with session '\(sessionID)', but the JSON-RPC result did not include a protocolVersion.",
            )
        }

        return .init(sessionID: sessionID, protocolVersion: protocolVersion)
    }

    private func extractInitializePayload(from response: RawHTTPResponse) throws -> Data {
        if response.httpResponse.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true {
            let bodyText = String(decoding: response.body, as: UTF8.self)
            for line in bodyText.split(separator: "\n") {
                let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmedLine.hasPrefix("data:") else { continue }

                let payload = trimmedLine.dropFirst("data:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                guard payload.isEmpty == false, payload.first == "{" else { continue }

                return Data(payload.utf8)
            }

            throw HealthcheckCommandError(
                "SpeakSwiftlyServer MCP initialize returned an event stream, but the stream did not contain a JSON payload event. Body: \(response.bodyPreview)",
            )
        }

        return response.body
    }

    private func endpointURL(path: String) -> URL {
        let trimmedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return options.baseURL.appending(path: trimmedPath)
    }

    private func performJSONRequest<Response: Decodable>(
        path: String,
        method: String,
        body: Data?,
        responseType: Response.Type,
    ) async throws -> DecodedHTTPResponse<Response> {
        let response = try await performRawRequest(
            path: path,
            method: method,
            body: body,
            contentType: body == nil ? nil : "application/json",
        )

        do {
            let value = try JSONDecoder().decode(Response.self, from: response.body)
            return .init(
                statusCode: response.statusCode,
                value: value,
                bodyPreview: response.bodyPreview,
            )
        } catch {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck could not decode the JSON response from '\(endpointURL(path: path).absoluteString)'. Likely cause: \(error.localizedDescription). Body: \(response.bodyPreview)",
            )
        }
    }

    private func performRawRequest(
        path: String,
        method: String,
        body: Data?,
        contentType: String?,
        acceptHeader: String? = nil,
    ) async throws -> RawHTTPResponse {
        var request = URLRequest(url: endpointURL(path: path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = options.timeoutSeconds
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let acceptHeader {
            request.setValue(acceptHeader, forHTTPHeaderField: "Accept")
        }

        let session = URLSession(configuration: .ephemeral)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck could not reach '\(request.url?.absoluteString ?? path)'. Likely cause: \(error.localizedDescription)",
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw HealthcheckCommandError(
                "SpeakSwiftlyServer healthcheck reached '\(request.url?.absoluteString ?? path)', but the response was not an HTTP response.",
            )
        }

        return .init(httpResponse: httpResponse, body: data)
    }
}

// MARK: - DecodedHTTPResponse

private struct DecodedHTTPResponse<Response> {
    let statusCode: Int
    let value: Response
    let bodyPreview: String
}

// MARK: - RawHTTPResponse

private struct RawHTTPResponse {
    let httpResponse: HTTPURLResponse
    let body: Data

    var statusCode: Int { httpResponse.statusCode }

    var bodyPreview: String {
        let text = String(decoding: body.prefix(400), as: UTF8.self)
        return text.isEmpty ? "<empty>" : text
    }
}

// MARK: - HealthcheckHealthSnapshot

private struct HealthcheckHealthSnapshot: Decodable {
    let status: String
    let serverMode: String
    let workerStage: String
    let workerReady: Bool

    enum CodingKeys: String, CodingKey {
        case status
        case serverMode = "server_mode"
        case workerStage = "worker_stage"
        case workerReady = "worker_ready"
    }
}

// MARK: - HealthcheckHostSnapshot

private struct HealthcheckHostSnapshot: Decodable {
    let defaultVoiceProfileName: String?
    let transports: [HealthcheckTransportSnapshot]

    enum CodingKeys: String, CodingKey {
        case defaultVoiceProfileName = "default_voice_profile_name"
        case transports
    }
}

// MARK: - HealthcheckTransportSnapshot

private struct HealthcheckTransportSnapshot: Decodable {
    let name: String
    let state: String
}

// MARK: - MCPInitializeResult

private struct MCPInitializeResult {
    let sessionID: String
    let protocolVersion: String
}

// MARK: - HealthcheckCommandError

struct HealthcheckCommandError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
