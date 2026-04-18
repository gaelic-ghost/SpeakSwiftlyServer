import Foundation
import HTTPTypes
import MCP

actor MCPSessionRegistry {
    let path: String

    private let configuration: MCPConfig
    private let host: ServerHost
    private var sessions = [String: MCPSession]()
    private var started = false

    init(configuration: MCPConfig, host: ServerHost) {
        path = configuration.path
        self.configuration = configuration
        self.host = host
    }

    func start() {
        started = true
    }

    func stop() async {
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        started = false

        for session in activeSessions {
            await session.stop()
        }
    }

    func handle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        guard started else {
            return .error(
                statusCode: 503,
                .internalError("SpeakSwiftly MCP is not ready yet. Likely cause: the shared MCP surface has not finished starting."),
            )
        }

        if isInitializeRequest(request) {
            return await createSession(for: request)
        }

        guard let sessionID = request.header(HTTPHeaderName.sessionID), sessionID.isEmpty == false else {
            return .error(
                statusCode: 400,
                .invalidRequest(
                    "Bad Request: Session not initialized. Start a new MCP session with an initialize request before sending follow-up requests.",
                ),
            )
        }
        guard let session = sessions[sessionID] else {
            return .error(
                statusCode: 404,
                .invalidRequest(
                    "Not Found: No active MCP session matched '\(sessionID)'. Initialize a new session before retrying this request.",
                ),
                sessionID: sessionID,
            )
        }

        let response = await session.handle(request)
        if request.method.uppercased() == "DELETE", (200...299).contains(response.statusCode) {
            sessions.removeValue(forKey: sessionID)
            await session.stop()
        }
        return response
    }

    private func createSession(for request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        let session = await MCPSession.make(
            configuration: configuration,
            host: host,
        )

        do {
            try await session.start()
        } catch {
            return .error(
                statusCode: 500,
                .internalError(
                    "SpeakSwiftly MCP could not start a new session transport. Likely cause: \(error.localizedDescription)",
                ),
            )
        }

        let response = await session.handle(request)

        guard (200...299).contains(response.statusCode) else {
            await session.stop()
            return response
        }
        guard let sessionID = mcpSessionID(from: response.headers) else {
            await session.stop()
            return .error(
                statusCode: 500,
                .internalError(
                    "SpeakSwiftly MCP accepted an initialize request, but the session response was missing the required MCP-Session-Id header.",
                ),
            )
        }

        sessions[sessionID] = session
        return response
    }

    private func isInitializeRequest(_ request: MCP.HTTPRequest) -> Bool {
        guard request.method.uppercased() == "POST", let body = request.body else {
            return false
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }

        return json["method"] as? String == "initialize"
    }
}

private func mcpSessionID(from headers: [String: String]) -> String? {
    for (name, value) in headers {
        if name.caseInsensitiveCompare(HTTPHeaderName.sessionID) == .orderedSame,
           value.isEmpty == false {
            return value
        }
    }
    return nil
}
