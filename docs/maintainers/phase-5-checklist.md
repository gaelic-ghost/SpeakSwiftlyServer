# Phase 5 Checklist

## Objective

Strengthen the shared host's live-update model so HTTP, MCP, and app consumers can subscribe to meaningful host changes without rebuilding transport-specific state models or leaning on UI-facing observation types.

## Scope

Phase 5 should cover:

- correcting the remaining transport lifecycle-truth gap so `listening` only means the shared Hummingbird process is actually serving traffic
- introducing a host-owned event stream alongside the existing host snapshot model
- improving host subscription and fan-out plumbing with `swift-async-algorithms` where it removes bespoke stream code
- deciding which remaining standalone MCP concepts still earn migration into the shared host now that embedded MCP is real

Phase 5 should not yet cover:

- live config reloading policy or in-place config mutation
- copying the standalone MCP prompt catalog over for parity alone
- rebuilding every standalone playback-job surface if the shared host model still has not earned those concepts directly

## Core Decisions

- `ServerHost` remains the only backend owner and the only source of transport truth.
- `ServerState` remains a SwiftUI-facing `@Observable` projection, not the server's event backbone.
- Stable host snapshots and live host events should coexist instead of replacing one another.
- HTTP SSE and MCP subscriptions should consume host-owned async surfaces, not UI observation.
- Phase 5 should prefer small, typed host events over transport-specific streaming payloads.

## Near-Term Use Cases

This phase unlocks:

- cleaner app and agent visibility into transport, queue, playback, and job changes as they happen
- a more honest operator model where transport lifecycle states line up with actual network availability
- a better foundation for selective MCP live resources or notifications without bolting more ad hoc logic onto the current snapshot stream

This phase removes:

- the remaining mismatch between transport intent and transport reality at the `listening` boundary
- pressure to keep extending a single snapshot stream for every non-UI consumer use case
- more bespoke stream and fan-out logic in HTTP and MCP as those surfaces grow

The simpler path considered first was to keep extending the current shared `AsyncStream<HostStateSnapshot>` model and only patch over the transport mismatch. That would work for a while, but it would keep host updates too snapshot-shaped and make future live MCP behavior harder to reason about.

## File Changes

### Host

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Keep the stable host snapshot path, but add a host-owned event stream and make transport-state updates line up with actual lifecycle boundaries.

- Add `Sources/SpeakSwiftlyServer/Host/HostEvents.swift`
  Define the small typed host event model that HTTP and MCP can subscribe to without reconstructing meaning from whole snapshots.

- Optionally add `Sources/SpeakSwiftlyServer/Host/HostSubscriptions.swift`
  Only if the host subscription plumbing stops being readable inside `ServerHost`.

### HTTP

- Update `Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift`
  Use Hummingbird's real lifecycle callback to mark transports as `listening` only after the shared server is running, and decide whether any SSE plumbing should start consuming the host event surface.

### MCP

- Update `Sources/SpeakSwiftlyServer/MCP/MCPSurface.swift`
  Keep reads and mutations host-backed, and only add subscription-aware MCP behavior where the host event surface materially improves the operator experience.

### Docs

- Update `README.md`
  Clarify the transport lifecycle truth boundary and any new live-update semantics that become part of the public server behavior.

- Update `docs/maintainers/server-consolidation-plan.md`
  Record the Phase 5 event-stream direction and the role split between host snapshots, host events, and SwiftUI observation.

## Initial Host Event Scope

The first host event surface should stay compact and directly useful:

- `transportChanged`
- `jobChanged`
- `playbackChanged`
- `profileCacheChanged`
- `recentErrorRecorded`

These events should complement the existing `HostStateSnapshot`, not replace it.

## Acceptance Criteria

- Transport snapshots only report `listening` once the shared Hummingbird process is actually serving traffic.
- `ServerHost` exposes a typed host event surface alongside the existing stable snapshot surface.
- `ServerState` remains out of the server-side event backbone.
- `swift build` and `swift test` remain green after the transport lifecycle cleanup and event-surface additions.

## Status

Phase 5 is now landed for the initial host-events and selective live-update slice. The shared host reports transport `listening` only after the Hummingbird process is actually serving traffic, `ServerHost` now exposes a typed host event surface alongside stable host snapshots, and the embedded MCP surface supports selective live resource notifications for `speak://runtime/overview`, `speak://runtime/status`, `speak://runtime/configuration`, `speak://voices`, `speak://voices/{profile_name}`, `speak://requests`, and `speak://requests/{request_id}`. The shared host now also exposes the host-native profile-detail and request-detail resources that earned migration cleanly, along with the small prompt subset that still fits the embedded MCP surface directly.

The following items remain deliberately deferred rather than accidentally unfinished:

- migrating playback-job MCP resources until the shared host naturally earns those concepts
- copying the rest of the old standalone MCP prompt catalog over for parity alone
- defining live config reloading policy or in-place config mutation

That selective HTTP SSE convergence work is now tracked and landed in Phase 6.
