# SpeakSwiftlyServer

Standalone Swift package for hosting the local `SpeakSwiftly` runtime behind an app-friendly HTTP API, an optional MCP surface, and a small embedded Apple-platform API.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Embedding](#embedding)
- [Configuration](#configuration)
- [Codex Plugin](#codex-plugin)
- [Development](#development)
- [Repo Structure](#repo-structure)
- [Release Notes](#release-notes)
- [License](#license)

## Overview

### Status

This project is actively available and stable enough to try.

### What This Project Is

`SpeakSwiftlyServer` is the standalone Swift Package Manager home for the local `SpeakSwiftly` server layer. It ships one reusable library target for embedding and one executable target, `SpeakSwiftlyServerTool`, for running the shared localhost service, LaunchAgent maintenance commands, and health checks.

The package exposes three user-facing surfaces:

- a localhost HTTP API for app and operator control
- an optional MCP surface for tool, resource, and prompt access
- a small embedded Apple-platform API centered on the public `EmbeddedServer` observable model

### Motivation

The goal is to give macOS and near-future Apple-platform apps one small, typed local speech-service layer without adding a second runtime stack or forcing every consumer to rebuild the same transport and lifecycle glue around `SpeakSwiftly`.

## Quick Start

Build the package with Xcode's selected Swift toolchain:

```bash
xcrun swift build
```

Run the shared server executable locally:

```bash
xcrun swift run SpeakSwiftlyServerTool
```

Check the current operator surface:

```bash
xcrun swift run SpeakSwiftlyServerTool help
xcrun swift run SpeakSwiftlyServerTool healthcheck --base-url http://127.0.0.1:7338
```

For contributor setup, validation, release workflow, and live end-to-end coverage, use [CONTRIBUTING.md](./CONTRIBUTING.md).

## Usage

Run the server directly in the foreground:

```bash
xcrun swift run SpeakSwiftlyServerTool serve
```

Install or refresh the per-user LaunchAgent with a config file:

This command expects the staged tool artifact to already exist at `.release-artifacts/current/SpeakSwiftlyServerTool`. On a clean checkout, build and stage the release artifact first, or pass `--tool-executable-path /absolute/path/to/SpeakSwiftlyServerTool` explicitly.

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install \
  --config-file ./server.yaml
```

Promote the current checkout into the live LaunchAgent-backed service:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live \
  --config-file ./server.yaml
```

Inspect or remove the installed LaunchAgent:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent status
xcrun swift run SpeakSwiftlyServerTool launch-agent uninstall
```

The package uses distinct default localhost ports by entrypoint:

- direct executable startup defaults to `127.0.0.1:7338`
- LaunchAgent installs default to `127.0.0.1:7337`
- embedded app-owned sessions default to `127.0.0.1:7339`

The full transport contract lives in [API.md](./API.md).

## Embedding

The supported public embedding surface is `EmbeddedServer`, defined in [Sources/SpeakSwiftlyServer/Host/ServerState.swift](./Sources/SpeakSwiftlyServer/Host/ServerState.swift). App code owns that one observable object directly, calls `liftoff()`, binds UI to its observable properties, and uses the same object for runtime controls, playback controls, voice-profile actions, and direct live speech submission through `queueLiveSpeech(...)`.

```swift
import SpeakSwiftlyServer
import SwiftUI

@main
struct ExampleApp: App {
    @State private var server = EmbeddedServer(
        options: .init(
            port: 7811,
            runtimeProfileRootURL: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("ExampleApp/SpeakSwiftlyRuntime", isDirectory: true)
        )
    )

    var body: some Scene {
        WindowGroup {
            ContentView(server: server)
                .task {
                    try? await server.liftoff()
                }
        }
    }
}
```

If you do not pass `EmbeddedServer.Options(port:)`, the embedded host defaults to `127.0.0.1:7339`. If you pass `EmbeddedServer.Options(runtimeProfileRootURL:)`, that root is used for the runtime-owned persistence path as well as the server's runtime configuration store.

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

If `APP_CONFIG_FILE` points at a YAML file, the server loads it through [swift-configuration](https://github.com/apple/swift-configuration), with environment variables taking precedence over YAML and YAML taking precedence over built-in defaults.

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
    title: Speak Swiftly
```

The app-managed install layout is centered on one per-user location under `~/Library/Application Support/SpeakSwiftlyServer`, with logs in `~/Library/Logs/SpeakSwiftlyServer`. The package exposes that layout directly through [AppManagedInstallLayout.swift](./Sources/SpeakSwiftlyServer/AppManagedInstallLayout.swift).

## Codex Plugin

This repository is also packaged as a repo-local Codex plugin through [`.codex-plugin/plugin.json`](./.codex-plugin/plugin.json). The plugin points at the checked-in [`.mcp.json`](./.mcp.json) connection for the local `speak_swiftly` MCP server and the tracked [skills](./skills/) bundle that teaches Codex how to use the surface intentionally.

The first plugin pass ships focused skills for:

- broad MCP orientation
- LaunchAgent setup and maintenance
- runtime, playback, and queue control
- voice workflows
- text-profile workflows

## Development

The contributor and maintainer workflow lives in [CONTRIBUTING.md](./CONTRIBUTING.md).

Use that guide for:

- local setup and runtime expectations
- validation commands
- live end-to-end coverage
- pull request and release workflow
- monorepo and submodule handoff rules

## Repo Structure

```text
.
├── Sources/
│   ├── SpeakSwiftlyServer/
│   └── SpeakSwiftlyServerTool/
├── Tests/
├── docs/
├── API.md
├── CONTRIBUTING.md
├── Package.swift
└── README.md
```

- `Sources/SpeakSwiftlyServer/` contains the reusable library target.
- `Sources/SpeakSwiftlyServerTool/` contains the unified executable wrapper.
- `Tests/` contains unit, integration, and a small opt-in live E2E smoke suite.
- `docs/` contains maintainer-facing supporting documentation.

## Release Notes

Tagged release notes live in [GitHub Releases](https://github.com/gaelic-ghost/SpeakSwiftlyServer/releases) and the repo keeps matching historical release notes and release checklists under [docs/releases](./docs/releases/). Investigations and incident writeups live under [docs/investigations](./docs/investigations/).

## License

See [LICENSE](./LICENSE).
