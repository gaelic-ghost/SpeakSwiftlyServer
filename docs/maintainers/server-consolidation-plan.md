# Server Consolidation Plan

## Overview

`SpeakSwiftlyServer` is becoming the single runtime-owning host for both the app-facing HTTP API and a future MCP surface.

The goal is to remove the current split where separate hosts can each create their own in-process `SpeakSwiftlyCore` runtime. After consolidation, one process will own one `WorkerRuntime`, one playback controller, one queue view, one readiness state, and one profile cache.

## Target Architecture

The target architecture has three layers:

1. `Host`
   `ServerHost` is the only runtime owner and orchestration boundary. It owns lifecycle, worker status observation, caches, request tracking, and transport-agnostic snapshots and mutations.

2. `HTTP`
   The HTTP surface remains a thin Hummingbird adapter over `ServerHost`. It owns route registration, request decoding, HTTP status and header shaping, accepted job URL building, and SSE response framing.

3. `MCP`
   The MCP surface will be a sibling adapter over `ServerHost`. It will own tool, resource, and prompt registration plus MCP-specific request and response shaping.

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
- Keep transport-specific shaping out of the host.

### Phase 3

- Adopt `swift-configuration`.
- Add YAML-backed typed configuration loading.
- Define explicit config reload policy and controlled-restart boundaries.

### Phase 4

- Add the MCP surface to the same Hummingbird application.
- Route MCP through `ServerHost` instead of creating a second runtime-owning host.

### Phase 5

- Pull over the remaining host-worthy MCP pieces from `SpeakSwiftlyMCP`.
- Deprecate or thin out the standalone `SpeakSwiftlyMCP` host package.
