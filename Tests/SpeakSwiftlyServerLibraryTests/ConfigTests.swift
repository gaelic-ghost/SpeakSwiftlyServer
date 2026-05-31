import Foundation
import SpeakSwiftly
@testable import SpeakSwiftlyServer
import Testing

// MARK: - Configuration Tests

@Test func `configuration loads defaults and rejects invalid values`() async throws {
    let defaults = try await AppConfig.load(environment: [:])
    #expect(defaults.server.host == "127.0.0.1")
    #expect(defaults.server.port == 7338)
    #expect(defaults.http.host == "127.0.0.1")
    #expect(defaults.http.port == 7338)
    #expect(defaults.http.sseHeartbeatSeconds == 10)
    #expect(defaults.server.sseHeartbeatSeconds == 10)
    #expect(defaults.server.completedJobTTLSeconds == 900)

    let launchAgentDefaults = try await AppConfig.load(
        environment: [:],
        defaultProfile: .launchAgent,
    )
    #expect(launchAgentDefaults.server.port == 7337)
    #expect(launchAgentDefaults.http.port == 7337)

    let embeddedDefaults = try await AppConfig.load(
        environment: [:],
        defaultProfile: .embeddedSession,
    )
    #expect(embeddedDefaults.server.port == 7339)
    #expect(embeddedDefaults.http.port == 7339)

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
      runtime:
        speechBackend: marvis
        duckMediaVolume: a_little
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
    #expect(yamlConfig.runtime.speechBackend == .marvis)
    #expect(yamlConfig.runtime.duckMediaVolume == .aLittle)
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

@Test func `server config store loads yaml and exposes reloading service when config file is set`() async throws {
    let configDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
    let yamlURL = configDirectory.appendingPathComponent("server.yaml")
    try """
    app:
      name: initial-server
      environment: development
      host: 127.0.0.1
      port: 7338
      sseHeartbeatSeconds: 4
      completedJobTTLSeconds: 30
      completedJobMaxCount: 25
      jobPruneIntervalSeconds: 5
      http:
        enabled: true
        host: 127.0.0.1
        port: 7338
        sseHeartbeatSeconds: 4
      mcp:
        enabled: false
        path: /mcp
        serverName: speak-swiftly-mcp
        title: SpeakSwiftly
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let store = try await ServerConfigStore(environment: [
        "APP_CONFIG_FILE": yamlURL.path,
        "APP_CONFIG_RELOAD_INTERVAL_SECONDS": "0.05",
    ])
    #expect(store.services.count == 1)

    let initialConfig = try store.loadAppConfig()
    #expect(initialConfig.server.name == "initial-server")
    #expect(initialConfig.server.completedJobMaxCount == 25)
}

@Test func `server config store loads application support yaml path with spaces directly`() async throws {
    let applicationSupportDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("Application Support/SpeakSwiftlyServer", isDirectory: true)
    try FileManager.default.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
    let yamlURL = applicationSupportDirectory.appendingPathComponent("server.yaml", isDirectory: false)
    try """
    app:
      name: application-support-server
      environment: development
      host: 127.0.0.1
      port: 7337
      sseHeartbeatSeconds: 10
      completedJobTTLSeconds: 900
      completedJobMaxCount: 200
      jobPruneIntervalSeconds: 60
      http:
        enabled: true
        host: 127.0.0.1
        port: 7337
        sseHeartbeatSeconds: 10
      mcp:
        enabled: true
        path: /mcp
        serverName: speak-swiftly-mcp
        title: SpeakSwiftly
    """.write(to: yamlURL, atomically: true, encoding: .utf8)

    let config = try await AppConfig.load(environment: ["APP_CONFIG_FILE": yamlURL.path])

    #expect(yamlURL.path.contains("Application Support"))
    #expect(config.server.name == "application-support-server")
    #expect(config.server.port == 7337)
    #expect(config.http.enabled)
    #expect(config.mcp.enabled)
}

@Test func `host reports and persists runtime configuration state`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { EmbeddedServer() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: configurationStore,
        state: state,
    )

    let initialSnapshot = await host.runtimeConfigurationSnapshot()
    #expect(initialSnapshot.activeRuntimeSpeechBackend == "qwen3_smol")
    #expect(initialSnapshot.nextRuntimeSpeechBackend == "qwen3_smol")
    #expect(initialSnapshot.activeDuckMediaVolume == "off")
    #expect(initialSnapshot.nextDuckMediaVolume == "off")
    #expect(initialSnapshot.activeDefaultVoiceProfileName == nil)
    #expect(initialSnapshot.nextDefaultVoiceProfileName == nil)
    #expect(initialSnapshot.persistedDuckMediaVolume == nil)
    #expect(initialSnapshot.persistedConfigurationExists == false)
    #expect(initialSnapshot.persistedConfigurationState == "missing")
    #expect(initialSnapshot.persistedConfigurationWillAffectNextRuntimeStart == true)

    let updatedSnapshot = try await host.saveRuntimeConfiguration(
        speechBackend: .marvis,
        duckMediaVolume: .aLot,
    )
    #expect(updatedSnapshot.activeRuntimeSpeechBackend == "qwen3_smol")
    #expect(updatedSnapshot.nextRuntimeSpeechBackend == "marvis")
    #expect(updatedSnapshot.activeDuckMediaVolume == "off")
    #expect(updatedSnapshot.nextDuckMediaVolume == "a_lot")
    #expect(updatedSnapshot.activeDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.nextDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.persistedSpeechBackend == "marvis")
    #expect(updatedSnapshot.persistedDuckMediaVolume == "a_lot")
    #expect(updatedSnapshot.persistedDefaultVoiceProfileName == nil)
    #expect(updatedSnapshot.persistedConfigurationExists == true)
    #expect(updatedSnapshot.persistedConfigurationState == "loaded")
    #expect(updatedSnapshot.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == updatedSnapshot)

    let hostStateSnapshot = await host.hostStateSnapshot()
    #expect(hostStateSnapshot.runtimeConfiguration == updatedSnapshot)
}

@Test func `host reports live backend switch without mutating next startup configuration`() async throws {
    let runtime = MockRuntime()
    let state = await MainActor.run { EmbeddedServer() }
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )
    let host = ServerHost(
        configuration: testConfiguration(),
        runtime: runtime,
        runtimeStartupConfigurationStore: configurationStore,
        state: state,
    )

    let response = try await host.switchSpeechBackend(to: .marvis)
    #expect(response.speechBackend == "marvis")

    let runtimeConfiguration = await host.runtimeConfigurationSnapshot()
    #expect(runtimeConfiguration.activeRuntimeSpeechBackend == "marvis")
    #expect(runtimeConfiguration.nextRuntimeSpeechBackend == "qwen3_smol")
    #expect(runtimeConfiguration.activeDuckMediaVolume == "off")
    #expect(runtimeConfiguration.nextDuckMediaVolume == "off")
    #expect(runtimeConfiguration.activeDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.nextDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.persistedSpeechBackend == nil)
    #expect(runtimeConfiguration.persistedDuckMediaVolume == nil)
    #expect(runtimeConfiguration.persistedDefaultVoiceProfileName == nil)
    #expect(runtimeConfiguration.activeRuntimeMatchesNextRuntime == false)

    let statusSnapshot = await host.statusSnapshot()
    #expect(statusSnapshot.runtimeConfiguration == runtimeConfiguration)
}

@Test func `host persists default voice profile selection across restart`() async throws {
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationStore = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": profileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )

    do {
        let runtime = MockRuntime()
        let state = await MainActor.run { EmbeddedServer() }
        let host = ServerHost(
            configuration: testConfiguration(defaultVoiceProfileName: "configured-default"),
            runtime: runtime,
            runtimeStartupConfigurationStore: configurationStore,
            state: state,
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
        let state = await MainActor.run { EmbeddedServer() }
        let restartedHost = ServerHost(
            configuration: testConfiguration(defaultVoiceProfileName: "configured-default"),
            runtime: runtime,
            runtimeStartupConfigurationStore: configurationStore,
            state: state,
        )

        #expect(await restartedHost.defaultVoiceProfileName() == "persisted-default")
        let runtimeConfiguration = await restartedHost.runtimeConfigurationSnapshot()
        #expect(runtimeConfiguration.activeDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.nextDefaultVoiceProfileName == "persisted-default")
        #expect(runtimeConfiguration.persistedDefaultVoiceProfileName == "persisted-default")
    }
}

@Test func `runtime startup configuration store reports invalid persisted configuration`() throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let configurationURL = runtimeProfileRootURL
        .deletingLastPathComponent()
        .appendingPathComponent("server.yaml", isDirectory: false)
    try FileManager.default.createDirectory(
        at: configurationURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
    )
    try """
    { this is not valid yaml
    """.write(to: configurationURL, atomically: true, encoding: .utf8)

    let store = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )

    let snapshot = store.snapshot()
    #expect(snapshot.activeRuntimeSpeechBackend == "qwen3_smol")
    #expect(snapshot.nextRuntimeSpeechBackend == "qwen3_smol")
    #expect(snapshot.activeDuckMediaVolume == "off")
    #expect(snapshot.nextDuckMediaVolume == "off")
    #expect(snapshot.persistedConfigurationExists == true)
    #expect(snapshot.persistedConfigurationState == "invalid")
    #expect(snapshot.persistedSpeechBackend == nil)
    #expect(snapshot.persistedDuckMediaVolume == nil)
    #expect(snapshot.persistedDefaultVoiceProfileName == nil)
    #expect(snapshot.persistedConfigurationError?.contains("server.yaml") == true)
    #expect(snapshot.persistedConfigurationError?.contains("Likely cause") == true)
}

@Test func `runtime startup configuration store environment override beats persisted backend`() throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(
        environment: [
            "SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path,
            "SPEAKSWIFTLY_SPEECH_BACKEND": "marvis",
        ],
        activeRuntimeSpeechBackend: .marvis,
    )

    _ = try store.saveDefaultVoiceProfileName("persisted-femme")
    _ = try store.save(speechBackend: .qwen3_smol, duckMediaVolume: .aLittle)

    let snapshot = store.snapshot()
    #expect(snapshot.activeRuntimeSpeechBackend == "marvis")
    #expect(snapshot.nextRuntimeSpeechBackend == "marvis")
    #expect(snapshot.environmentSpeechBackendOverride == "marvis")
    #expect(snapshot.persistedSpeechBackend == "qwen3_smol")
    #expect(snapshot.activeDuckMediaVolume == "a_little")
    #expect(snapshot.nextDuckMediaVolume == "a_little")
    #expect(snapshot.persistedDuckMediaVolume == "a_little")
    #expect(snapshot.persistedDefaultVoiceProfileName == "persisted-femme")
    #expect(snapshot.nextDefaultVoiceProfileName == "persisted-femme")
    #expect(snapshot.persistedConfigurationState == "loaded")
    #expect(snapshot.persistedConfigurationWillAffectNextRuntimeStart == false)
    #expect(snapshot.activeRuntimeMatchesNextRuntime == true)
}

@Test func `runtime startup configuration store preserves explicit qwen backend`() throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )

    let snapshot = try store.save(
        speechBackend: .qwen3_smol_6bit,
        duckMediaVolume: .default,
    )

    #expect(snapshot.nextRuntimeSpeechBackend == "qwen3_smol_6bit")
    #expect(snapshot.activeDuckMediaVolume == "default")
    #expect(snapshot.nextDuckMediaVolume == "default")
    #expect(snapshot.persistedSpeechBackend == "qwen3_smol_6bit")
    #expect(snapshot.persistedDuckMediaVolume == "default")
}

@Test func `runtime startup configuration store reports duck only changes as pending restart`() throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
        activeRuntimeSpeechBackend: .qwen3_smol,
    )

    let snapshot = try store.save(
        speechBackend: .qwen3_smol,
        duckMediaVolume: .default,
        activeRuntimeSpeechBackend: .qwen3_smol,
        activeDuckMediaVolume: .off,
    )

    #expect(snapshot.activeRuntimeSpeechBackend == "qwen3_smol")
    #expect(snapshot.nextRuntimeSpeechBackend == "qwen3_smol")
    #expect(snapshot.activeDuckMediaVolume == "off")
    #expect(snapshot.nextDuckMediaVolume == "default")
    #expect(snapshot.persistedDuckMediaVolume == "default")
    #expect(snapshot.activeRuntimeMatchesNextRuntime == false)
}

@Test func `runtime startup configuration store normalizes blank default voice profile name`() throws {
    let runtimeProfileRootURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("profiles", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(
        environment: ["SPEAKSWIFTLY_PROFILE_ROOT": runtimeProfileRootURL.path],
    )

    let snapshot = try store.saveDefaultVoiceProfileName("   \n\t  ")
    #expect(snapshot.activeDefaultVoiceProfileName == nil)
    #expect(snapshot.nextDefaultVoiceProfileName == nil)
    #expect(snapshot.persistedDefaultVoiceProfileName == nil)
    #expect(snapshot.persistedConfigurationExists == true)
    #expect(snapshot.persistedConfigurationState == "loaded")
}

@Test func `runtime startup configuration includes bundled system profile resources`() {
    let configuration = RuntimeStartupConfiguration(
        speechBackend: .qwen3_smol,
        duckMediaVolume: .aLittle,
        defaultVoiceProfileName: nil,
    )
    .speakSwiftlyConfiguration()

    #expect(configuration.duckMediaVolume == .aLittle)
    #expect(configuration.systemProfileResourceRoots.count == 1)
    #expect(configuration.systemProfileResourceRoots.first?.lastPathComponent == "profiles")
    #expect(configuration.systemProfileResourceRoots.first?.deletingLastPathComponent().lastPathComponent == "SystemProfiles")
}

@Test func `bundled system profile resources include default voices`() throws {
    let configuration = RuntimeStartupConfiguration(
        speechBackend: .qwen3_smol,
        duckMediaVolume: .off,
        defaultVoiceProfileName: nil,
    )
    .speakSwiftlyConfiguration()
    let resourceRoot = try #require(configuration.systemProfileResourceRoots.first)

    let expectedProfiles = [
        "swift-signal": "swift.signal",
        "swift-anchor": "swift.anchor",
    ]

    for (profileName, seedID) in expectedProfiles {
        let profileDirectoryURL = resourceRoot.appendingPathComponent(profileName, isDirectory: true)
        let manifestURL = profileDirectoryURL
            .appendingPathComponent("profile.json", isDirectory: false)
        let referenceURL = profileDirectoryURL.appendingPathComponent("reference.wav", isDirectory: false)
        let data = try Data(contentsOf: manifestURL)
        let manifest = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let seed = try #require(manifest["seed"] as? [String: Any])

        #expect(manifest["author"] as? String == "system")
        #expect(manifest["profileName"] as? String == profileName)
        #expect(seed["seedID"] as? String == seedID)
        #expect(FileManager.default.fileExists(atPath: referenceURL.path))
    }

    let lockURL = resourceRoot.appendingPathComponent(".profile-store.lock", isDirectory: false)
    #expect(!FileManager.default.fileExists(atPath: lockURL.path))
}

@Test func `runtime startup configuration resolves profile root to broader SpeakSwiftly state root`() {
    let profileRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("speakswiftly-runtime/profiles", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(profileRootURL: profileRootURL)

    #expect(store.runtimeStateRootURL() == profileRootURL.deletingLastPathComponent())
    #expect(store.profileStoreRootURL() == profileRootURL)
}

@Test func `runtime startup configuration leaves non-profiles state root paths unchanged`() {
    let runtimeRootURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("SpeakSwiftlyRuntime", isDirectory: true)
    let store = RuntimeStartupConfigurationStore(profileRootURL: runtimeRootURL)

    #expect(store.runtimeStateRootURL() == runtimeRootURL)
    #expect(store.profileStoreRootURL() == runtimeRootURL.appendingPathComponent("profiles", isDirectory: true))
}
