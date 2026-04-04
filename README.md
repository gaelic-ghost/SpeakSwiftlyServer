# SpeakSwiftlyServer

Swift executable package for a localhost HTTP server that exposes `SpeakSwiftlyCore` over a small, app-friendly API.

## Overview

This repository is the Swift-native sibling to `../speak-to-user-server`. It uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) to host a localhost macOS HTTP service with in-memory job tracking and server-sent events, while delegating speech, profile management, and worker lifecycle to the typed `SpeakSwiftlyCore` runtime.

### Deployment Targets

Current intended deployment targets are:

- macOS 15 and newer for the standalone server package and initial app-managed installation path
- iOS 18 and newer for a near-future app-facing reuse path once the host logic is split cleanly enough to be consumed from an iOS app

The current executable package is still macOS-only, but its host and state architecture should be kept friendly to an eventual iOS extraction into a reusable library target.

Linux support is a medium-term consideration rather than a current promise. If making this Swift package Linux-compatible starts forcing awkward compromises into the Apple-first host and app architecture, a separate Linux implementation in Rust is an acceptable direction instead of contorting this package.

### Motivation

The target is a thin Swift service that a forthcoming macOS app can install and manage as a LaunchAgent without needing a separate Python runtime. Early development aimed to stay close to the existing Python server contract, but the current service now follows the newer `SpeakSwiftlyCore` control model directly where the runtime surface has evolved.

That means this package intentionally stays narrow: Hummingbird for HTTP, `SpeakSwiftlyCore` for speech and profile operations, and a small amount of server state to translate typed worker events into job snapshots and SSE replay.

That narrowness also informs platform policy. The package should prefer maintainable Apple-platform architecture for the current macOS and near-future iOS use cases over speculative cross-platform compromises.

## Setup

Build the package with SwiftPM:

```bash
swift build
```

Run the test suite:

```bash
swift test
```

## Usage

Run the server locally:

```bash
swift run SpeakSwiftlyServer
```

The service binds to `127.0.0.1:7337` by default and supports these environment variables:

- `APP_CONFIG_FILE`
- `APP_NAME`
- `APP_ENVIRONMENT`
- `APP_HOST`
- `APP_PORT`
- `APP_SSE_HEARTBEAT_SECONDS`
- `APP_COMPLETED_JOB_TTL_SECONDS`
- `APP_COMPLETED_JOB_MAX_COUNT`
- `APP_JOB_PRUNE_INTERVAL_SECONDS`
- `APP_HTTP_ENABLED`
- `APP_HTTP_HOST`
- `APP_HTTP_PORT`
- `APP_HTTP_SSE_HEARTBEAT_SECONDS`
- `APP_MCP_ENABLED`
- `APP_MCP_PATH`
- `APP_MCP_SERVER_NAME`
- `APP_MCP_TITLE`

If `APP_CONFIG_FILE` points at a YAML file, the server loads it through [apple/swift-configuration](https://github.com/apple/swift-configuration) with environment variables taking precedence over YAML and YAML taking precedence over built-in defaults. The expected YAML shape mirrors the nested config reader keys:

```yaml
app:
  name: speak-swiftly-server
  environment: development
  host: 127.0.0.1
  port: 7337
  sseHeartbeatSeconds: 10
  completedJobTTLSeconds: 900
  completedJobMaxCount: 200
  jobPruneIntervalSeconds: 60
  http:
    enabled: true
    host: 127.0.0.1
    port: 7337
    sseHeartbeatSeconds: 10
  mcp:
    enabled: false
    path: /mcp
    serverName: speak-to-user-mcp
    title: SpeakSwiftlyMCP
```

The current HTTP surface is:

- `GET /healthz`
- `GET /readyz`
- `GET /status`
- `GET /profiles`
- `GET /queue/generation`
- `GET /queue/playback`
- `GET /playback`
- `POST /profiles`
- `POST /playback/pause`
- `POST /playback/resume`
- `DELETE /profiles/{profile_name}`
- `DELETE /queue`
- `DELETE /queue/{request_id}`
- `POST /speak`
- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/events`

`POST /speak`, `POST /profiles`, and `DELETE /profiles/{profile_name}` all return job metadata immediately. `POST /speak` now mirrors `SpeakSwiftlyCore v0.8.0` directly by queueing a live speech job through `queue_speech_live`, which means every speech request records the initial acknowledgement event before it starts and eventually reaches terminal completion. Progress, worker status changes, acknowledgements, and terminal results are exposed through `GET /jobs/{job_id}/events` as SSE.

The queue and playback control routes are immediate control operations rather than long-running jobs. `GET /queue/generation` and `GET /queue/playback` expose the generation and playback queues separately so the HTTP layer matches the runtime's split control surface. `GET /playback`, `POST /playback/pause`, and `POST /playback/resume` expose the current playback state and let clients control it directly. `DELETE /queue` clears queued work and returns the number of cancelled queued requests. `DELETE /queue/{request_id}` cancels one active or queued request and returns the cancelled request ID.

The route surface now mirrors the current `SpeakSwiftlyCore` control model directly instead of preserving the older foreground/background split. The remaining alignment work is narrower: re-checking any app-facing payload details that still matter outside this repository and deciding whether any server-local translation code should disappear now that `SpeakSwiftlyCore` is more expressive.

## Development

The executable entrypoint lives in [`Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift). The server itself stays intentionally small:

