# TODO

## Thorough Review Slices

- [x] Slice 1: Host state and job tracking
  Files: `Sources/SpeakSwiftlyServer/Host/ServerHost+Snapshots.swift`, `Sources/SpeakSwiftlyServer/Host/ServerHost+RequestEvents.swift`
  Focus: runtime-derived state refresh policy, degraded-worker fallback behavior, profile-cache reconciliation, SSE replay, request retention and pruning.

- [x] Slice 2: Runtime adapter transport bridging
  Files: `Sources/SpeakSwiftlyServer/Host/SpeakSwiftlyRuntimeAdapter.swift`
  Focus: text-profile transport shaping, crash-vs-error behavior, path resolution, and runtime API drift handling.

- [x] Slice 3: MCP tool dispatch and notification policy
  Files: `Sources/SpeakSwiftlyServer/MCP/MCPToolHandlers.swift`
  Focus: repeated argument parsing, accepted-request result shaping, resource-change notifications, and tool-handler drift.

- [x] Slice 4: Embedded lifecycle and startup or shutdown ownership
  Files: `Sources/SpeakSwiftlyServer/EmbeddedServerSession.swift`, `Sources/SpeakSwiftlyServer/EmbeddedLifecycleServices.swift`
  Focus: readiness gates, sibling-service coordination, shutdown barriers, and transport-state transitions.

- [~] Slice 5: LaunchAgent operator flow
  Files: `Sources/SpeakSwiftlyServer/LaunchAgent/LaunchAgentRuntime.swift`
  Focus: launchctl polling, uninstall timing, partial teardown states, and operator-facing diagnostics.

- [x] Slice 6: E2E MCP stream harness
  Files: `Tests/SpeakSwiftlyServerTransportE2ETests/E2EMCPEventStream.swift` and related E2E helpers
  Focus: stream connection timing, polling sleeps, notification matching, and flake risk.

## Slice 1 Findings

- [x] Fix degraded-worker cached fallback so it clears `generationQueueStatus` alongside playback state, and add regression coverage for the degraded queue snapshot path.
- [x] Refresh the cached voice-profile list after `reroll_voice_profile` completes, and add regression coverage that verifies profile-cache metadata is refreshed after reroll.
- [x] Replace profile-name set reconciliation with request-scoped mutation intent checks so create, rename, reroll, and delete refreshes only verify the specific profile transition that was actually requested, even when unrelated external profile edits happen during the refresh window.

## Slice 2 Findings

- [x] Replace the text-profile transport bridge `preconditionFailure` path with thrown runtime errors that surface through HTTP text-profile routes as operator-readable JSON failures.
- [x] Translate MCP text-profile resource and tool bridge failures into explicit `MCPError.internalError(...)` payloads instead of relying on the default thrown-error path.
- [x] Recheck runtime-adapter path-resolution behavior for edge cases like non-normalized relative `cwd` values and whitespace-padded `cwd` inputs, and cover it with direct helper tests.
- [ ] Keep watching for future upstream transport-shape drift beyond the current text-profile bridge; if another released payload starts needing ad hoc JSON bridging, treat that as a new review slice rather than letting the adapter accumulate more silent translation seams.

## Slice 3 Findings

- [x] Collapse repeated accepted-request MCP tool result shaping behind one helper so speech-generation and voice-profile job tools keep a single request-resource response shape.
- [x] Collapse repeated text-profile MCP mutation branches behind one helper that preserves explicit `MCPError` mapping and always emits the `textProfiles` resource-change notification after successful mutation work.
- [x] Keep the text-profile snapshot read path on the same explicit error-mapping helper so read-only and mutation tool cases now fail through one predictable MCP error surface.

## Slice 4 Findings

- [x] Reset the embedded session lifecycle handle after shutdown completes so one long-lived `EmbeddedServer` instance can `liftoff()`, `land()`, and `liftoff()` again when an app feature is turned off and later turned back on.
- [x] Update lifecycle regression coverage so the post-shutdown `land()` path is treated as a no-op and add direct restart coverage for the reused embedded-session instance.
- [x] Split MCP startup failure handling from the post-start shutdown path so readiness failures only describe real startup failures instead of conflating later lifecycle errors with startup.
- [x] Collapse repeated sibling-service shutdown-barrier completion into one helper so prune, config-watch, MCP, and embedded-application services all use the same completion bookkeeping on success, graceful shutdown, and thrown failure paths.
- [x] Make embedded host startup both cancellable and time-bounded so `land()` can preempt an in-flight startup attempt and a stuck runtime start now fails with a clear operator-facing timeout instead of wedging the lifecycle service indefinitely.

## Slice 5 Findings

- [x] Make plain LaunchAgent uninstall wait for launchd to finish unloading the job, not just issue `bootout`, so immediate status checks and follow-up install flows do not race a partially torn-down service.
- [x] Distinguish a normal `not_loaded` LaunchAgent status from unexpected `launchctl print` failures so operator status output stops masking permission or launchd inspection errors as if the job were simply absent.
- [x] Remove the staged LaunchAgent config alias during uninstall so the app-owned install surface does not leave behind a stale launch-agent-only config copy after the service has been removed.

## Slice 6 Findings

- [x] Replace the SSE helper's fixed post-connect sleep and buffer polling loop with explicit async wakeups for stream readiness, notification arrival, and terminal stream failure so MCP resource-update tests stop depending on arbitrary 100ms delays inside the harness.
- [x] Recheck the broader MCP E2E helper path for places where startup or session-handshake failures are still flattened into retry polling instead of surfacing the real transport error once the server is reachable.
- [x] Run one live MCP smoke path against the refactored stream helper after the live-service model-unload preflight creates enough memory headroom, so the async-wakeup harness changes have one real end-to-end proof point beyond helper-only tests.
