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

This repository is the standalone Swift service for `SpeakSwiftly`. It uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) to host one macOS process with job tracking and server-sent events, while delegating speech, voice-profile management, and worker lifecycle to the typed `SpeakSwiftly` runtime.

### Deployment Targets

Current deployment targets are:

- macOS 15 and newer for the standalone server package and initial app-managed installation path
- iOS 18 and newer for a near-future app-facing reuse path once the host logic is split cleanly enough to be consumed from an iOS app

Linux support is a medium-term consideration rather than a current promise. A separate Linux implementation in Rust is more likely.

### Motivation

I wanted a solid foundation to build voice-enabled applications on top of. So, this package provides a thin Swift service that macOS apps can easily import and manage as a LaunchAgent, without needing a separate Python runtime. It the `SpeakSwiftly` control model.

It's intentionally narrow, using Hummingbird for HTTP and MCP, `SpeakSwiftly` for speech and profile operations, `TextForSpeech` for customizeable text normalization, and a small amount of server state to translate and cache runtime events as snapshots, as well as SSE replay, and MCP resources.

### Current SpeakSwiftly Alignment

This server is aligned to the current public library surface of its resolved [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) `2.3.1` package dependency.

Today the server relies on the current typed runtime capabilities that matter for transport hosting:

- `SpeakSwiftly.liftoff(configuration:)`
- `runtime.statusEvents()`
- `runtime.generate.speech(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.audio(text:with:textProfileName:textContext:sourceFormat:)`
- `runtime.generate.batch(_:with:)`
- `runtime.voices.create(design:from:vibe:voice:outputPath:)`
- `runtime.voices.create(clone:from:vibe:transcript:)`
- `runtime.voices.list()`
- `runtime.voices.rename(_:to:)`
- `runtime.voices.reroll(_:)`
- `runtime.voices.delete(named:)`
- `runtime.jobs.generationQueue()`
- `runtime.jobs.list()`
- `runtime.jobs.job(id:)`
- `runtime.jobs.expire(id:)`
- `runtime.artifacts.files()`
- `runtime.artifacts.file(id:)`
- `runtime.artifacts.batches()`
- `runtime.artifacts.batch(id:)`
- `runtime.player.list()`
- `runtime.player.state()`
- `runtime.player.pause()`
- `runtime.player.resume()`
- `runtime.player.clearQueue()`
- `runtime.player.cancelRequest(_:)`
- `runtime.overview()`
- `runtime.status()`
- `runtime.switchSpeechBackend(to:)`
- `runtime.reloadModels()`
- `runtime.unloadModels()`
- `runtime.request(id:)`
- `runtime.updates(for:)`

For text normalization, the server stays on the public `TextForSpeech` model surface through the runtime normalizer rather than inventing a parallel server-only schema:

- `runtime.normalizer.profiles.active()`
- `runtime.normalizer.profiles.stored(id:)`
- `runtime.normalizer.profiles.list()`
- `runtime.normalizer.profiles.effective(id:)`
- `runtime.normalizer.persistence.load()`
- `runtime.normalizer.persistence.save()`
- `runtime.normalizer.profiles.create(id:name:replacements:)`
- `runtime.normalizer.profiles.store(_:)`
- `runtime.normalizer.profiles.use(_:)`
- `runtime.normalizer.profiles.delete(id:)`
- `runtime.normalizer.profiles.reset()`
- `runtime.normalizer.profiles.add(...)`
- `runtime.normalizer.profiles.replace(...)`
- `runtime.normalizer.profiles.removeReplacement(...)`

The server also consumes the public summary and event types that those calls vend, including `SpeakSwiftly.RequestHandle`, `SpeakSwiftly.RequestEvent`, `SpeakSwiftly.StatusEvent`, `SpeakSwiftly.ProfileSummary`, `SpeakSwiftly.ActiveRequest`, `SpeakSwiftly.QueuedRequest`, `SpeakSwiftly.PlaybackStateSnapshot`, `SpeakSwiftly.RuntimeOverview`, `SpeakSwiftly.Vibe`, and `SpeakSwiftly.Configuration`.

