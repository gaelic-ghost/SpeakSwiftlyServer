# SpeakSwiftlyServer

Swift executable package for a shared localhost host process that exposes the public `SpeakSwiftly` runtime surface through an app-friendly HTTP API and an optional MCP surface.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Embedding](#embedding)
- [Configuration](#configuration)
- [Development](#development)
- [Repository Layout](#repository-layout)
- [Verification](#verification)
- [Roadmap](#roadmap)
- [License](#license)

## Overview

This repository is the standalone Swift service for `SpeakSwiftly`. It uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) to host one localhost macOS process with in-memory job tracking and server-sent events, while delegating speech, voice-profile management, and worker lifecycle to the typed `SpeakSwiftly` runtime. That shared process can mount both the HTTP API and the MCP surface without creating duplicate `SpeakSwiftly.Runtime` owners.

### Deployment Targets

Current intended deployment targets are:

- macOS 15 and newer for the standalone server package and initial app-managed installation path
- iOS 18 and newer for a near-future app-facing reuse path once the host logic is split cleanly enough to be consumed from an iOS app

The current executable package is still macOS-only, but its host and state architecture should be kept friendly to an eventual iOS extraction into a reusable library target.

Linux support is a medium-term consideration rather than a current promise. If making this Swift package Linux-compatible starts forcing awkward compromises into the Apple-first host and app architecture, a separate Linux implementation in Rust is an acceptable direction instead of contorting this package.

### Motivation

The target is a thin Swift service that a forthcoming macOS app can install and manage as a LaunchAgent without needing a separate Python runtime. Early development aimed to stay close to the existing Python server contract, but the current service now follows the newer `SpeakSwiftly` control model directly where the runtime surface has evolved.

That means this package intentionally stays narrow: Hummingbird for transport hosting, `SpeakSwiftly` for speech and profile operations, and a small amount of server state to translate typed runtime events into retained job snapshots, SSE replay, and MCP resources.

### Current SpeakSwiftly Alignment

This server is aligned to the current public library surface in the sibling [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) checkout rather than an older private worker boundary.

Today the server talks directly to:

- `SpeakSwiftly.live()`
- `SpeakSwiftly.Runtime.statusEvents()`
- `SpeakSwiftly.Runtime.speak(text:with:as:textProfileName:textContext:sourceFormat:id:)`
- `SpeakSwiftly.Runtime.createProfile(named:from:voice:outputPath:id:)`
- `SpeakSwiftly.Runtime.createClone(named:from:transcript:id:)`
- `SpeakSwiftly.Runtime.profiles(id:)`
- `SpeakSwiftly.Runtime.removeProfile(named:id:)`
- `SpeakSwiftly.Runtime.queue(_:id:)`
- `SpeakSwiftly.Runtime.playback(_:id:)`
- `SpeakSwiftly.Runtime.clearQueue(id:)`
- `SpeakSwiftly.Runtime.cancelRequest(_:requestID:)`

For text normalization, the server stays on the public `TextForSpeech` model surface through the runtime normalizer rather than inventing a parallel server-only schema:

- `SpeakSwiftly.Runtime.normalizer.activeProfile()`
- `SpeakSwiftly.Runtime.normalizer.baseProfile()`
- `SpeakSwiftly.Runtime.normalizer.profile(named:)`
- `SpeakSwiftly.Runtime.normalizer.profiles()`
- `SpeakSwiftly.Runtime.normalizer.effectiveProfile(named:)`
- `SpeakSwiftly.Runtime.normalizer.persistenceURL()`
- `SpeakSwiftly.Runtime.normalizer.loadProfiles()`
- `SpeakSwiftly.Runtime.normalizer.saveProfiles()`
- `SpeakSwiftly.Runtime.normalizer.createProfile(id:named:replacements:)`
- `SpeakSwiftly.Runtime.normalizer.storeProfile(_:)`
- `SpeakSwiftly.Runtime.normalizer.useProfile(_:)`
- `SpeakSwiftly.Runtime.normalizer.removeProfile(named:)`
- `SpeakSwiftly.Runtime.normalizer.reset()`
- `SpeakSwiftly.Runtime.normalizer.addReplacement(...)`
- `SpeakSwiftly.Runtime.normalizer.replaceReplacement(...)`
- `SpeakSwiftly.Runtime.normalizer.removeReplacement(...)`

The server also consumes the public summary and event types that those calls vend, including `SpeakSwiftly.RequestHandle`, `SpeakSwiftly.RequestEvent`, `SpeakSwiftly.StatusEvent`, `SpeakSwiftly.ProfileSummary`, `SpeakSwiftly.ActiveRequest`, `SpeakSwiftly.QueuedRequest`, and `SpeakSwiftly.PlaybackStateSnapshot`.

That alignment means the remaining translation layer is intentionally transport-local: snake_case HTTP and MCP payload shaping, retained job snapshots, and SSE framing. The server is not reaching through the library boundary to construct raw worker protocol messages or private runtime state directly.

That narrowness also informs platform policy. The package should prefer maintainable Apple-platform architecture for the current macOS and near-future iOS use cases over speculative cross-platform compromises.

## Setup

This package now resolves its SwiftPM dependencies from tagged GitHub releases in [`Package.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Package.swift). The one current exception is [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly), which is pinned to a specific Git revision until the latest tagged release can be consumed through a normal semver range again.

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

The shared server binds to `127.0.0.1:7337` by default.

The package now also ships a separate operator-facing CLI product:

```bash
swift run SpeakSwiftlyServerCli help
```

That CLI currently owns LaunchAgent support so the standalone server binary can stay focused on one foreground service process while the CLI grows into the install, inspection, and maintenance surface around it.

To render the current per-user LaunchAgent property list without installing it:

```bash
swift run SpeakSwiftlyServerCli launch-agent print-plist
```

To install or refresh the current user's LaunchAgent with a config file:

```bash
swift run SpeakSwiftlyServerCli launch-agent install \
  --config-file ./server.yaml
```

That command writes a user-owned property list into `~/Library/LaunchAgents`, points `ProgramArguments` at the `SpeakSwiftlyServer` executable rather than the CLI, and uses `launchctl bootstrap` / `bootout` against the current `gui/<uid>` domain. If your server binary lives somewhere other than the sibling executable next to `SpeakSwiftlyServerCli`, pass `--server-executable-path /absolute/path/to/SpeakSwiftlyServer`.

To inspect or remove the installed LaunchAgent:

```bash
swift run SpeakSwiftlyServerCli launch-agent status
swift run SpeakSwiftlyServerCli launch-agent uninstall
```

## Embedding

`SpeakSwiftlyServerCore` now exposes a small app-facing embedding surface for SwiftUI and other Apple-platform app code:

- [`EmbeddedServerSession.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/EmbeddedServerSession.swift) is the supported public lifecycle wrapper for starting and stopping an embedded shared server session.
- [`ServerState.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerState.swift) is the supported public `@Observable` projection that app UI can read directly.
- [`HostStateModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostStateModels.swift) and the job snapshot types in [`ServerModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerModels.swift) are the public read-only value models that back that observable state.

That public surface is intentionally small. `ServerHost` remains internal so app code does not couple itself to transport orchestration, async stream plumbing, or other backend ownership details.

Start an embedded session from app code like this:

```swift
import SpeakSwiftlyServerCore
import SwiftUI

@main
struct ExampleApp: App {
    @State private var session: EmbeddedServerSession?

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .task {
                    if session == nil {
                        session = try? await EmbeddedServerSession.start()
                    }
                }
        }
    }
}

struct ContentView: View {
    let session: EmbeddedServerSession?

    var body: some View {
        if let session {
            Text(session.state.overview.workerMode)
        } else {
            ProgressView("Starting SpeakSwiftlyServer…")
        }
    }
}
```

If a subview needs bindings into mutable session-backed state, use SwiftUI's `@Bindable` support for `@Observable` models instead of `@ObservedObject`. Apple documents that `@Observable` types are tracked by the properties a view reads directly, and that binding support should come through `@Bindable` when a view needs writable bindings:

- [Observation](https://developer.apple.com/documentation/observation)
- [Managing model data in your app](https://developer.apple.com/documentation/swiftui/managing-model-data-in-your-app)
- [Migrating from the observable object protocol to the observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)

## Configuration

The shared server supports these environment variables:

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
    serverName: speak-swiftly-mcp
    title: SpeakSwiftly
```

Top-level transport settings and HTTP-specific overrides intentionally compose this way:

- `APP_HOST`, `APP_PORT`, and `APP_SSE_HEARTBEAT_SECONDS` define the shared transport defaults.
- `APP_HTTP_HOST`, `APP_HTTP_PORT`, and `APP_HTTP_SSE_HEARTBEAT_SECONDS` override those defaults only for the HTTP surface.
- If you do not set an `APP_HTTP_*` value, the HTTP listener inherits the corresponding top-level `APP_*` value.

When `APP_CONFIG_FILE` is set, the server now watches that YAML file for changes through `ReloadingFileProvider<YAMLSnapshot>`. The optional `APP_CONFIG_RELOAD_INTERVAL_SECONDS` environment variable controls the polling interval and defaults to `2` seconds.

Only the host-safe subset reloads live today:

- `app.name`
- `app.environment`
- `app.sseHeartbeatSeconds`
- `app.completedJobTTLSeconds`
- `app.completedJobMaxCount`
- `app.jobPruneIntervalSeconds`

Changes to bind addresses, ports, HTTP enablement, MCP enablement, MCP path, or MCP server metadata are detected and reported, but they still require a process restart before they can take effect.

The current HTTP surface is:

- `GET /healthz`
- `GET /readyz`
- `GET /status`
- `GET /profiles`
- `POST /profiles/clone`
- `GET /jobs`
- `GET /queue/generation`
- `GET /queue/playback`
- `GET /playback`
- `GET /text-profiles`
- `GET /text-profiles/base`
- `GET /text-profiles/active`
- `GET /text-profiles/effective`
- `GET /text-profiles/effective/{profile_id}`
- `GET /text-profiles/stored/{profile_id}`
- `POST /profiles`
- `POST /playback/pause`
- `POST /playback/resume`
- `POST /text-profiles/stored`
- `POST /text-profiles/load`
- `POST /text-profiles/save`
- `POST /text-profiles/active/reset`
- `POST /text-profiles/active/replacements`
- `POST /text-profiles/stored/{profile_id}/replacements`
- `DELETE /profiles/{profile_name}`
- `DELETE /queue`
- `DELETE /queue/{request_id}`
- `DELETE /text-profiles/stored/{profile_id}`
- `DELETE /text-profiles/active/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}`
- `PUT /text-profiles/active`
- `PUT /text-profiles/active/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `POST /speak`
- `GET /jobs/{job_id}`
- `GET /jobs/{job_id}/events`

`POST /speak`, `POST /profiles`, `POST /profiles/clone`, and `DELETE /profiles/{profile_name}` all return job metadata immediately. `POST /speak` mirrors the current public `SpeakSwiftly.Runtime.speak(... as: .live)` path directly, which means every speech request records the initial acknowledgement event before it starts and eventually reaches terminal completion. `POST /speak` also accepts optional `cwd`, `repo_root`, `text_profile_name`, `text_format`, `nested_source_format`, and `source_format` fields so clients can pass path-aware, stored-profile-aware, and explicit format-aware normalization context through to the runtime when speech input should not rely on automatic format detection. Progress, worker status changes, acknowledgements, and terminal results are exposed through `GET /jobs/{job_id}/events` as SSE, and retained job state is discoverable through `GET /jobs`.

The `/text-profiles` route family is intentionally synchronous and state-oriented rather than job-oriented. It exposes the current base, active, stored, and effective `TextForSpeech.Profile` state plus replacement editing and profile persistence paths for downstream apps or agents that need to help a user shape text normalization directly. `POST /text-profiles/load` and `POST /text-profiles/save` map directly to the public normalizer persistence calls so operators can refresh or flush stored normalization state without reaching into the runtime process manually.

The queue and playback control routes are immediate control operations rather than long-running jobs. `GET /queue/generation` and `GET /queue/playback` expose the generation and playback queues separately so the HTTP layer matches the runtime's split control surface. `GET /playback`, `POST /playback/pause`, and `POST /playback/resume` expose the current playback state and let clients control it directly. `DELETE /queue` clears queued work and returns the number of cancelled queued requests. `DELETE /queue/{request_id}` cancels one active or queued request and returns the cancelled request ID.

The route surface now mirrors the current `SpeakSwiftly` control model directly instead of preserving the older foreground/background split. The remaining alignment work is narrower: keeping the transport docs accurate as the sibling runtime evolves and deciding whether any server-local transport shaping should disappear now that the public library surface is more expressive.

The current MCP surface is optional and mounts on the same shared Hummingbird process at `APP_MCP_PATH` when `APP_MCP_ENABLED=true`. It currently exposes these tools:

- `queue_speech_live`
- `create_profile`
- `create_clone`
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
- `load_text_profiles`
- `save_text_profiles`
- `list_text_profiles`
- `create_text_profile`
- `store_text_profile`
- `use_text_profile`
- `remove_text_profile`
- `reset_text_profile`
- `add_text_replacement`
- `replace_text_replacement`
- `remove_text_replacement`

The embedded MCP resources are:

- `speak://status`
- `speak://profiles`
- `speak://profiles/{profile_name}/detail`
- `speak://jobs`
- `speak://jobs/{job_id}`
- `speak://runtime`
- `speak://text-profiles`
- `speak://text-profiles/base`
- `speak://text-profiles/active`
- `speak://text-profiles/effective`
- `speak://text-profiles/effective/{profile_id}`
- `speak://text-profiles/stored/{profile_id}`
- `speak://text-profiles/guide`

Those MCP tools and resources are intentionally thin adapters over the same `ServerHost` snapshots and mutations used by the HTTP API and the app-facing `ServerState`.

Accepted-job MCP tool results now return both `status_resource_uri` and a direct `job_resource_uri` so MCP clients can jump straight to one request's retained job detail.

The embedded MCP surface also now carries a small prompt catalog migrated from the standalone package where those prompts still map cleanly onto the shared host model:

- `draft_profile_voice_description`
- `draft_profile_source_text`
- `draft_voice_design_instruction`
- `draft_queue_playback_notice`
- `draft_text_profile`
- `draft_text_replacement`

The text-profile prompts and the `speak://text-profiles/guide` resource are there so an app-hosted or MCP-hosted agent can help a user author replacements deliberately instead of treating normalization rules like hidden implementation detail. That parity is intentional because text profiles are meant to be downstream-user-facing, whether the downstream caller is a SwiftUI app, an MCP client, or a local HTTP consumer.

The embedded MCP surface now also supports resource subscriptions for those URIs. Clients connected to the standalone MCP event stream can subscribe to `speak://status`, `speak://profiles`, `speak://profiles/{profile_name}/detail`, `speak://jobs`, `speak://jobs/{job_id}`, and `speak://runtime` and receive `notifications/resources/updated` when shared host events change the underlying state.

Transport lifecycle snapshots are now intentionally tied to the shared Hummingbird process rather than static config alone. `listening` means the shared HTTP host has actually reached Hummingbird's `onServerRunning` boundary, so HTTP and MCP surface status now describe real network availability instead of only configuration intent.

The current HTTP SSE route remains intentionally job-specific at the route boundary, but it now rides the same host-owned event backbone used by other non-UI consumers instead of keeping a separate per-job subscriber registry inside `ServerHost`. That keeps the HTTP semantics stable while removing the last bespoke live-update path from the shared host.

## Development

The shared runtime entrypoint now lives in [`Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift) inside the `SpeakSwiftlyServerCore` module, with thin executable wrappers in [`Sources/SpeakSwiftlyServerExecutable/main.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServerExecutable/main.swift) for the `SpeakSwiftlyServer` executable target and [`Sources/SpeakSwiftlyServerCli/main.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServerCli/main.swift) for the CLI. The shared host process stays intentionally small:

- [`HTTPSurface.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift) assembles and conditionally mounts the HTTP surface on the shared Hummingbird server.
- [`MCPSurface.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/MCP/MCPSurface.swift) mounts the embedded MCP transport on that same shared process and registers tools and resources against `ServerHost`.
- [`MCPModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/MCP/MCPModels.swift) defines the thin MCP-specific catalog and result wrappers that stay at the transport edge.
- [`ServerHost.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost.swift) owns runtime lifecycle, request orchestration, shared host state, and server-side update flow.
- [`ServerState.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerState.swift) is the `@Observable` SwiftUI-facing projection of host state.
- [`HostStateModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostStateModels.swift) defines the shared host-native snapshots used by app UI, HTTP, and MCP consumers.
- [`HostEvents.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostEvents.swift) defines the typed host event surface used by non-UI consumers that need live change notifications without depending on SwiftUI observation.
- [`ServerRuntimeBridge.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerRuntimeBridge.swift) keeps the runtime boundary thin around the public `SpeakSwiftly.Runtime` actor.
- [`ServerModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerModels.swift) defines request and response payloads.

The design is deliberately direct. Adding extra wrappers, managers, or intermediate layers here would be easy, but it would also be the kind of unnecessary complexity that makes a small localhost service harder to reason about, so the server is kept close to the typed runtime API on purpose. That means the service talks to the public `SpeakSwiftly.Runtime` surface, its public text normalizer, and its public event and summary types instead of reaching through the library boundary to construct raw worker requests itself.

The separate CLI target is the one intentional widening of that model. It earns its keep because it unlocks LaunchAgent installation, status inspection, and future operator workflows without turning the server binary itself into a mixed control-and-serve tool.

For repository maintenance, treat this standalone repository as the source of truth for package development, tags, and releases. When the `speak-to-user` monorepo adopts a new server version, prefer bumping that submodule pointer to a tagged `SpeakSwiftlyServer` release rather than a floating branch tip.

The repo-maintenance toolkit is now the maintainer-facing wrapper around that release flow. Use `scripts/repo-maintenance/validate-all.sh` for local validation, `scripts/repo-maintenance/sync-shared.sh` for deterministic repo-local sync hooks, and `scripts/repo-maintenance/release.sh` for the tagged release path after verification passes.

## Repository Layout

- `Sources/SpeakSwiftlyServer/` contains the reusable `SpeakSwiftlyServerCore` library target with the HTTP, MCP, host, config, and LaunchAgent support code.
- `Sources/SpeakSwiftlyServerExecutable/` contains the thin `SpeakSwiftlyServer` executable wrapper.
- `Sources/SpeakSwiftlyServerCli/` contains the thin operator CLI wrapper.
- `Tests/` contains the package test suite, including the opt-in end-to-end coverage paths and the dedicated CLI tests.
- `docs/` holds repo-local supporting documentation.
- `plugins/apple-dev-skills/` is the in-development plugin copy that this repository publishes through the local marketplace file.
- `.agents/plugins/marketplace.json` points local Codex discovery at the in-repo plugin source during development.

## Verification

Current local maintainer baseline:

```bash
scripts/repo-maintenance/validate-all.sh
```

The package-level verification path that toolkit wraps is still:

```bash
swift test
```

If you want to check the split executable surfaces explicitly, these are the direct smoke-test commands:

```bash
swift run SpeakSwiftlyServerCli help
swift run SpeakSwiftlyServerCli launch-agent print-plist
```

The current automated suite covers configuration parsing, queued live speech job completion semantics, generation and playback queue inspection, playback control routes, queue cancellation routes, startup failure before readiness, runtime degradation while active and queued speech jobs are in flight, in-memory retention and pruning, SSE replay and heartbeat behavior, route-level health, profile, clone, text-profile, and job lifecycle responses against a controlled typed runtime, the embedded MCP tool, prompt, and resource surface, the shared host snapshot stream and typed host event stream, plus an opt-in live end-to-end suite against a real `SpeakSwiftly` runtime:

```bash
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2ETests
```

That serialized live suite now mirrors the main `SpeakSwiftly` sequential workflows across both HTTP and MCP:

- voice-design profile creation, then silent playback, then audible playback
- clone creation with a provided transcript, then silent playback, then audible playback
- clone creation with inferred transcript loading, then silent playback, then audible playback

If you want the underlying playback trace logs too, add `SPEAKSWIFTLY_PLAYBACK_TRACE=1` to that same command.

That live path expects the sibling [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) checkout to have already been built with Xcode at least once so `../SpeakSwiftly/.derived/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib` exists for the server process.

After the live suite passes, use `scripts/repo-maintenance/release.sh` for the tagged release flow so local validation, tag creation, push, and GitHub release creation stay on the same documented path.

The remaining coverage work is now narrower and more cleanup-focused. The main open checks are trimming any transport-local wrappers that no longer buy clarity and expanding end-to-end assertions when the sibling runtime surface settles again.

## Roadmap

Planned work is tracked in [`ROADMAP.md`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/ROADMAP.md).

## License

This repository is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). See [LICENSE](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/LICENSE).
