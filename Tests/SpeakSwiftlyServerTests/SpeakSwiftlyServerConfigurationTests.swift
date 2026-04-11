import Foundation
import SpeakSwiftlyCore
import Testing
@testable import SpeakSwiftlyServer

// MARK: - Configuration Tests

@Test func configurationLoadsDefaultsAndRejectsInvalidValues() async throws {
    let defaults = try await AppConfig.load(environment: [:])
    #expect(defaults.server.host == "127.0.0.1")
    #expect(defaults.server.port == 7337)
    #expect(defaults.http.host == "127.0.0.1")
    #expect(defaults.http.port == 7337)
    #expect(defaults.http.sseHeartbeatSeconds == 10)
    #expect(defaults.server.sseHeartbeatSeconds == 10)
    #expect(defaults.server.completedJobTTLSeconds == 900)

    let appConfig = try await AppConfig.load(environment: [
        "APP_PORT": "7550",
        "APP_HTTP_ENABLED": "false",
        "APP_HTTP_HOST": "0.0.0.0",
        "APP_HTTP_PORT": "7444",
        "APP_HTTP_SSE_HEARTBEAT_SECONDS": "2.5",
        "APP_MCP_ENABLED": "true",
        "APP_MCP_PATH": "/assistant/mcp",
        "APP_MCP_SERVER_NAME": "speak-swiftly-agent",
        "APP_MCP_TITLE": "SpeakSwiftly Server MCP",
    ])
    #expect(appConfig.server.port == 7550)
    #expect(appConfig.http.enabled == false)
    #expect(appConfig.http.host == "0.0.0.0")
    #expect(appConfig.http.port == 7444)
    #expect(appConfig.http.sseHeartbeatSeconds == 2.5)
    #expect(appConfig.mcp.enabled == true)
    #expect(appConfig.mcp.path == "/assistant/mcp")
    #expect(appConfig.mcp.serverName == "speak-swiftly-agent")
    #expect(appConfig.mcp.title == "SpeakSwiftly Server MCP")

    let configDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let yamlURL = configDirectory.appendingPathComponent("server.yaml")
    try """
    app:
      name: yaml-server
      environment: staging
      host: 192.168.1.10
      port: 7555
      sseHeartbeatSeconds: 4
      completedJobTTLSeconds: 30
      completedJobMaxCount: 25
      jobPruneIntervalSeconds: 5
      http:
        enabled: false
        host: 0.0.0.0
        port: 7666
        sseHeartbeatSeconds: 1.5
      mcp:
        enabled: true
        path: /assistant/mcp
        serverName: yaml-mcp
        title: YAML MCP
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let yamlConfig = try await AppConfig.load(environment: [
        "APP_CONFIG_FILE": yamlURL.path,
        "APP_HTTP_PORT": "7777",
    ])
    #expect(yamlConfig.server.name == "yaml-server")
    #expect(yamlConfig.server.environment == "staging")
    #expect(yamlConfig.server.host == "192.168.1.10")
    #expect(yamlConfig.server.port == 7555)
    #expect(yamlConfig.http.enabled == false)
    #expect(yamlConfig.http.host == "0.0.0.0")
    #expect(yamlConfig.http.port == 7777)
    #expect(yamlConfig.mcp.enabled == true)
    #expect(yamlConfig.mcp.path == "/assistant/mcp")
    #expect(yamlConfig.mcp.serverName == "yaml-mcp")
    #expect(yamlConfig.mcp.title == "YAML MCP")

    let inheritedTransportConfig = try await AppConfig.load(environment: [
        "APP_HOST": "0.0.0.0",
        "APP_PORT": "7999",
        "APP_SSE_HEARTBEAT_SECONDS": "3.25",
    ])
    #expect(inheritedTransportConfig.server.host == "0.0.0.0")
    #expect(inheritedTransportConfig.server.port == 7999)
    #expect(inheritedTransportConfig.server.sseHeartbeatSeconds == 3.25)
    #expect(inheritedTransportConfig.http.host == "0.0.0.0")
    #expect(inheritedTransportConfig.http.port == 7999)
    #expect(inheritedTransportConfig.http.sseHeartbeatSeconds == 3.25)

    do {
        _ = try await AppConfig.load(environment: ["APP_PORT": "zero"])
        Issue.record("Expected invalid APP_PORT to throw a configuration error.")
    } catch let error as ServerConfigurationError {
        #expect(error.message.contains("APP_PORT"))
    }

    do {
        _ = try await AppConfig.load(environment: ["APP_HTTP_PORT": "zero"])
        Issue.record("Expected invalid APP_HTTP_PORT to throw a configuration error.")
    } catch let error as ServerConfigurationError {
        #expect(error.message.contains("APP_HTTP_PORT"))
    }
}

@Test func configStoreLoadsYamlAndExposesReloadingServiceWhenConfigFileIsSet() async throws {
    let configDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let yamlURL = configDirectory.appendingPathComponent("server.yaml")
    try """
    app:
      name: initial-server
      environment: development
      host: 127.0.0.1
      port: 7337
      sseHeartbeatSeconds: 4
      completedJobTTLSeconds: 30
      completedJobMaxCount: 25
      jobPruneIntervalSeconds: 5
      http:
        enabled: true
        host: 127.0.0.1
        port: 7337
        sseHeartbeatSeconds: 4
      mcp:
        enabled: false
        path: /mcp
        serverName: speak-swiftly-mcp
        title: SpeakSwiftly
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let store = try await ConfigStore(environment: [
        "APP_CONFIG_FILE": yamlURL.path,
        "APP_CONFIG_RELOAD_INTERVAL_SECONDS": "0.05",
    ])
    #expect(store.services.count == 1)

    let initialConfig = try store.loadAppConfig()
    #expect(initialConfig.server.name == "initial-server")
    #expect(initialConfig.server.completedJobMaxCount == 25)
}

