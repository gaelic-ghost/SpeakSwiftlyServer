# Phase 4 Checklist

## Objective

Mount the MCP surface into the same `SpeakSwiftlyServer` process, route it entirely through `ServerHost`, and keep the transport boundary thin enough that the old standalone MCP host can start shrinking instead of competing.

## Scope

Phase 4 should cover:

- adding the MCP transport and package dependency to `SpeakSwiftlyServer`
- mounting MCP into the shared Hummingbird host process
- routing MCP tools and resources through `ServerHost`
- making transport-state reporting reflect actual adapter lifecycle instead of config intent alone

Phase 4 should not yet cover:

- live config reloading
- rebuilding the old standalone prompt catalog unless it still clearly earns its keep
- preserving every standalone `SpeakSwiftlyMCP` resource just for parity when the host does not yet own the right data

## Core Decisions

- `ServerHost` remains the only backend owner.
- `MCPSurface` stays a transport adapter, not a second host model.
- MCP reads should prefer host snapshots over reconstructing state from worker events.
- MCP live updates should subscribe to the host-owned update pipeline only where they materially improve the operator experience.
- Transport status should become runtime-aware, not remain only config-derived.

## Near-Term Use Cases

This phase unlocks:

- one app-managed localhost process that can expose both HTTP and MCP without duplicate `WorkerRuntime` instances
- agent-facing MCP access to the same queue, playback, profile, and status state already used by the app and HTTP API
- a cleaner migration path away from the standalone `SpeakSwiftlyMCP` executable

This phase removes:

- duplicate runtime ownership between `SpeakSwiftlyServer` and `SpeakSwiftlyMCP`
- drift risk between HTTP status reporting and MCP status reporting
- the need to keep the standalone MCP server in lockstep just to expose the same core controls

The simpler path considered first was keeping the standalone MCP package alive and only teaching the app to choose one transport at a time. That would have worked short-term, but it would preserve the current duplication and keep transport truth split across two hosts.

## File Changes

### Package

- Update `Package.swift`
  Add the MCP Swift SDK dependency and any minimal supporting dependencies required for the embedded MCP transport.

### Entry

- Update `Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`
  Assemble the shared Hummingbird app with both the HTTP and MCP surfaces mounted from the same host and config.

### Host

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Promote transport-state reporting from config-derived snapshots to host-owned lifecycle snapshots.

- Update `Sources/SpeakSwiftlyServer/Host/HostStateModels.swift`
  Widen transport-state snapshots if needed so app UI and MCP resources can see `disabled`, `starting`, `listening`, or `failed` instead of only `configured`.

### MCP

- Implement `Sources/SpeakSwiftlyServer/MCP/MCPSurface.swift`
  Mount the MCP transport and register method handlers against `ServerHost`.

- Implement `Sources/SpeakSwiftlyServer/MCP/MCPModels.swift`
  Hold MCP-specific schemas, resource payloads, and any thin response wrappers that should not leak into the host.

### Docs

- Update `README.md`
  Document how the shared server process exposes MCP, including the config keys and base MCP path once mounted.

- Update `docs/maintainers/server-consolidation-plan.md`
  Record that MCP is no longer a separate runtime-owning host once this phase lands.

## Initial MCP Scope

The first integrated MCP surface should include the host-backed tools that already map cleanly onto `ServerHost`:

- `queue_speech_live`
- `create_profile`
- `list_profiles`
- `remove_profile`
- `list_queue_generation`
- `list_queue_playback`
- `playback_pause`
- `playback_resume`
- `playback_state`
- `clear_queue`
- `cancel_request`
- `status`

The first integrated MCP resources should be the ones backed by existing host snapshots:

- `speak://status`
- `speak://profiles`
- `speak://runtime`

These should be deferred to Phase 5 unless the host grows the right backing data naturally during implementation:

- `speak://playback-jobs`
- `speak://playback-jobs/{playback_job_id}`
- profile-detail resources that duplicate data the host does not yet distinguish beyond cached profile snapshots
- the standalone prompt catalog

## Acceptance Criteria

- `SpeakSwiftlyServer` can expose HTTP and MCP from the same process without creating a second runtime owner.
- MCP tool handlers read and mutate only through `ServerHost`.
- Host transport snapshots distinguish actual adapter lifecycle from static configuration intent.
- The mounted MCP surface exposes the agreed first-pass tools and resources.
- `swift build` and `swift test` remain green after integration.

## Status

Phase 4 is now implemented in `SpeakSwiftlyServer`.

The original Phase 4 landing left one follow-up mismatch: transport snapshots could flip to `listening` before the shared Hummingbird process had actually bound and started serving traffic. That lifecycle-truth gap is now treated as the first Phase 5 cleanup item rather than being left implicit.

## Follow-On Work

- Phase 5 should decide which remaining standalone `SpeakSwiftlyMCP` resources, prompts, and playback-job concepts still earn migration into the shared host.
- After MCP is mounted, define whether any MCP resources should subscribe to the host update pipeline directly instead of remaining read-on-demand snapshots.