- [`HTTPSurface.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift) assembles the Hummingbird HTTP surface.
- [`ServerHost.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/Host/ServerHost.swift) owns runtime lifecycle, request orchestration, shared host state, and server-side update flow.
- [`ServerState.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/Host/ServerState.swift) is the `@Observable` SwiftUI-facing projection of host state.
- [`HostStateModels.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/Host/HostStateModels.swift) defines the shared host-native snapshots used by app UI, HTTP, and future MCP consumers.
- [`ServerRuntimeBridge.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/Host/ServerRuntimeBridge.swift) keeps the runtime boundary thin around `SpeakSwiftlyCore`.
- [`ServerModels.swift`](/Users/galew/Workspace/SpeakSwiftlyServer/Sources/SpeakSwiftlyServer/Host/ServerModels.swift) defines request and response payloads.

The design is deliberately direct. Adding extra wrappers, managers, or intermediate layers here would be easy, but it would also be the kind of unnecessary complexity that makes a small localhost service harder to reason about, so the server is kept close to the typed runtime API on purpose. As of `SpeakSwiftly v0.8.1`, that also means the service talks to the public `WorkerRuntime` helper surface instead of reaching through the library boundary to construct raw worker requests itself.

## Verification

Current baseline checks:

```bash
swift build
swift test
```

The current automated suite covers configuration parsing, queued live speech job completion semantics, generation and playback queue inspection, playback control routes, queue cancellation routes, startup failure before readiness, runtime degradation while active and queued speech jobs are in flight, in-memory retention and pruning, SSE replay and heartbeat behavior, route-level health, profile, and job lifecycle responses against a controlled typed runtime, plus an opt-in live end-to-end path against a real `SpeakSwiftlyCore` runtime:

```bash
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2ETests
```

There is also a second opt-in live pass that exercises the actual playback path instead of the silent playback controller. It still drives the full localhost HTTP surface, but it additionally waits for the runtime's structured `playback_engine_ready`, `playback_started`, and `playback_finished` log events:

```bash
SPEAKSWIFTLYSERVER_E2E=1 SPEAKSWIFTLYSERVER_E2E_REAL_PLAYBACK=1 swift test --filter SpeakSwiftlyServerE2ETests
```

If you want the underlying playback trace logs too, add `SPEAKSWIFTLY_PLAYBACK_TRACE=1`.

That live path expects the sibling [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) checkout to have already been built with Xcode at least once so `../SpeakSwiftly/.derived/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` exists for the server process.

The remaining coverage work is now narrower and more integration-focused. The main open checks are downstream payload-alignment expectations for adjacent consumers and any future end-to-end assertions that should exercise those consumers directly.

## Roadmap

Planned work is tracked in [`ROADMAP.md`](/Users/galew/Workspace/SpeakSwiftlyServer/ROADMAP.md).

## License

A project license has not been added yet.
