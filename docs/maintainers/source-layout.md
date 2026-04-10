# Source Layout

## Purpose

This document is the maintainer map for the post-`SpeakSwiftly 2.2.1` source split. The goal is to keep future cleanup, review, and feature work landing in the smallest file family that already owns the relevant concern, instead of letting `ServerHost.swift`, one host extension, or one mixed test file grow back into a monolith.

## Host Sources

- `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Holds the actor declaration, stored state, construction, lifecycle, transport watch hooks, and shared snapshot basics.
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Queries.swift`
  Holds the public query surface, runtime/text-profile reads and writes, generated-artifact reads, and immediate control entrypoints.
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
- `Sources/SpeakSwiftlyServer/Host/QueueStatusModels.swift`
  Queue, playback, health, readiness, and status snapshots.
- `Sources/SpeakSwiftlyServer/Host/JobEventModels.swift`
  Job event payloads and retained request snapshots.
- `Sources/SpeakSwiftlyServer/Host/HostStateModels.swift`
  Shared host-overview snapshots for app state, HTTP, and MCP resources.

## Test Sources

- `Tests/SpeakSwiftlyServerTests/SpeakSwiftlyServerHTTPWorkflowTests.swift`, `SpeakSwiftlyServerHTTPControlTests.swift`, and `SpeakSwiftlyServerHTTPFailureTests.swift`
  Keep lifecycle-heavy HTTP route coverage split by mainline flows, immediate control paths, and error handling.
- `Tests/SpeakSwiftlyServerTests/SpeakSwiftlyServerMCPCatalogListingTests.swift`, `SpeakSwiftlyServerMCPCatalogRuntimeTests.swift`, `SpeakSwiftlyServerMCPCatalogResourceTests.swift`, and `SpeakSwiftlyServerMCPCatalogSupport.swift`
  Keep MCP catalog, runtime-tool, and resource/prompt coverage separate so the tool surface can grow without another single giant catalog test.
- `Tests/SpeakSwiftlyServerTests/SpeakSwiftlyServerMCPSessionTests.swift` and `SpeakSwiftlyServerMCPSubscriptionTests.swift`
  Keep MCP session behavior and live-subscription behavior independent from catalog assertions.
- `Tests/SpeakSwiftlyServerTests/SpeakSwiftlyServerConfigurationTests.swift`, `SpeakSwiftlyServerHostLifecycleTests.swift`, and `SpeakSwiftlyServerHostStateTests.swift`
  Keep configuration, lifecycle, and shared-state coverage independent instead of mixing them into one broad host suite.
- `Tests/SpeakSwiftlyServerTests/MockRuntime.swift` plus the `MockRuntime+*.swift` extensions
  Keep the typed-runtime test double split by text profiles, speech generation, runtime controls, retained artifacts, and test-only control hooks.
- `Tests/SpeakSwiftlyServerE2ETests/SpeakSwiftlyServerE2ESuite.swift` plus the `SpeakSwiftlyServerE2E*Lane.swift`, `SpeakSwiftlyServerE2E*Helpers.swift`, and `SpeakSwiftlyServerE2E*ControlSurfaceTests.swift` files
  Keep live workflow lanes, operator-control lanes, and helper/support code separate so the opt-in suite stays readable even as it grows.

## Current Cleanup Follow-Through

- Keep same-type `ServerHost` extensions as the preferred split mechanism for host refactors. Do not introduce helper coordinators or wrapper objects unless a real ownership boundary changes.
- Keep transport-local shaping at the edge. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- If a test file starts mixing HTTP, MCP, LaunchAgent, and host-state concerns again, split it before adding more cases.
