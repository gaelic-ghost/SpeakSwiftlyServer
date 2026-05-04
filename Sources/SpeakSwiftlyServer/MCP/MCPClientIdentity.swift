import MCP

struct MCPClientInfoSnapshot {
    let name: String
    let title: String?
    let version: String
}

actor MCPClientIdentity {
    private var clientInfo: MCPClientInfoSnapshot?

    func record(_ clientInfo: Client.Info) {
        self.clientInfo = .init(
            name: clientInfo.name,
            title: clientInfo.title,
            version: clientInfo.version,
        )
    }

    func snapshot() -> MCPClientInfoSnapshot? {
        clientInfo
    }
}

func mcpSpeechRequestContextDefaults(
    toolName: String,
    clientInfo: MCPClientInfoSnapshot?,
) -> SpeechRequestContextDefaults {
    var attributes = [
        "surface": "mcp",
        "mcp.tool": toolName,
        "server.app": "SpeakSwiftlyServer",
    ]

    if let clientInfo {
        attributes["mcp.client.name"] = clientInfo.name
        attributes["mcp.client.version"] = clientInfo.version
        if let title = clientInfo.title, !title.isEmpty {
            attributes["mcp.client.title"] = title
        }
    }

    return .init(
        source: "mcp",
        app: mcpAppName(from: clientInfo),
        topic: toolName,
        attributes: attributes,
    )
}

private func mcpAppName(from clientInfo: MCPClientInfoSnapshot?) -> String {
    guard let clientInfo else {
        return "MCP client via SpeakSwiftlyServer"
    }

    let displayName = if let title = clientInfo.title, !title.isEmpty {
        title
    } else {
        clientInfo.name
    }
    return "\(displayName) via SpeakSwiftlyServer"
}
