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
        attributes["mcp.client.display_name"] = mcpClientDisplayName(from: clientInfo)
        if let title = clientInfo.title, !title.isEmpty {
            attributes["mcp.client.title"] = title
        }
    }

    return .init(
        source: "mcp",
        topic: toolName,
        attributes: attributes,
    )
}

private func mcpClientDisplayName(from clientInfo: MCPClientInfoSnapshot) -> String {
    let displayName = if let title = clientInfo.title, !title.isEmpty {
        title
    } else {
        clientInfo.name
    }
    return "\(displayName) via SpeakSwiftlyServer"
}
