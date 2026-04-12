import Testing

// MARK: - HTTP Workflow Entry Tests

extension SpeakSwiftlyServerE2EHTTPWorkflowEntryTests {
    @Test func httpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runVoiceDesignLane(using: .http)
    }

    @Test func httpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runCloneLane(using: .http, transcriptMode: .provided)
    }

    @Test func httpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runCloneLane(using: .http, transcriptMode: .inferred)
    }

    @Test func httpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await SpeakSwiftlyServerE2ETests.runMarvisTripletLane(using: .http)
    }

    @Test func httpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await SpeakSwiftlyServerE2ETests.runQueuedMarvisTripletLane(using: .http)
    }

    @Test func httpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await SpeakSwiftlyServerE2ETests.runRelativePathProfileAndCloneLane(using: .http)
    }
}

// MARK: - MCP Workflow Entry Tests

extension SpeakSwiftlyServerE2EMCPWorkflowEntryTests {
    @Test func mcpVoiceDesignLaneRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runVoiceDesignLane(using: .mcp)
    }

    @Test func mcpCloneLaneWithProvidedTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runCloneLane(using: .mcp, transcriptMode: .provided)
    }

    @Test func mcpCloneLaneWithInferredTranscriptRunsSequentialSilentAndAudibleCoverage() async throws {
        try await SpeakSwiftlyServerE2ETests.runCloneLane(using: .mcp, transcriptMode: .inferred)
    }

    @Test func mcpMarvisVoiceDesignProfilesRunAudibleLivePlaybackAcrossAllVibes() async throws {
        try await SpeakSwiftlyServerE2ETests.runMarvisTripletLane(using: .mcp)
    }

    @Test func mcpMarvisQueuedLivePlaybackDrainsInOrder() async throws {
        try await SpeakSwiftlyServerE2ETests.runQueuedMarvisTripletLane(using: .mcp)
    }

    @Test func mcpProfileAndCloneCreationResolveRelativePathsAgainstExplicitCallerWorkingDirectory() async throws {
        try await SpeakSwiftlyServerE2ETests.runRelativePathProfileAndCloneLane(using: .mcp)
    }
}