@Test func hostReportsAndPersistsRuntimeConfigurationState() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: configurationStore,
        state: state
    )

    let initialSnapshot = await host.runtimeConfigurationSnapshot()
    #expect(initialSnapshot.activeRuntimeSpeechBackend == "qwen3")
    #expect(initialSnapshot.nextRuntimeSpeechBackend == "qwen3")
    #expect(initialSnapshot.activeDefaultVoiceProfileName == nil)
    #expect(initialSnapshot.nextDefaultVoiceProfileName == nil)
    #expect(initialSnapshot.persistedConfigurationExists == false)
    #expect(initialSnapshot.persistedConfigurationState == "missing")
    #expect(initialSnapshot.persistedConfigurationWillAffectNextRuntimeStart == true)

    let updatedSnapshot = try await host.saveRuntimeConfiguration(speechBackend: .marvis)
    #expect(updatedSnapshot.activeRuntimeSpeechBackend == "qwen3")
    #expect(updatedSnapshot.nextRuntimeSpeechBackend == "marvis")
    #expect(updatedSnapshot.activeDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.nextDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.persistedSpeechBackend == "marvis")
    #expect(updatedSnapshot.persistedDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.persistedConfigurationExists == true)
    #expect(updatedSnapshot.persistedConfigurationState == "loaded")
    #expect(updatedSnapshot.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == updatedSnapshot)

    let hostStateSnapshot = await host.hostStateSnapshot()
    #expect(hostStateSnapshot.runtimeConfiguration == updatedSnapshot)
}

@Test func hostReportsLiveBackendSwitchWithoutMutatingNextStartupConfiguration() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { ServerState() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeConfigurationStore: configurationStore,
        state: state
    )

    let response = try await host.switchSpeechBackend(to: .marvis)
    #expect(response.speechBackend == "marvis")

    let runtimeConfiguration = await host.runtimeConfigurationSnapshot()
    #expect(runtimeConfiguration.activeRuntimeSpeechBackend == "marvis")
    #expect(runtimeConfiguration.nextRuntimeSpeechBackend == "qwen3")
    #expect(runtimeConfiguration.activeDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.nextDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.persistedSpeechBackend == nil)
    #expect(runtimeConfiguration.persistedDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == runtimeConfiguration)
}

@Test func hostPersistsDefaultVoiceProfileSelectionAcrossRestart() async throws {
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3
    )

    do {
        let runtime = MockRuntime()
        let state = await MainActor.run { ServerState() }
        let host = ServerHost(
            configuration: testConfiguration(defaultVoiceProfileName: "configured-default"),
            runtime: runtime,
            runtimeConfigurationStore: configurationStore,
            state: state
        )

        let selectedProfileName = try await host.setDefaultVoiceProfileName("persisted-default")
        #expect(selectedProfileName == "persisted-default")

        let runtimeConfiguration = await host.runtimeConfigurationSnapshot()
        #expect(runtimeConfiguration.activeDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.nextDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.persistedDefaultVoiceProfileName == "persisted-default")
    }

    do {
        let runtime = MockRuntime()
        let state = await MainActor.run { ServerState() }
        let restartedHost = ServerHost(
            configuration: testConfiguration(defaultVoiceProfileName: "configured-default"),
            runtime: runtime,
            runtimeConfigurationStore: configurationStore,
            state: state
        )

        #expect(await restartedHost.defaultVoiceProfileName() == "persisted-default")
        let runtimeConfiguration = await restartedHost.runtimeConfigurationSnapshot()
        #expect(runtimeConfiguration.activeDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.nextDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.persistedDefaultVoiceProfileName == "persisted-default")
    }
}
