# Source Layout

## Purpose

This document is the maintainer map for the current `SpeakSwiftly 4.x`-aligned source split. The goal is to keep future cleanup, review, and feature work landing in the smallest file family that already owns the relevant concern, instead of letting `ServerHost.swift`, one host extension, or one mixed test file grow back into a monolith.

Historical release artifacts belong under [`docs/releases`](../releases/), and historical debugging
writeups belong under [`docs/investigations`](../investigations/), not beside the active maintainer
maps in this directory.
Public documentation media belongs under [`docs/media`](../media/). Runtime-loaded package resources
belong under `Sources/SpeakSwiftlyServer/Resources` instead, because SwiftPM only exposes target
resources through the target bundle.

## Host Sources

- `Sources/SpeakSwiftlyServer/EmbeddedLifecycleServices.swift`
  Holds the embedded-session readiness gates, shutdown barrier, and the explicit service-owned wrappers for host lifecycle, config watching, MCP lifecycle, and wrapped application runtime.
- `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Holds the actor declaration, stored state, and construction-time setup.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Lifecycle.swift`
  Holds runtime start and shutdown, shared update streams, transport lifecycle hooks, configuration-reload handling, and the host health or readiness snapshot surface.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Queries.swift`
  Holds the public runtime query surface, generated-artifact reads, retained-request reads, and immediate control entrypoints.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+ProfileQueries.swift`
  Holds the voice-profile cache reads, default-voice-profile ownership, text-profile queries and mutations, and profile-refresh entrypoints.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+JobSubmission.swift`
  Holds request submission, accepted-request shaping, and the handoff into retained host tracking.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+JobTracking.swift`
  Holds SSE replay, request-event consumption, profile-cache reconciliation, worker status handling, and in-memory job retention.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+State.swift`
  Holds publish flow, runtime refresh, derived host snapshots, and live configuration reload helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+EventSupport.swift`
  Holds transport-status helpers, recent-error emission, event mapping, SSE encoding, and shared host-event helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+ControlSupport.swift`
  Holds playback-control settling, optimistic playback snapshots, and immediate runtime-success helpers.
- `Sources/SpeakSwiftlyServer/Host/ServerRuntimeProtocol.swift`
  Holds the narrow runtime seam and the request-handle wrapper type used by the host.
- `Sources/SpeakSwiftlyServer/Host/ServerRuntimeAdapter.swift`
  Holds the concrete adapter from the public `SpeakSwiftly.Runtime` actor into that host-owned seam.

## Model Sources

- `Sources/SpeakSwiftlyServer/Host/ServerModels.swift`
  Request payloads plus shared normalization-format helpers.
- `Sources/SpeakSwiftlyServer/Host/ProfileModels.swift`
  Voice-profile snapshots plus text-profile and replacement transport models.
- `Sources/SpeakSwiftlyServer/Host/DefaultVoiceCatalog.swift`
  Package-owned default voice seed catalog loading and validation models.
- `Sources/SpeakSwiftlyServer/Host/QueueStatusModels.swift`
  Queue, playback, health, readiness, and status snapshots.
- `Sources/SpeakSwiftlyServer/Host/JobEventModels.swift`
  Job event payloads and retained request snapshots.
- `Sources/SpeakSwiftlyServer/Host/HostStateModels.swift`
  Shared host-overview snapshots for app state, HTTP, and MCP resources.

## Operator Sources

- `Sources/SpeakSwiftlyServer/Resources/DefaultVoiceProfiles/catalog.json`
  Holds the package-owned default voice seed catalog. Keep this as bundled seed metadata, not as
  user profile storage.
- `Sources/SpeakSwiftlyServer/HealthcheckCommand.swift` and `HealthcheckCommand+Transport.swift`
  Keep CLI-facing healthcheck option parsing and high-level probe orchestration separate from the low-level HTTP transport helpers and probe response models.
- `Sources/SpeakSwiftlyServer/LaunchAgent/LaunchAgentCommands.swift`
  Holds the top-level command parsing and dispatch for `serve`, `healthcheck`, and `launch-agent`.
- `Sources/SpeakSwiftlyServer/LaunchAgent/LaunchAgentOptions.swift` and `LaunchAgentOptions+Installation.swift`
  Keep LaunchAgent option parsing, path resolution, and repository-root discovery separate from property-list rendering, config staging, and install/bootstrap mechanics.
- `Sources/SpeakSwiftlyServer/LaunchAgent/LaunchAgentRuntime.swift`
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

## Plugin And Skill Sources

- `.codex-plugin/plugin.json`
  Holds the repo-root Codex plugin manifest for this checkout, including the tracked skill, MCP config, and plugin-managed hook paths. This repository remains the canonical payload owner for the planned `speak-swiftly` plugin identity, displayed as `Speak Swiftly`.
- `.agents/plugins/marketplace.json`
  Holds the repo-local marketplace advertisement that lets this repository surface as an installable local Codex plugin. The Socket marketplace should list this same payload by Git-backed reference rather than carrying a copied plugin directory.
- `hooks/`
  Holds the plugin-managed Codex lifecycle hook config and final-reply TTS script used by installed plugin users.
- `.codex/`
  Holds repo-local development and testing config for hook payload inspection. Do not document `.codex/` as the end-user install path.
- `scripts/codex-hooks-doctor.mjs`
  Reports hook ownership, legacy global hook entries, installed plugin hook metadata, live runtime readiness, and voice-profile alignment. Planned repair behavior also detects legacy `speak-swiftly-server` installs and duplicate enablement from both the standalone and Socket marketplaces, preferring `speak-swiftly@socket` when both are present.
- `skills/speak-swiftly-mcp/`
  Holds the general MCP orientation skill for broad SpeakSwiftly surface requests.
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
