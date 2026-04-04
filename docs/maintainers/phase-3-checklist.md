# Phase 3 Checklist

## Objective

Calm down the host update pipeline before MCP arrives, then layer typed configuration loading on top of that steadier host model.

## Scope

Phase 3 is intentionally broader than the original config-only placeholder. It now covers:

- host-owned streaming improvements
- async update coalescing
- adoption of Apple infrastructure packages that simplify those concerns
- typed configuration loading groundwork
- `swift-configuration` adoption for defaults plus environment plus optional YAML loading

## Core Decisions

- `ServerHost` remains the single source of truth for server-side updates.
- `ServerState` remains a SwiftUI-facing projection and does not become the primary stream source.
- Server-side update fan-out should use a host-owned async pipeline instead of ad-hoc `AsyncStream` subscriber dictionaries wherever practical.
- The package continues to target `macOS 15+` today and should stay friendly to a near-future `iOS 18+` reuse path.

## File Changes

### Package

- Update `Package.swift`
  Add Apple infrastructure packages needed for the host update pipeline and typed configuration work.

### Host

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Replace eager per-event refresh with a host-owned update pipeline and coalesced runtime snapshot refresh.

- Add `Sources/SpeakSwiftlyServer/Host/HostUpdateStream.swift` if needed
  Hold any small dedicated stream or channel helpers if keeping them inside `ServerHost.swift` stops being readable.

### Config

- Add `Sources/SpeakSwiftlyServer/Config/ConfigStore.swift`
  Hold the shared `swift-configuration` reader setup for defaults, environment overrides, and optional YAML file loading.

## Acceptance Criteria

- Host-side non-UI updates no longer depend on manual subscriber dictionaries as the primary abstraction.
- Runtime queue and playback snapshots are no longer re-fetched eagerly on every single host publish.
- The package can support future HTTP SSE and MCP consumers from the same host-owned update pipeline.
- Typed configuration loading has a clear home and now supports defaults plus environment overrides plus optional YAML files.

## Follow-On Work

- Phase 4 should mount MCP into the same Hummingbird process and subscribe it to the host update pipeline.
- Define which settings are safe to reload live and which require controlled restart before adding reloading file providers.
