# Source Layout

## Purpose

This document is the maintainer map for the current `SpeakSwiftly 5.x`-aligned source split. The goal is to keep future cleanup, review, and feature work landing in the smallest file family that already owns the relevant concern, instead of letting `ServerHost.swift`, one host extension, or one mixed test file grow back into a monolith.

Historical release artifacts belong under [`docs/releases`](../releases/), and historical debugging
writeups belong under [`docs/investigations`](../investigations/), not beside the active maintainer
maps in this directory.
Public documentation media belongs under [`docs/media`](../media/). Runtime-loaded package resources
belong under `Sources/SpeakSwiftlyServer/Resources` instead, because SwiftPM only exposes target
resources through the target bundle.
The current package-to-server API comparison belongs in
[`speakswiftly-api-coverage-matrix.md`](speakswiftly-api-coverage-matrix.md) so the consumer-facing
`API.md` can stay a stable contract while compatibility notes and dedupe follow-through remain
visible to maintainers. Completed implementation plans belong in
[`implementation-history.md`](implementation-history.md), not as active roadmap files.

## Host Sources

- `Sources/SpeakSwiftlyServer/EmbeddedLifecycleServices.swift`
  Holds the embedded-session readiness gates, shutdown barrier, and the explicit service-owned wrappers for host lifecycle, config watching, MCP lifecycle, and wrapped application runtime.
- `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Holds the actor declaration, stored state, and construction-time setup.
- `Sources/SpeakSwiftlyServer/Host/EmbeddedServer.swift`
  Holds the public observable embedded-server surface that consuming apps own directly.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RuntimeLifecycle.swift`
  Holds runtime start and shutdown, shared update streams, transport lifecycle hooks, configuration-reload handling, and the host health or readiness snapshot surface.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RuntimeControls.swift`
  Holds the public runtime query surface, generated-artifact reads, retained-request reads, and immediate control entrypoints.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Profiles.swift`
  Holds the voice-profile cache reads, default-voice-profile ownership, text-profile queries and mutations, and profile-refresh entrypoints.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Requests.swift`
  Holds request submission, accepted-request shaping, and the handoff into retained host tracking.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RequestEvents.swift`
  Holds SSE replay, request-event consumption, profile-cache reconciliation, worker status handling, and in-memory job retention.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Snapshots.swift`
  Holds publish flow, runtime refresh, derived host snapshots, and live configuration reload helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+EventMapping.swift`
  Holds transport-status helpers, recent-error emission, event mapping, SSE encoding, and shared host-event helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+ControlResponses.swift`
  Holds playback-control settling, optimistic playback snapshots, and immediate runtime-success helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+BuiltInVoices.swift`
  Holds the temporary server-side built-in voice seed installation behavior. This should shrink or disappear when built-in voice seeds move into `SpeakSwiftly`.
- `Sources/SpeakSwiftlyServer/Host/SpeakSwiftlyRuntimeServing.swift`
  Holds the narrow runtime seam and the request-handle wrapper type used by the host.
- `Sources/SpeakSwiftlyServer/Host/SpeakSwiftlyRuntimeAdapter.swift`
  Holds the concrete adapter from the public `SpeakSwiftly.Runtime` actor into that host-owned seam.
- `Sources/SpeakSwiftlyServer/Host/ServerHostLifecycleDelay.swift`
  Holds the host lifecycle delay helper used by shutdown and retry paths.

## Model Sources

- `Sources/SpeakSwiftlyServer/Host/ServerModels.swift`
  Request payloads, shared normalization-format helpers, and transport-owned `SpeakSwiftly.RequestContext` default merging for HTTP and MCP speech requests.
- `Sources/SpeakSwiftlyServer/Host/ProfileModels.swift`
  Voice-profile snapshots plus text-profile and replacement transport models.
- `Sources/SpeakSwiftlyServer/Host/BuiltInVoiceSeedCatalog.swift`
  Package-owned built-in voice seed catalog loading and validation models. This is a temporary server-side home until SpeakSwiftly owns its built-in voice seeds directly.
- `Sources/SpeakSwiftlyServer/Host/QueueResponseModels.swift`
  Queue response envelopes plus health, readiness, and status snapshots. Keep playback state itself in `EmbeddedServerSnapshots.swift` so app state, HTTP, and MCP event payloads do not grow parallel playback snapshot shapes.
- `Sources/SpeakSwiftlyServer/Host/RequestEventModels.swift`
  Job event payloads and retained request snapshots.
