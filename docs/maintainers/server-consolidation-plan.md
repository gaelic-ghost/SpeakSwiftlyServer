# Server Consolidation Plan

## Overview

`SpeakSwiftlyServer` is now the single runtime-owning host for both the app-facing HTTP API and the first embedded MCP surface.

The goal is to remove the current split where separate hosts can each create their own in-process `SpeakSwiftlyCore` runtime. After consolidation, one process will own one `WorkerRuntime`, one playback controller, one queue view, one readiness state, and one profile cache.

## Target Architecture

The target architecture has three layers:

1. `Host`
   `ServerHost` is the only runtime owner and orchestration boundary. It owns lifecycle, worker status observation, caches, request tracking, and transport-agnostic snapshots and mutations.

2. `HTTP`
   The HTTP surface remains a thin Hummingbird adapter over `ServerHost`. It owns route registration, request decoding, HTTP status and header shaping, accepted job URL building, and SSE response framing.

3. `MCP`
   The MCP surface is now a sibling adapter over `ServerHost`. It owns embedded MCP transport mounting plus MCP-specific tool, resource, and response shaping without creating a second runtime-owning host.

## State Model

The server now distinguishes backend ownership from UI-facing observation:

- `ServerHost`
  This is the authoritative backend actor. It owns `WorkerRuntime`, request submission, queue and playback control, profile refresh, job storage, and host snapshots.

- `ServerState`
  This is an `@Observable final class` intended for app and operator UI use. It mirrors safe snapshots published by `ServerHost` and should never own backend orchestration logic.

This split keeps dependency flow straight:

- runtime -> `ServerHost`
- `ServerHost` -> `ServerState`
- `HTTP` and `MCP` -> `ServerHost`
- app UI -> `ServerState`

## Configuration Direction

The long-term configuration direction is a composed app config:

- `AppConfig`
- `HostConfig`
- `HTTPConfig`
- `MCPConfig`

Phase 1 introduces the typed config composition without yet adopting `swift-configuration`.

Phase 3 will adopt [`apple/swift-configuration`](https://github.com/apple/swift-configuration) so the server can load defaults, YAML, environment overrides, and later reloadable providers through one typed configuration pipeline.

## Implementation Phases

### Phase 1

- Introduce `ServerHost` as the runtime-owning actor.
- Repurpose `ServerState` into an observable UI-facing state object.
- Introduce `AppConfig` with nested HTTP and MCP config sections while keeping current environment compatibility.
- Keep the existing HTTP behavior unchanged.

### Phase 2

- Clean up the host API so all shared backend mutations and snapshots flow through `ServerHost`.
- Introduce host-native state snapshots for app UI, HTTP, and future MCP consumers.
- Keep transport-specific shaping out of the host.
- Keep server-side update flow off `MainActor`.
- Use `ServerState` as a SwiftUI-facing projection, not as the server's primary stream or event bus.

### Phase 3

- Add a host-owned async update pipeline so non-UI consumers stop depending on eager per-event runtime refresh and manual stream fan-out.
- Use `swift-async-algorithms` where it simplifies host update flow and future HTTP/MCP fan-out semantics.
- Adopt `swift-configuration`.
- Add YAML-backed typed configuration loading.
- Keep reload policy explicit rather than implicit; define controlled-restart boundaries before adding live-reloading config providers.

### Phase 4

- Add the MCP surface to the same Hummingbird application.
- Route MCP through `ServerHost` instead of creating a second runtime-owning host.
- Keep the first integrated MCP scope focused on host-backed tools and resources that already map cleanly onto current server snapshots.
- Make transport-state reporting runtime-aware so app UI and MCP see actual adapter lifecycle instead of only config intent.

Phase 4 is now landed. `SpeakSwiftlyServer` mounts an embedded MCP surface through `MCPSurface`, the first MCP tool and resource catalog now rides the same `ServerHost` used by HTTP and app UI, and transport snapshots now report lifecycle states like `stopped`, `starting`, `listening`, and `failed` instead of only config-derived intent.

### Phase 5

- Correct the remaining transport lifecycle-truth gap so `listening` means the shared Hummingbird process is actually serving traffic.
- Introduce a host-owned event surface alongside stable host snapshots.
- Use `swift-async-algorithms` more deliberately for host subscriptions and fan-out where it removes bespoke stream plumbing.
- Pull over only the remaining host-worthy MCP pieces from `SpeakSwiftlyMCP`, not the old standalone host shape.
- Deprecate or thin out the standalone `SpeakSwiftlyMCP` host package.

Phase 5 is now landed for the initial live-update slice. The host now exposes typed `HostEvent` updates alongside the stable `HostStateSnapshot` surface, the `listening` boundary is tied to Hummingbird's real `onServerRunning` lifecycle hook, and the embedded MCP surface can subscribe clients to `speak://status`, `speak://profiles`, `speak://profiles/{profile_name}/detail`, `speak://jobs`, `speak://jobs/{job_id}`, and `speak://runtime` without introducing a second runtime-owning state model. The shared host also now exposes host-native job resources plus the subset of the old prompt catalog that still maps cleanly onto the embedded server model.

## Remaining Deliberate Deferrals

The following items are still intentionally deferred:

- converging the existing job-specific HTTP SSE stream onto the host event surface
- rebuilding playback-job MCP resources before the shared host naturally owns those concepts
- importing the rest of the old standalone MCP prompt catalog for parity alone
- defining live config reloading semantics or in-place config mutation policy

These are not cleanup misses from Phases 1 through 5. They are consciously deferred scope boundaries.

## Next Likely Phase

The next likely host-level phase is selective HTTP SSE convergence.

That work would keep `ServerHost` as the only source of transport truth, preserve `ServerState` as the SwiftUI-facing projection, and decide where the existing job-specific SSE route should continue to stay specialized versus where it should begin consuming the newer host event surface.

That phase should wait for the adjacent `SpeakSwiftly` API layer to settle enough that widening the host event model does not create unnecessary churn across repositories.
