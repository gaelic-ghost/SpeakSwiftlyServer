package enum ServerHostDefaultSnapshots {
    package static let overview = HostOverviewSnapshot(
        service: "speak-swiftly-server",
        environment: "development",
        defaultVoiceProfileName: nil,
        serverMode: "degraded",
        workerMode: "starting",
        workerStage: "starting",
        workerReady: false,
        startupError: nil,
        profileCacheState: "uninitialized",
        profileCacheWarning: nil,
        profileCount: 0,
        lastProfileRefreshAt: nil,
    )

    package static let generationQueue = QueueStatusSnapshot.empty(queueType: "generation")
    package static let playbackQueue = QueueStatusSnapshot.empty(queueType: "playback")

    package static let playback = PlaybackStatusSnapshot(
        state: "idle",
        activeRequest: nil,
        isStableForConcurrentGeneration: false,
        isRebuffering: false,
        stableBufferedAudioMS: nil,
        stableBufferTargetMS: nil,
    )

    package static let runtimeBackendTransition = RuntimeBackendTransitionSnapshot(
        state: "idle",
        activeSpeechBackend: "qwen3_smol",
        requestedSpeechBackend: nil,
        requestID: nil,
        operation: nil,
        waitingReason: nil,
        submittedAt: nil,
        startedAt: nil,
    )

    package static let runtimeConfiguration = RuntimeConfigurationSnapshot(
        activeRuntimeSpeechBackend: "qwen3_smol",
        nextRuntimeSpeechBackend: "qwen3_smol",
        activeDuckMediaVolume: "off",
        nextDuckMediaVolume: "off",
        activeDefaultVoiceProfileName: nil,
        nextDefaultVoiceProfileName: nil,
        environmentSpeechBackendOverride: nil,
        persistedSpeechBackend: nil,
        persistedDuckMediaVolume: nil,
        persistedDefaultVoiceProfileName: nil,
        profileRootPath: "",
        persistedConfigurationPath: "",
        persistedConfigurationExists: false,
        persistedConfigurationState: "missing",
        persistedConfigurationError: nil,
        persistedConfigurationAppliesOnRestart: true,
        activeRuntimeMatchesNextRuntime: true,
        persistedConfigurationWillAffectNextRuntimeStart: true,
    )

    package static let remoteGeneration = RemoteGenerationStatusSnapshot(
        state: "disabled",
        streamRequestsEnabled: false,
        sharedTokenConfigured: false,
        streamTokenHeaderName: RemoteGenerationConfig.streamTokenHeaderName,
        activeOutboundRequestCount: 0,
        activeStreams: [],
    )

    package static let networkAudioReceiverSelection = NetworkAudioReceiverSelectionSnapshot(
        selectedDestinationID: nil,
        selectedDestination: nil,
        availableDestinationCount: 0,
    )
}