- `Sources/SpeakSwiftlyServer/Host/EmbeddedServerSnapshots.swift`
  Shared host-overview, queue, playback, runtime, transport, and error snapshots for app state, HTTP, MCP resources, and request-event payloads.
- `Sources/SpeakSwiftlyServer/Host/ServerHostEvents.swift`
  Host event snapshots and update messages for profile-cache, text-profile, runtime-config, and request-event notifications.

## Operator Sources

- `Sources/SpeakSwiftlyServer/Resources/DefaultVoiceProfiles/catalog.json`
  Holds the package-owned built-in voice seed catalog. Keep this as bundled seed metadata, not as
  user profile storage.
- `Sources/SpeakSwiftlyServer/Resources/default-server.yaml`
  Holds the bundled default server config. The library seeds the persisted Application Support
  config from this resource and stores runtime startup choices in the same YAML document.
- `Sources/SpeakSwiftlyServer/Config/AppConfig.swift` and `ServerConfigStore.swift`
  Hold the typed server config, the `swift-configuration` reader/reload setup, and the fallback
  defaults used when a config file omits values.
- `Sources/SpeakSwiftlyServer/Config/RuntimeStartupConfiguration.swift`
  Holds the typed `app.runtime` startup choices and converts them into `SpeakSwiftly.Configuration`.
- `Sources/SpeakSwiftlyServer/Config/ServerConfigPersistence.swift`
  Owns the library-level default-config seed, load, and save behavior for the persisted YAML file.
  Keep one-off config-provider adapters private inside this file unless another source needs them.
- `Sources/SpeakSwiftlyServer/Config/RuntimeStartupConfigurationStore.swift`
  Bridges persisted `app.runtime` choices into active host snapshots and save operations.
- `Sources/SpeakSwiftlyServer/Config/ServerConfiguration.swift`
  Holds the typed root server configuration and shared server configuration error.
- `Sources/SpeakSwiftlyServer/Config/ServerStorageDefaults.swift`
  Holds the default Application Support paths for the server YAML config and runtime profile root.
- `Sources/SpeakSwiftlyServerTool/HealthcheckCommand.swift` and `HealthcheckCommand+Transport.swift`
  Keep CLI-facing healthcheck option parsing and high-level probe orchestration separate from the low-level HTTP transport helpers and probe response models.
- `Sources/SpeakSwiftlyServerTool/AppManagedInstallLayout.swift`
  Holds the tool-managed per-user filesystem contract for the bundled helper and LaunchAgent install surface, including config, runtime state, plist, and retained log paths.
- `Sources/SpeakSwiftlyServerTool/LaunchAgent/LaunchAgentCommands.swift`
  Holds the top-level command parsing and dispatch for `serve`, `healthcheck`, and `launch-agent`.
- `Sources/SpeakSwiftlyServerTool/LaunchAgent/LaunchAgentOptions.swift` and `LaunchAgentOptions+Installation.swift`
  Keep LaunchAgent option parsing, path resolution, and repository-root discovery separate from property-list rendering, config staging, and install/bootstrap mechanics.
- `Sources/SpeakSwiftlyServerTool/LaunchAgent/LaunchAgentRuntime.swift`
  Holds LaunchAgent status inspection, uninstall flow, launchctl execution, and defaults.

## Test Sources

- `Tests/SpeakSwiftlyServerTests/HTTPWorkflowTests.swift`, `HTTPControlTests.swift`, and `HTTPFailureTests.swift`
  Keep lifecycle-heavy HTTP route coverage split by mainline flows, immediate control paths, and error handling.
- `Tests/SpeakSwiftlyServerTests/MCPCatalogListingTests.swift`, `MCPCatalogRuntimeTests.swift`, `MCPCatalogResourceTests.swift`, and `SpeakSwiftlyServerMCPCatalogSupport.swift`
  Keep MCP catalog, runtime-tool, and resource/prompt coverage separate so the tool surface can grow without another single giant catalog test.
- `Tests/SpeakSwiftlyServerTests/MCPSessionTests.swift` and `MCPSubscriptionTests.swift`
  Keep MCP session behavior and live-subscription behavior independent from catalog assertions.
- `Tests/SpeakSwiftlyServerTests/ConfigTests.swift`, `HostLifecycleTests.swift`, and `HostStateTests.swift`
  Keep configuration, lifecycle, and shared-state coverage independent instead of mixing them into one broad host suite.
- `Tests/SpeakSwiftlyServerTests/MockRuntime.swift` plus the `MockRuntime+*.swift` extensions
  Keep the typed-runtime test double split by text profiles, speech generation, runtime controls, retained artifacts, and test-only control hooks.
