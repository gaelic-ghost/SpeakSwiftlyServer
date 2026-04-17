# SpeakSwiftlyServer

Swift executable package for a shared localhost host process that exposes the public `SpeakSwiftly` runtime surface through an app-friendly HTTP API and an optional MCP surface.

## Table of Contents

- [Overview](#overview)
- [Setup](#setup)
- [Usage](#usage)
- [Codex Plugin](#codex-plugin)
- [Embedding](#embedding)
- [Configuration](#configuration)
- [Contributing](#contributing)
- [Development](#development)
- [Repository Layout](#repository-layout)
- [Verification](#verification)
- [Roadmap](#roadmap)
- [License](#license)

## Overview

This repository is the standalone Swift service for `SpeakSwiftly`. It uses [Hummingbird](https://github.com/hummingbird-project/hummingbird) to host one macOS process with job tracking, server-sent events, an operator-friendly HTTP API, and an optional MCP surface, while delegating speech, voice-profile management, and worker lifecycle to the typed `SpeakSwiftly` runtime.

### Deployment Targets

Current deployment targets are:

- macOS 15 and newer for the standalone server package and initial app-managed installation path
- iOS 18 and newer for a near-future app-facing reuse path once the host logic is split cleanly enough to be consumed from an iOS app

Linux support is a medium-term consideration rather than a current promise. A separate Linux implementation in Rust is more likely.

### Motivation

The goal is to give macOS apps one small, typed, app-managed service layer for local speech work without introducing a separate Python runtime or a second control model beside `SpeakSwiftly`.

The package stays intentionally narrow. Hummingbird owns transport hosting, `SpeakSwiftly` owns speech, profile, and runtime lifecycle behavior, `TextForSpeech` owns customizable text normalization, and the server keeps only the state it needs for retained snapshots, SSE replay, and MCP resources.

### Current SpeakSwiftly Alignment

This server is aligned to the current public library surface of its resolved [`SpeakSwiftly`](https://github.com/gaelic-ghost/SpeakSwiftly) `3.0.5` package dependency.

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

This package resolves its SwiftPM dependencies from GitHub source control in [`Package.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Package.swift) and locks the resolved revisions in [`Package.resolved`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Package.resolved). `SpeakSwiftly` uses a normal semantic-version requirement here, and this package currently follows it with an up-to-next-major constraint starting at `3.0.5`. The server's direct `TextForSpeech` dependency now tracks `0.17.0`, matching the current upstream `SpeakSwiftly` graph.

Build the package with SwiftPM through Xcode's selected toolchain:

```bash
xcrun swift build
```

Run the test suite:

```bash
xcrun swift test
```

The repository intentionally documents `xcrun swift ...` as the default path because the standalone Swiftly-selected Swift 6.3 toolchain in this environment currently reproduces a transitive `_NumericsShims` module-loading failure that does not appear under Xcode's matching Swift toolchain.

The repository also now carries a minimal [`.spi.yml`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/.spi.yml) so Swift Package Index can build and host documentation for the `SpeakSwiftlyServer` library target once the package is indexed. The follow-on DocC content plan lives in [`docs/maintainers/docc-spi-hosting-plan.md`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/docs/maintainers/docc-spi-hosting-plan.md).

## Usage

Run the server locally:

```bash
xcrun swift run SpeakSwiftlyServerTool
```

The package now uses distinct default localhost ports by entrypoint:

- direct executable startup defaults to `127.0.0.1:7338`
- LaunchAgent installs default to `127.0.0.1:7337`
- embedded app-owned sessions default to `127.0.0.1:7339`

All three entrypaths also support the same explicit runtime-profile-root override through `SPEAKSWIFTLY_PROFILE_ROOT`. Embedded app hosts can set that through `EmbeddedServerSession.Options(runtimeProfileRootURL:)`, foreground `serve` runs can set it through `--profile-root`, and LaunchAgent installs already stage it into the installed property list.

The package now ships one operator-facing executable product with both the foreground server entrypoint and the LaunchAgent maintenance surface:

```bash
xcrun swift run SpeakSwiftlyServerTool help
```

Running the tool without subcommands defaults to `serve`, and the same binary also exposes `launch-agent` subcommands for install, promotion, inspection, and maintenance work.

The most common local operator path is:

1. `xcrun swift run SpeakSwiftlyServerTool help`
2. `xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist`
3. `xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live --config-file ./server.yaml`
4. `xcrun swift run SpeakSwiftlyServerTool healthcheck`

To render the current per-user LaunchAgent property list without installing it:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist
```

To start the server directly in the foreground with an app- or operator-owned runtime profile root:

```bash
xcrun swift run SpeakSwiftlyServerTool serve \
  --profile-root ./runtime/profiles
```

To install or refresh the current user's LaunchAgent with a config file:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install \
  --config-file ./server.yaml
```

That command writes a user-owned property list into `~/Library/LaunchAgents`, points `ProgramArguments` at the staged release artifact under `.release-artifacts/current/SpeakSwiftlyServerTool serve`, and uses `launchctl bootstrap` / `bootout` against the current `gui/<uid>` domain. That default keeps the live service on the repo's staged release build instead of whichever debug or transient executable happened to invoke the command. The install output now also prints the exact staged executable path and modification time that the LaunchAgent is being asked to activate. If your tool binary lives somewhere other than the staged release path, pass `--tool-executable-path /absolute/path/to/SpeakSwiftlyServerTool` explicitly.

To promote the currently checked-out code into the live LaunchAgent-backed service in one supported step:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live \
  --config-file ./server.yaml
```

That command rebuilds the release executable from the current repository checkout, stages the executable and the sibling `SpeakSwiftly` metallib into `.release-artifacts/current`, refreshes the staged executable's ad-hoc code signature explicitly, and then reruns the LaunchAgent install path. Use `install` when the staged artifact is already the thing you want launchd to boot. Use `promote-live` when the intent is "make the live service run the current source checkout now" without a separate release tag flow.

To inspect or remove the installed LaunchAgent:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent status
xcrun swift run SpeakSwiftlyServerTool launch-agent uninstall
```

To verify the live service end to end without ad hoc `curl` or hand-built JSON-RPC:

```bash
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

That command probes `GET /healthz`, reads `GET /runtime/host`, and sends a real MCP `initialize` request to `/mcp`. It prints one concise summary that distinguishes "the process is up" from "both HTTP and MCP are actually healthy."

### App-Managed Install Contract

The current app-managed install contract is explicit and centered on one per-user layout instead of ad hoc paths:

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

## Codex Plugin

This repository is also packaged as a repo-local Codex plugin through [`.codex-plugin/plugin.json`](./.codex-plugin/plugin.json). The plugin points at the checked-in [`.mcp.json`](./.mcp.json) connection for the local `speak_swiftly` MCP server and the tracked [skills](./skills/) bundle that teaches Codex how to use the surface intentionally. When the plugin is installed through a Codex marketplace, Codex installs the plugin into its plugin cache and loads that installed copy from there, so the plugin surface is the normal Codex-side MCP wiring path. Users should not need to add a second handwritten global MCP entry just to reach the local server.

The first plugin pass currently ships five focused skills:

- [`speak-swiftly-mcp`](./skills/speak-swiftly-mcp/SKILL.md) for broad MCP orientation and workflow selection
- [`speak-swiftly-launchagent-setup`](./skills/speak-swiftly-launchagent-setup/SKILL.md) for installing, refreshing, validating, and removing the per-user LaunchAgent-backed service
- [`speak-swiftly-runtime-operator`](./skills/speak-swiftly-runtime-operator/SKILL.md) for runtime state, playback, queue, and request control
- [`speak-swiftly-voice-workflows`](./skills/speak-swiftly-voice-workflows/SKILL.md) for voice profiles, live speech, and retained artifacts
- [`speak-swiftly-text-profiles`](./skills/speak-swiftly-text-profiles/SKILL.md) for normalization styles, stored profiles, and replacement editing

The repo-local marketplace advertisement lives in [`.agents/plugins/marketplace.json`](./.agents/plugins/marketplace.json). That entry intentionally points at the repository root so this checkout itself can be discovered and installed as one local plugin instead of forcing a second nested plugin copy inside the repo.

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

Behind that small public API, the embedded path now uses one outer `ServiceGroup` owned by the
session wrapper. That outer group owns the package-level host lifecycle, optional config watching,
optional MCP readiness and drain, and the wrapped Hummingbird application as sibling long-running
services. Hummingbird still owns its own internal application `ServiceGroup`, but app code should
keep treating `EmbeddedServerSession` itself as the lifecycle boundary.

From app code, `ServerState` now also exposes app-facing control points for the cached voice-profile list, the effective default voice profile, runtime model lifecycle, and playback actions:

- `listVoiceProfiles()` and `refreshVoiceProfiles()`
- `setDefaultVoiceProfileName(_:)` and `clearDefaultVoiceProfileName()`
- `switchSpeechBackend(to:)`, `reloadModels()`, and `unloadModels()`
- `pausePlayback()`, `resumePlayback()`, `clearPlaybackQueue()`, and `cancelPlaybackRequest(_:)`

Those default-profile actions mutate the host-owned effective default that HTTP and MCP speech-generation requests use when `profile_name` is omitted. That app-managed default starts from configuration, can be changed live by the embedded app, and is persisted in the server runtime configuration so it survives process restart. Clearing the app-managed default removes the persisted override and falls back to the configured `app.defaultVoiceProfileName` when one exists.

The runtime control actions apply the refreshed host snapshot back onto `ServerState` before they return, so app code gets one coherent post-action picture of the current backend, worker stage, queues, playback state, and transport health instead of needing to stitch together several follow-up reads.

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
                        session = try? await EmbeddedServerSession.start(
                            options: .init(
                                port: 7811,
                                runtimeProfileRootURL: FileManager.default
                                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                                    .first?
                                    .appendingPathComponent("ExampleApp/SpeakSwiftlyRuntime", isDirectory: true)
                            )
                        )
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

If you do not pass `EmbeddedServerSession.Options(port:)`, the embedded host defaults to `127.0.0.1:7339`. Passing `options.port` applies that same value to the shared transport default and the concrete HTTP listener, so app code can claim an app-specific localhost port without mutating global environment state first.

If you pass `EmbeddedServerSession.Options(runtimeProfileRootURL:)`, that same root is forwarded into both the server-owned runtime configuration store and the underlying `SpeakSwiftly` startup path. That gives an app one explicit persistence root for runtime configuration, text-profile persistence, generated artifacts, and other runtime-owned profile data. For sandboxed macOS apps, Apple documents that `applicationSupportDirectory` already resolves inside the app container; for shared storage across the app and extensions or helpers, pass an App Group container URL instead.

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
- `SPEAKSWIFTLY_PROFILE_ROOT`

If `APP_CONFIG_FILE` points at a YAML file, the server loads it through [apple/swift-configuration](https://github.com/apple/swift-configuration) with environment variables taking precedence over YAML and YAML taking precedence over built-in defaults. The expected YAML shape mirrors the nested config reader keys:

```yaml
app:
  name: speak-swiftly-server
  environment: development
  host: 127.0.0.1
  port: 7338
  sseHeartbeatSeconds: 10
  completedJobTTLSeconds: 900
  completedJobMaxCount: 200
  jobPruneIntervalSeconds: 60
  http:
    enabled: true
    host: 127.0.0.1
    port: 7338
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
- The direct executable, LaunchAgent runtime, and embedded session each start from different built-in default ports before those environment or YAML overrides are applied.

`SPEAKSWIFTLY_PROFILE_ROOT` is the startup-time persistence-root override. Point it at the runtime profile root directory you want the server to own, not at a broader support directory. When it is set, the server runtime configuration store and the underlying `SpeakSwiftly` persistence paths both use that same root. This value is a startup ownership choice, not a live-reloadable YAML setting.

When `APP_CONFIG_FILE` is set, the server watches that YAML file for changes, but only the host-safe subset reloads live today. Bind addresses, ports, HTTP enablement, MCP enablement, MCP path, and MCP server metadata still require a process restart.

The full transport contract now lives in [API.md](API.md), including:

- the complete HTTP route inventory
- accepted-request semantics and SSE behavior
- text-profile, playback, and runtime control notes
- the MCP tool, resource, prompt, and subscription catalog
- transport-status semantics for the shared Hummingbird host

If you are integrating against the server rather than just running it locally, use [API.md](API.md) as the source of truth.

## Contributing

Use [CONTRIBUTING.md](CONTRIBUTING.md) for the maintainer workflow, validation path, live end-to-end coverage, release flow, and monorepo handoff rules.

The maintainer release contract is now intentionally split by checkout context: use `scripts/repo-maintenance/release-prepare.sh` from a feature branch or worktree when the job is "push this release candidate, open or update the PR, and queue auto-merge," then use `scripts/repo-maintenance/release-publish.sh` from local `main` after the PR merges when the job is "cut the actual tag and GitHub release." If local `main` is ahead of `origin/main`, that still counts as branch-side release-candidate work for this contract: get those commits onto a PR path first, then fast-forward `main` and publish from the synced release branch. The current details live in [docs/maintainers/release-workflow.md](docs/maintainers/release-workflow.md).

## Development

The shared runtime entrypoint lives in [`Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift) inside the `SpeakSwiftlyServer` module, with a thin executable wrapper in [`Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift) for the unified `SpeakSwiftlyServerTool` executable target.

The design stays deliberately direct. The service talks to the public `SpeakSwiftly.Runtime` surface, its public text normalizer, and its public event and summary types instead of reaching through the library boundary to construct raw worker requests itself.

For the maintainer workflow, source split, and release path, use [CONTRIBUTING.md](CONTRIBUTING.md), [docs/maintainers/source-layout.md](docs/maintainers/source-layout.md), and [docs/maintainers/release-workflow.md](docs/maintainers/release-workflow.md).

## Repository Layout

- `Sources/SpeakSwiftlyServer/` contains the reusable `SpeakSwiftlyServer` library target with the HTTP, MCP, host, config, and LaunchAgent support code.
- `Sources/SpeakSwiftlyServerTool/` contains the unified `SpeakSwiftlyServerTool` executable wrapper and command entrypoint.
- `Tests/` contains the package test suite, including the opt-in end-to-end coverage paths and the dedicated CLI tests.
- `docs/` holds repo-local supporting documentation.
- `docs/maintainers/source-layout.md` summarizes the current source split so follow-on cleanup work can land in the right file family instead of regrowing monoliths.

## Verification

Use [CONTRIBUTING.md](CONTRIBUTING.md) for:

- the maintainer validation path
- direct tool smoke-test commands
- opt-in live end-to-end coverage
- release verification and artifact staging notes

## Roadmap

Planned work is tracked in [`ROADMAP.md`](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/ROADMAP.md).

## License

This repository is licensed under the [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0). See [LICENSE](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/LICENSE).
