import Testing

// MARK: - HTTP Workflow Entry Tests

extension HTTPWorkflowE2ETests {
    @Test func httpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runVoiceDesignLane(using: .http)
    }

    @Test func httpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runCloneLane(using: .http, transcriptMode: .provided)
    }

    @Test func httpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runCloneLane(using: .http, transcriptMode: .inferred)
    }

    @Test func httpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await ServerE2E.runMarvisTripletLane(using: .http)
    }

    @Test func httpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await ServerE2E.runQueuedMarvisTripletLane(using: .http)
    }

    @Test func httpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await ServerE2E.runRelativePathProfileAndCloneLane(using: .http)
    }
}

// MARK: - MCP Workflow Entry Tests

extension MCPWorkflowE2ETests {
    @Test func mcpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runVoiceDesignLane(using: .mcp)
    }

    @Test func mcpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runCloneLane(using: .mcp, transcriptMode: .provided)
    }

    @Test func mcpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await ServerE2E.runCloneLane(using: .mcp, transcriptMode: .inferred)
    }

    @Test func mcpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await ServerE2E.runMarvisTripletLane(using: .mcp)
    }

    @Test func mcpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await ServerE2E.runQueuedMarvisTripletLane(using: .mcp)
    }

    @Test func mcpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await ServerE2E.runRelativePathProfileAndCloneLane(using: .mcp)
    }
}
