import Testing

// MARK: - HTTP Workflow Entry Tests

extension HTTPWorkflowE2ETests {
    @Test func `http voice design lane runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runVoiceDesignLane(using: .http)
    }

    @Test func `http clone lane with provided transcript runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runCloneLane(using: .http, transcriptMode: .provided)
    }

    @Test func `http clone lane with inferred transcript runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runCloneLane(using: .http, transcriptMode: .inferred)
    }

    @Test func `http marvis voice design profiles run audible live playback across all vibes`() async throws {
        try await ServerE2E.runMarvisTripletLane(using: .http)
    }

    @Test func `http marvis queued live playback drains in order`() async throws {
        try await ServerE2E.runQueuedMarvisTripletLane(using: .http)
    }

    @Test func `http profile and clone creation resolve relative paths against explicit caller working directory`() async throws {
        try await ServerE2E.runRelativePathProfileAndCloneLane(using: .http)
    }
}

// MARK: - MCP Workflow Entry Tests

extension MCPWorkflowE2ETests {
    @Test func `mcp voice design lane runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runVoiceDesignLane(using: .mcp)
    }

    @Test func `mcp clone lane with provided transcript runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runCloneLane(using: .mcp, transcriptMode: .provided)
    }

    @Test func `mcp clone lane with inferred transcript runs sequential silent and audible coverage`() async throws {
        try await ServerE2E.runCloneLane(using: .mcp, transcriptMode: .inferred)
    }

    @Test func `mcp marvis voice design profiles run audible live playback across all vibes`() async throws {
        try await ServerE2E.runMarvisTripletLane(using: .mcp)
    }

    @Test func `mcp marvis queued live playback drains in order`() async throws {
        try await ServerE2E.runQueuedMarvisTripletLane(using: .mcp)
    }

    @Test func `mcp profile and clone creation resolve relative paths against explicit caller working directory`() async throws {
        try await ServerE2E.runRelativePathProfileAndCloneLane(using: .mcp)
    }
}