- `Tests/SpeakSwiftlyServerE2ETests/E2ESuite.swift`, `E2ETransportSmokeTests.swift`, and the `SpeakSwiftlyServerE2E*Helpers.swift` files
  Keep the live target as one small transport-owned smoke suite that proves server boot, one real HTTP request, one real MCP resource update, and retained request inspection without duplicating SpeakSwiftly's worker-owned E2E matrix here.
- `Tests/SpeakSwiftlyServerE2ETests/E2EHTTPClient.swift`, `E2EMCPClient.swift`, and `E2EMCPEventStream.swift`
  Keep the live HTTP transport, MCP request transport, and MCP SSE stream handling separate so transport bugs do not regrow one giant helper file.
- `Tests/SpeakSwiftlyServerE2ETests/E2EPayloadHelpers.swift` and `E2ETransportWaiters.swift`
  Keep JSON or JSON-RPC decoding, polling waiters, and stored-profile manifest loading split by responsibility instead of mixing transport and payload utilities.

## Transport Sources

- `Sources/SpeakSwiftlyServer/HTTP/HTTPSpeechRoutes.swift`
  Owns HTTP speech submission and the HTTP default request-context provenance for route, method, server identity attributes, and speech topic.
- `Sources/SpeakSwiftlyServer/MCP/MCPClientIdentity.swift`
  Captures MCP `clientInfo` from session initialization and converts it into speech request-context attributes such as `mcp.client.display_name`.
- `Sources/SpeakSwiftlyServer/MCP/MCPToolHandlers.swift` and `MCPToolSupport.swift`
  Own MCP tool execution and merge MCP tool/client defaults with caller-provided `request_context`, `cwd`, and `repo_root`.

## Plugin And Skill Sources

- `.codex-plugin/plugin.json`
  Holds the repo-root Codex plugin manifest for this checkout, including the tracked skill, MCP config, and plugin-managed hook paths. This repository remains the canonical payload owner for the `speak-swiftly` plugin identity, displayed as `Speak Swiftly`.
- `hooks/`
  Holds the Codex lifecycle hook config, final-reply TTS script, and logging-only permission-request probe used by installed plugin users.
- `.codex/`
  Holds repo-local development and testing config for hook payload inspection. Do not document `.codex/` as the end-user install path.
- `scripts/codex-hooks-doctor.mjs`
  Reports hook ownership, required hook feature flags, duplicate user-level Stop hooks, permission-request probe wiring, legacy or dev-only global hook entries, installed plugin hook metadata, live runtime readiness, and voice-profile alignment. Its dry-run repair planning detects legacy `speak-swiftly-server` installs and duplicate enablement from both the standalone and Socket marketplaces, preferring `speak-swiftly@socket` when both are present.
- `skills/speak-swiftly-mcp/`
  Holds the general MCP orientation skill for broad SpeakSwiftly surface requests.
- `skills/speak-swiftly-launchagent-setup/`
  Holds the LaunchAgent setup, refresh, status, and healthcheck skill.
- `skills/speak-swiftly-codex-hooks/`
  Holds the Codex lifecycle hook setup, plugin-managed hook feature-gate check, permission-request probe, doctor interpretation, duplicate global hook repair, and hook-log troubleshooting skill.
- `skills/speak-swiftly-runtime-operator/`
  Holds the runtime, queue, playback, and request-control skill.
- `skills/speak-swiftly-voice-workflows/`
  Holds the voice-profile, live-speech, and retained-artifact skill.
- `skills/speak-swiftly-text-profiles/`
  Holds the text-normalization, stored-profile, and replacement-authoring skill.

## Current Cleanup Follow-Through

- Keep same-type `ServerHost` extensions as the preferred split mechanism for host refactors. Do not introduce helper coordinators or wrapper objects unless a real ownership boundary changes.
- Keep embedded-session lifecycle ownership in `EmbeddedLifecycleServices.swift` plus `EmbeddedServerSession.swift` instead of drifting those readiness and shutdown semantics back into ad hoc retained-task bodies.
- Keep transport-local shaping at the edge. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- If a test file starts mixing HTTP, MCP, LaunchAgent, and host-state concerns again, split it before adding more cases.
- Keep the shorter Swift Testing suite and file names at the source level, but leave the SwiftPM test target names and `.xctestplan` entries alone unless there is a concrete package-graph or tooling reason to rename them too. The suite surface is what maintainers read and filter most often, while the target names are already stable package wiring.
