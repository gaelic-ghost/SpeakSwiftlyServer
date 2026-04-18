import Foundation

// MARK: - HealthcheckOptions

package struct HealthcheckOptions {
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
        try await performRequiredJSONRequest(
            path: "/healthz",
            method: "GET",
            body: nil,
            responseType: HealthcheckHealthSnapshot.self,
            expectedStatus: 200,
            failureContext: "SpeakSwiftlyServer healthcheck",
        )
    }

    private func fetchHostStatus() async throws -> HealthcheckHostSnapshot {
        try await performRequiredJSONRequest(
            path: "/runtime/host",
            method: "GET",
            body: nil,
            responseType: HealthcheckHostSnapshot.self,
            expectedStatus: 200,
            failureContext: "SpeakSwiftlyServer healthcheck",
        )
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