That alignment means the remaining translation layer is intentionally transport-local: snake_case HTTP and MCP payload shaping, retained job snapshots, and SSE framing. Queue, playback, and runtime-refresh state now come from the atomic runtime overview instead of server-local fallback reconstruction. The server is not reaching through the library boundary to construct raw worker protocol messages or private runtime state directly.

For generation requests, the server also supports one server-owned default voice profile. HTTP and MCP callers may omit `profile_name` for live speech, retained audio, and retained batch requests when the server has `app.defaultVoiceProfileName` or `APP_DEFAULT_VOICE_PROFILE_NAME` configured. When neither the request nor the server configuration provides a voice profile, the server rejects the request with a descriptive validation error instead of silently guessing.

That narrowness also informs platform policy. The package should prefer maintainable Apple-platform architecture for the current macOS and near-future iOS use cases over speculative cross-platform compromises.

## Setup

This package resolves its SwiftPM dependencies from GitHub source control in [`Package.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Package.swift) and locks the resolved revisions in [`Package.resolved`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Package.resolved). `SpeakSwiftly` is currently pinned to the `v2.3.1` commit revision declared there instead of to a local checkout, because the upstream package still depends on `mlx-audio-swift` by revision and SwiftPM will not allow a stable-version root requirement in that graph shape.

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
swift run SpeakSwiftlyServerTool
```

The shared server binds to `127.0.0.1:7337` by default.

The package now ships one operator-facing executable product with both the foreground server entrypoint and the LaunchAgent maintenance surface:

```bash
swift run SpeakSwiftlyServerTool help
```

Running the tool without subcommands defaults to `serve`, and the same binary also exposes `launch-agent` subcommands for install, inspection, and maintenance work.

To render the current per-user LaunchAgent property list without installing it:

```bash
swift run SpeakSwiftlyServerTool launch-agent print-plist
```

To install or refresh the current user's LaunchAgent with a config file:

```bash
swift run SpeakSwiftlyServerTool launch-agent install \
  --config-file ./server.yaml
```

That command writes a user-owned property list into `~/Library/LaunchAgents`, points `ProgramArguments` at the staged release artifact under `.release-artifacts/current/SpeakSwiftlyServerTool serve`, and uses `launchctl bootstrap` / `bootout` against the current `gui/<uid>` domain. That default keeps the live service on the repo's staged release build instead of whichever debug or transient executable happened to invoke the command. If your tool binary lives somewhere other than the staged release path, pass `--tool-executable-path /absolute/path/to/SpeakSwiftlyServerTool` explicitly.

To inspect or remove the installed LaunchAgent:

```bash
swift run SpeakSwiftlyServerTool launch-agent status
swift run SpeakSwiftlyServerTool launch-agent uninstall
```

### App-Managed Install Contract

The `v2.0.0` app-managed install contract is now explicit and centered on one per-user layout instead of ad hoc paths:

- server support root: `~/Library/Application Support/SpeakSwiftlyServer`
- server config file: `~/Library/Application Support/SpeakSwiftlyServer/server.yaml`
- runtime base directory: `~/Library/Application Support/SpeakSwiftlyServer/runtime`
- runtime profile root: `~/Library/Application Support/SpeakSwiftlyServer/runtime/profiles`
- runtime configuration file: `~/Library/Application Support/SpeakSwiftlyServer/runtime/configuration.json`
- logs directory: `~/Library/Logs/SpeakSwiftlyServer`
- stdout log: `~/Library/Logs/SpeakSwiftlyServer/stdout.log`
- stderr log: `~/Library/Logs/SpeakSwiftlyServer/stderr.log`
- reserved cache root: `~/Library/Caches/SpeakSwiftlyServer`

That runtime profile root is now the default LaunchAgent-owned `SPEAKSWIFTLY_PROFILE_ROOT`, which means the standalone server no longer has to share the generic default `SpeakSwiftly` per-user profile store unless an operator intentionally points it somewhere else.

The package exposes that same contract directly to app code through [`ServerInstallLayout`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/AppManagedInstallLayout.swift), so the app can inspect or reuse the owned paths without re-deriving them by hand:

```swift
import SpeakSwiftlyServer

let layout = ServerInstallLayout.defaultForCurrentUser()
print(layout.standardErrorLogURL.path)
print(layout.runtimeProfileRootURL.path)
```

The package also now exposes [`ServerInstalledLogs`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/AppManagedInstallLayout.swift), which lets the app read the owned stdout and stderr files as plain text, line arrays, or decodable JSON-line payloads:

```swift
import SpeakSwiftlyServer

let logs = try ServerInstalledLogs.read()
let stderrText = logs.stderr.text
let stderrLines = logs.stderr.lines

struct RuntimeLog: Decodable, Sendable {
    let event: String
    let ok: Bool?
}

let runtimeEvents = try logs.stderr.decodeJSONLines(as: RuntimeLog.self)
```

That API is intentionally file-backed. The app can call one package function and get useful in-process formats without scraping Console, tailing files manually, or hardcoding LaunchAgent defaults in a second place.

## Embedding

`SpeakSwiftlyServer` now exposes a small app-facing embedding surface for SwiftUI and other Apple-platform app code:

- [`EmbeddedServerSession.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/EmbeddedServerSession.swift) is the supported public lifecycle wrapper for starting and stopping an embedded shared server session.
- [`ServerState.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerState.swift) is the supported public `@Observable` projection that app UI can read directly.
- [`HostStateModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostStateModels.swift) plus the transport-facing model families in [`ServerModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerModels.swift), [`ProfileModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ProfileModels.swift), [`QueueStatusModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/QueueStatusModels.swift), and [`JobEventModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/JobEventModels.swift) are the public read-only value models that back that observable state.

That public surface is intentionally small. `ServerHost` remains internal so app code does not couple itself to transport orchestration, async stream plumbing, or other backend ownership details.

Start an embedded session from app code like this:

```swift
import SpeakSwiftlyServer
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
- `APP_DEFAULT_VOICE_PROFILE_NAME`
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
- `GET /runtime/host`
- `GET /runtime/status`
- `GET /runtime/configuration`
- `GET /voices`
- `GET /text-profiles`
- `GET /text-profiles/style`
- `GET /text-profiles/base`
- `GET /text-profiles/active`
- `GET /text-profiles/effective`
- `GET /text-profiles/effective/{profile_id}`
- `GET /text-profiles/stored/{profile_id}`
- `GET /generation/queue`
- `GET /generation/jobs`
- `GET /generation/jobs/{job_id}`
- `GET /generation/files`
- `GET /generation/files/{artifact_id}`
- `GET /generation/batches`
- `GET /generation/batches/{batch_id}`
- `GET /playback/state`
- `GET /playback/queue`
- `GET /requests`
- `GET /requests/{request_id}`
- `GET /requests/{request_id}/events`
- `POST /voices/from-description`
- `POST /voices/from-audio`
- `POST /voices/{profile_name}/reroll`
- `POST /speech/live`
- `POST /speech/files`
- `POST /speech/batches`
- `POST /playback/pause`
- `POST /playback/resume`
- `POST /text-profiles/stored`
- `POST /text-profiles/load`
- `POST /text-profiles/save`
- `POST /text-profiles/active/reset`
- `POST /text-profiles/active/replacements`
- `POST /text-profiles/stored/{profile_id}/replacements`
- `POST /runtime/backend`
- `POST /runtime/models/reload`
- `POST /runtime/models/unload`
- `PUT /voices/{profile_name}/name`
- `PUT /text-profiles/stored/{profile_id}`
- `PUT /text-profiles/style`
- `PUT /text-profiles/active`
- `PUT /text-profiles/active/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `PUT /runtime/configuration`
- `DELETE /voices/{profile_name}`
- `DELETE /playback/queue`
- `DELETE /playback/requests/{request_id}`
- `DELETE /text-profiles/stored/{profile_id}`
- `DELETE /text-profiles/active/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}/replacements/{replacement_id}`

`POST /speech/live`, `POST /voices/from-description`, `POST /voices/from-audio`, `PUT /voices/{profile_name}/name`, `POST /voices/{profile_name}/reroll`, and `DELETE /voices/{profile_name}` all return accepted-request metadata immediately. Those responses use `request_id`, `request_url`, and `events_url` so ordinary HTTP clients can follow one tracked request cleanly without having to learn the MCP resource model first. `POST /speech/live` mirrors the current public live-speech queue lane and accepts optional `cwd`, `repo_root`, `text_profile_name`, `text_format`, `nested_source_format`, and `source_format` fields so callers can pass path-aware and normalization-aware context explicitly.

The `/text-profiles` route family is synchronous and state-oriented rather than request-oriented. It exposes the current built-in style plus base, active, stored, and effective `TextForSpeech.Profile` state, along with replacement editing and profile persistence paths for downstream apps or agents that need to shape normalization deliberately. `GET /text-profiles/style` and `PUT /text-profiles/style` mirror the built-in normalization-style control that now participates in effective normalization alongside custom profiles. `POST /text-profiles/load` and `POST /text-profiles/save` map directly to the public text-profile persistence calls so operators can refresh or flush stored normalization state without reaching into the runtime process manually.

The queue and playback control routes are immediate control operations rather than long-running requests. `GET /generation/queue` and `GET /playback/queue` expose the generation and playback queues separately so the HTTP layer matches the runtime's split control surface. `GET /playback/state`, `POST /playback/pause`, and `POST /playback/resume` expose the current playback state and let clients control it directly. `DELETE /playback/queue` clears queued playback work and returns the number of cancelled queued requests. `DELETE /playback/requests/{request_id}` cancels one active or queued request and returns the cancelled request ID.

The runtime routes are also state-oriented. `GET /runtime/host` returns the shared-host overview with readiness, queues, transports, cached profiles, and recent errors. `GET /runtime/status` returns the underlying `SpeakSwiftly.StatusEvent`. `GET /runtime/configuration` and `PUT /runtime/configuration` expose the saved next-start backend configuration. `POST /runtime/backend` hot-switches the active backend, while `POST /runtime/models/reload` and `POST /runtime/models/unload` follow the current v2 runtime-control verbs directly.

The current MCP surface is optional and mounts on the same shared Hummingbird process at `APP_MCP_PATH` when `APP_MCP_ENABLED=true`. It currently exposes these tools:

- `generate_speech`
- `generate_audio_file`
- `generate_batch`
- `create_voice_profile_from_description`
- `create_voice_profile_from_audio`
- `update_voice_profile_name`
- `reroll_voice_profile`
- `get_runtime_overview`
- `get_runtime_status`
- `get_staged_runtime_config`
- `set_staged_config`
- `switch_speech_backend`
- `reload_models`
- `unload_models`
- `list_voice_profiles`
- `delete_voice_profile`
- `get_text_normalizer_snapshot`
- `get_text_profile_style`
- `set_text_profile_style`
- `list_generation_queue`
- `list_playback_queue`
- `pause_playback`
- `resume_playback`
- `get_playback_state`
- `clear_playback_queue`
- `cancel_request`
- `load_text_profiles`
- `save_text_profiles`
- `create_text_profile`
- `store_text_profile`
- `use_text_profile`
- `delete_text_profile`
- `reset_active_text_profile`
- `add_text_replacement`
- `replace_text_replacement`
- `remove_text_replacement`
- `list_active_requests`
- `list_generation_jobs`
- `get_generation_job`
- `expire_generation_job`
- `list_generated_files`
- `get_generated_file`
- `list_generated_batches`
- `get_generated_batch`

The embedded MCP resources are:

- `speak://runtime/overview`
- `speak://runtime/status`
- `speak://runtime/configuration`
- `speak://voices`
- `speak://voices/guide`
- `speak://text-profiles`
- `speak://text-profiles/style`
- `speak://text-profiles/base`
- `speak://text-profiles/active`
- `speak://text-profiles/effective`
- `speak://requests`
- `speak://generation/jobs`
- `speak://generation/files`
- `speak://generation/batches`
- `speak://voices/{profile_name}`
- `speak://requests/{request_id}`
- `speak://generation/jobs/{job_id}`
- `speak://generation/files/{artifact_id}`
- `speak://generation/batches/{batch_id}`
- `speak://text-profiles/effective/{profile_id}`
- `speak://text-profiles/stored/{profile_id}`
- `speak://text-profiles/guide`
- `speak://playback/guide`

Those MCP tools and resources are intentionally thin adapters over the same `ServerHost` snapshots and mutations used by the HTTP API and the app-facing `ServerState`.

Accepted-request MCP tool results now return `request_id`, `request_resource_uri`, and `status_resource_uri` so coding agents can follow one tracked request immediately while still having an obvious top-level status resource for orientation.

The embedded MCP surface also now carries a small prompt catalog migrated from the standalone package where those prompts still map cleanly onto the shared host model:

- `draft_profile_voice_description`
- `draft_profile_source_text`
- `draft_voice_design_instruction`
- `draft_queue_playback_notice`
- `draft_text_profile`
- `draft_text_replacement`
- `choose_surface_action`

The text-profile prompts and the `speak://text-profiles/guide` resource are there so an app-hosted or MCP-hosted agent can help a user author replacements deliberately instead of treating normalization rules like hidden implementation detail. That parity is intentional because text profiles are meant to be downstream-user-facing, whether the downstream caller is a SwiftUI app, an MCP client, or a local HTTP consumer, and that now includes the built-in normalization style as part of the operator-facing surface.

The embedded MCP surface also supports resource subscriptions for the live state resources and templates backed by shared host updates. Clients connected to the standalone MCP event stream can subscribe to `speak://runtime/overview`, `speak://runtime/status`, `speak://runtime/configuration`, `speak://voices`, `speak://voices/{profile_name}`, `speak://requests`, `speak://requests/{request_id}`, `speak://generation/jobs`, `speak://generation/jobs/{job_id}`, `speak://generation/files`, `speak://generation/files/{artifact_id}`, `speak://generation/batches`, `speak://generation/batches/{batch_id}`, `speak://text-profiles`, `speak://text-profiles/style`, `speak://text-profiles/base`, `speak://text-profiles/active`, `speak://text-profiles/effective`, `speak://text-profiles/effective/{profile_id}`, and `speak://text-profiles/stored/{profile_id}` and receive `notifications/resources/updated` when shared host events change the underlying state.

Transport lifecycle snapshots are now intentionally tied to the shared Hummingbird process rather than static config alone. `listening` means the shared HTTP host has actually reached Hummingbird's `onServerRunning` boundary, so HTTP and MCP surface status now describe real network availability instead of only configuration intent.

The current HTTP SSE route remains intentionally job-specific at the route boundary, but it now rides the same host-owned event backbone used by other non-UI consumers instead of keeping a separate per-job subscriber registry inside `ServerHost`. That keeps the HTTP semantics stable while removing the last bespoke live-update path from the shared host.

## Development

The shared runtime entrypoint now lives in [`Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift) inside the `SpeakSwiftlyServer` module, with a thin executable wrapper in [`Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift) for the unified `SpeakSwiftlyServerTool` executable target. The shared host process stays intentionally small, but the source layout is now split by concern so the codebase is easier to navigate:

- [`HTTPSurface.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift) assembles and conditionally mounts the HTTP surface on the shared Hummingbird server.
- [`MCPSurface.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/MCP/MCPSurface.swift) mounts the embedded MCP transport on that same shared process and registers tools and resources against `ServerHost`.
- [`MCPModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/MCP/MCPModels.swift) defines the thin MCP-specific catalog and result wrappers that stay at the transport edge.
- [`ServerHost.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost.swift) owns the actor definition, stored state, construction, lifecycle, and shared snapshot basics.
- [`ServerHost+Queries.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BQueries.swift) holds the public host query surface and immediate control entrypoints.
- [`ServerHost+JobSubmission.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BJobSubmission.swift) owns request submission, accepted-request shaping, and entry into retained host tracking.
- [`ServerHost+JobTracking.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BJobTracking.swift) owns request-event consumption, SSE replay, profile-cache reconciliation, and retention.
- [`ServerHost+State.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BState.swift) owns publish flow, runtime refresh, and derived host snapshot helpers.
- [`ServerHost+EventSupport.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BEventSupport.swift) keeps transport-state, event-mapping, SSE encoding, and shared host-event helpers at the edge.
- [`ServerHost+ControlSupport.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerHost%2BControlSupport.swift) keeps immediate playback and runtime control settling logic out of the query surface.
- [`ServerState.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerState.swift) is the `@Observable` SwiftUI-facing projection of host state.
- [`HostStateModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostStateModels.swift) defines the shared host-native snapshots used by app UI, HTTP, and MCP consumers.
- [`HostEvents.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/HostEvents.swift) defines the typed host event surface used by non-UI consumers that need live change notifications without depending on SwiftUI observation.
- [`ServerRuntimeProtocol.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerRuntimeProtocol.swift) defines the narrow runtime seam and request-handle wrapper that the host owns.
- [`ServerRuntimeAdapter.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerRuntimeAdapter.swift) keeps the runtime boundary thin around the public `SpeakSwiftly.Runtime` actor.
- [`ServerModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ServerModels.swift), [`ProfileModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/ProfileModels.swift), [`QueueStatusModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/QueueStatusModels.swift), and [`JobEventModels.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/Host/JobEventModels.swift) split the transport and host-facing value models by concern instead of keeping one oversized payload file.
- The opt-in live suite is also now split by transport and support role instead of keeping one broad helper blob. [`E2EHTTPClient.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/E2EHTTPClient.swift), [`E2EMCPClient.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/E2EMCPClient.swift), [`E2EMCPEventStream.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/E2EMCPEventStream.swift), [`E2EPayloadHelpers.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/E2EPayloadHelpers.swift), [`E2ETransportWaiters.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/E2ETransportWaiters.swift), and [`SpeakSwiftlyServerE2EAudioRouteHelpers.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Tests/SpeakSwiftlyServerE2ETests/SpeakSwiftlyServerE2EAudioRouteHelpers.swift) keep MCP handshake logic, SSE observation, payload decoding, polling waiters, and audible-route stabilization separate.

The design is deliberately direct. Adding extra wrappers, managers, or intermediate layers here would be easy, but it would also be the kind of unnecessary complexity that makes a small localhost service harder to reason about, so the server is kept close to the typed runtime API on purpose. That means the service talks to the public `SpeakSwiftly.Runtime` surface, its public text normalizer, and its public event and summary types instead of reaching through the library boundary to construct raw worker requests itself.

The unified tool target is the one intentional widening of that model. It earns its keep because it unlocks LaunchAgent installation, status inspection, and future operator workflows while keeping the reusable `SpeakSwiftlyServer` module focused on embedding and host logic.

For repository maintenance, treat this standalone repository as the source of truth for package development, tags, and releases. When the `speak-to-user` monorepo adopts a new server version, prefer bumping that submodule pointer to a tagged `SpeakSwiftlyServer` release rather than a floating branch tip.

The repo-maintenance toolkit is now the maintainer-facing wrapper around that release flow. Use `scripts/repo-maintenance/validate-all.sh` for local validation, `scripts/repo-maintenance/sync-shared.sh` for deterministic repo-local sync hooks, and `scripts/repo-maintenance/release.sh` for the tagged release path after verification passes.

That tagged release path now also builds `SpeakSwiftlyServerTool` in `release` mode and stages the resulting binary under `.release-artifacts/<tag>/SpeakSwiftlyServerTool`, copies the required adjacent `Resources/default.metallib` into that same staged artifact directory from the sibling published `SpeakSwiftly` release-runtime metadata, and then refreshes `.release-artifacts/current` to that tagged build. The live LaunchAgent install path is expected to consume that staged release artifact by default.

The live audible e2e harness now also pins macOS built-in speakers immediately before audible server startup and again immediately before audible request submission. That route stabilization stays test-only, but it matters in practice because connected Bluetooth headphones can otherwise reclaim the default output device mid-run and fail an otherwise healthy live playback request.

## Repository Layout

- `Sources/SpeakSwiftlyServer/` contains the reusable `SpeakSwiftlyServer` library target with the HTTP, MCP, host, config, and LaunchAgent support code.
- `Sources/SpeakSwiftlyServerTool/` contains the unified `SpeakSwiftlyServerTool` executable wrapper and command entrypoint.
- `Tests/` contains the package test suite, including the opt-in end-to-end coverage paths and the dedicated CLI tests.
- `docs/` holds repo-local supporting documentation.
- `docs/maintainers/source-layout.md` summarizes the current source split so follow-on cleanup work can land in the right file family instead of regrowing monoliths.

## Verification

Current local maintainer baseline:

```bash
scripts/repo-maintenance/validate-all.sh
```

The package-level verification path that toolkit wraps is still:

```bash
swift build
swift test
```

If you want to check the unified tool surface explicitly, these are the direct smoke-test commands:

```bash
swift run SpeakSwiftlyServerTool help
swift run SpeakSwiftlyServerTool launch-agent print-plist
```

The current automated suite covers configuration parsing, queued live speech job completion semantics, generation and playback queue inspection, playback control routes, queue cancellation routes, startup failure before readiness, runtime degradation while active and queued speech jobs are in flight, in-memory retention and pruning, SSE replay and heartbeat behavior, route-level health, profile, clone, text-profile, and job lifecycle responses against a controlled typed runtime, the embedded MCP tool, prompt, and resource surface, the shared host snapshot stream and typed host event stream, plus an opt-in live end-to-end suite against a real `SpeakSwiftly` runtime:

```bash
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2ETests
```

That serialized live suite now mirrors the main `SpeakSwiftly` live workflows across both HTTP and MCP:

- voice-design profile creation, then silent playback, then audible playback
- clone creation with a provided transcript, then silent playback, then audible playback
- clone creation with inferred transcript loading, then silent playback, then audible playback
- Marvis all-vibes audible playback across three stored voice profiles
- queued Marvis audible live playback that pre-queues three jobs and verifies ordered drain behavior on one worker

If you want the underlying playback trace logs too, add `SPEAKSWIFTLY_PLAYBACK_TRACE=1` to that same command.

That live path now relies on the bundled resources shipped by the resolved [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) dependency instead of expecting a sibling published runtime checkout to provide `default.metallib`. SwiftPM dependency resolution and live runtime resources now come from the same `v2.3.1` package state declared in `Package.swift` and `Package.resolved`, even though the package itself is pinned by commit revision instead of a semantic-version requirement.

After the live suite passes, use `scripts/repo-maintenance/release.sh` for the tagged release flow so local validation, release artifact staging, tag creation, push, and GitHub release creation stay on the same documented path.

The remaining coverage work is now narrower and more cleanup-focused. The main open checks are trimming any transport-local wrappers that no longer buy clarity and expanding end-to-end assertions when the resolved runtime dependency surface shifts again.

## Roadmap

Planned work is tracked in [`ROADMAP.md`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/ROADMAP.md).

## License

This repository is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). See [LICENSE](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/LICENSE).
