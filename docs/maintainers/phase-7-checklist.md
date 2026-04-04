# Phase 7 Checklist

## Goal

Turn the last real deferred item into a first-class shared-host capability: explicit config reload policy with a first-party reloading provider, safe live application in `ServerHost`, and clear reporting when a changed value still needs a restart.

## Why This Phase Exists

The shared host, transport model, and event surface are now stable enough that config reloading no longer risks targeting moving architecture. This phase is a durable building-block change because it:

- removes the last major configuration mismatch between the docs and the actual server behavior
- uses Apple’s `ReloadingFileProvider` instead of introducing a custom watcher subsystem
- keeps `ServerHost` as the single authority for deciding which changes can apply live
- turns malformed reloads and restart-required changes into readable operator-facing host errors instead of silent no-ops

The simpler path considered first was to stop after documenting that playback-job parity was retired and leave config reload as the only remaining future item. That would have avoided code churn, but it would also have left the server with first-party config infrastructure that still could not express the policy the docs had been pointing at for multiple phases.

## Scope

### Config

- Update `Sources/SpeakSwiftlyServer/Config/ConfigStore.swift`
  Switch YAML-backed config files from `FileProvider<YAMLSnapshot>` to `ReloadingFileProvider<YAMLSnapshot>`, expose provider services to the shared Hummingbird process, and surface typed config reload updates without killing the watch loop on malformed edits.

- Update `Sources/SpeakSwiftlyServer/Config/AppConfig.swift`
  Add a direct initializer from `ConfigReader` so live reloads and startup loading use the same typed decoding path.

### Host

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Add a host-owned config reload application path.

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Apply only the safe live subset in place: host name, environment, SSE heartbeat interval, completed-job retention TTL, completed-job max count, and prune interval.

- Update `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Treat bind-address, port, HTTP adapter, and MCP adapter shape changes as restart-required, and report them through the existing recent-error model.

### Entry Point And Services

- Update `Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`
  Build startup config through `ConfigStore`, pass any reloading provider services into the Hummingbird application, and feed typed config updates back into `ServerHost`.

- Update `Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift`
  Accept background services during shared app assembly so the config provider can run inside the same process lifecycle as the server.

### Docs

- Update `README.md`
  Document `APP_CONFIG_RELOAD_INTERVAL_SECONDS`, the current safe live subset, and the still-restart-gated settings.

- Update `docs/maintainers/server-consolidation-plan.md`
  Mark legacy playback-job and prompt-parity deferrals as retired, then mark config reload policy as landed.

- Update `ROADMAP.md`
  Mark the old live-update follow-through as complete and add the new config-reload milestone.

## Explicit Non-Goals

- live-rebinding HTTP or MCP sockets in place
- toggling HTTP or MCP enabled state without a restart
- rebuilding the old standalone `playback-jobs` namespace
- reviving prompt-parity work that the shared embedded prompt catalog already replaced

## Validation

- `swift build`
- `swift test`

Add coverage for both the typed reload-update surface and the host-side live-apply versus restart-required boundary.

## Status

Phase 7 is now landed for the first safe-live-reload slice. The server runs Apple’s reloading YAML provider inside the shared Hummingbird process, malformed reloads are rejected without killing the watcher, `ServerHost` applies the safe live subset in place, and restart-required changes are reported through the shared recent-error model.
