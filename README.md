# SpeakSwiftlyServer

Standalone Swift package for hosting the local `SpeakSwiftly` runtime behind an app-friendly HTTP API, an optional MCP surface, and a small embedded Apple-platform API.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Development](#development)
- [Repo Structure](#repo-structure)
- [Release Notes](#release-notes)
- [License](#license)
- [Embedding](#embedding)
- [Configuration](#configuration)
- [Codex Plugin](#codex-plugin)

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

`SpeakSwiftlyServer` currently targets macOS 15.0 and Swift 6.3. Build the
package with Xcode's selected Swift toolchain:

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

When the default staged tool path is used, this command first builds and stages the current checkout at `.release-artifacts/current/SpeakSwiftlyServerTool`, refreshes its bundled Metal resource, refreshes the staged ad-hoc signature, and then writes and bootstraps the LaunchAgent. Pass `--tool-executable-path /path/to/SpeakSwiftlyServerTool` only when you intentionally want to install a specific prebuilt executable instead.

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install \
  --config-file ./server.yaml
```

Use the explicit promotion command when you want the lower-level "build, stage, then reinstall" spelling. This is mostly useful for release or operator scripts that want to name the promotion step directly; ordinary default-path refreshes can use `install`.

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

### Planned Default Voices

The planned built-in default voice pair is `swift-signal` and `swift-anchor`. `swift-signal` is the
bright, crisp, responsive default voice; `swift-anchor` is the grounded, steady, reassuring default
voice.

These planned defaults are package-owned seed voices, not Gale's personal saved profiles. If a user
already has a profile with one of those names, the installer should use a `-builtin` fallback such as
`swift-signal-builtin` for the package-owned copy instead of overwriting the user's profile.

The full transport contract lives in [API.md](./API.md).

## Development

The contributor and maintainer workflow lives in [CONTRIBUTING.md](./CONTRIBUTING.md). This section is only the product README's short handoff for people who want to build or validate the package locally before making changes.

Use that guide for:

- local setup and runtime expectations
- validation commands
- live end-to-end coverage
- pull request and release workflow
- monorepo and submodule handoff rules

The short version for a fresh checkout is:

- use `xcrun swift test` for the normal package-development loop
- use `sh scripts/repo-maintenance/validate-all.sh` for the full maintainer and CI gate
- use `node scripts/codex-hooks-doctor.mjs` when changing the Codex plugin or hook surface
- use `scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z --skip-version-bump` for the aligned release flow
- use `scripts/repo-maintenance/config/profile.env` to confirm the active `swift-package` maintainer profile

### Setup

Resolve package dependencies with the Xcode-selected Swift toolchain:

```bash
xcrun swift package resolve
```

Install the local tools used by the full maintainer gate when you are running it outside CI:

```bash
brew install swiftformat swiftlint
```

### Workflow

Use a feature branch for normal repo work. Keep Swift package changes grounded in `Package.swift`, keep source and docs updates together when public behavior changes, and use [CONTRIBUTING.md](./CONTRIBUTING.md) for pull request, live-service, and monorepo handoff rules.

### Validation

Run the full local maintainer gate before handing off a complete change:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

For a narrower package-development loop, run:

```bash
xcrun swift build
xcrun swift test
```

## Repo Structure

```text
.
├── Sources/
│   ├── SpeakSwiftlyServer/
│   └── SpeakSwiftlyServerTool/
├── Tests/
├── docs/
├── hooks/
├── skills/
├── .codex-plugin/
├── API.md
├── CONTRIBUTING.md
├── Package.swift
└── README.md
```

- `Sources/SpeakSwiftlyServer/` contains the reusable library target.
- `Sources/SpeakSwiftlyServerTool/` contains the unified executable wrapper.
- `Tests/` contains unit, integration, and a small opt-in live E2E smoke suite.
- `docs/` contains maintainer-facing supporting documentation.
- `hooks/` and `skills/` contain the plugin-managed Codex hook and skill surfaces.
- `.codex-plugin/` contains the Codex plugin manifest for this repository.

## Release Notes

Tagged release notes live in [GitHub Releases](https://github.com/gaelic-ghost/SpeakSwiftlyServer/releases) and the repo keeps matching historical release notes and release checklists under [docs/releases](./docs/releases/). Investigations and incident writeups live under [docs/investigations](./docs/investigations/).

## License

See [LICENSE](./LICENSE).

## Embedding

The supported public embedding surface is `EmbeddedServer`, defined in [Sources/SpeakSwiftlyServer/Host/ServerState.swift](./Sources/SpeakSwiftlyServer/Host/ServerState.swift). App code owns that one observable object directly, calls `liftoff()`, binds UI to its observable properties, and uses the same object for runtime controls, playback controls, voice-profile actions, and direct live speech submission through `queueLiveSpeech(...)`, including the shared `SpeakSwiftly.RequestContext` metadata model when one request needs caller-origin details.

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

If you do not pass `EmbeddedServer.Options(port:)`, the embedded host defaults to `127.0.0.1:7339`. If you pass `EmbeddedServer.Options(runtimeProfileRootURL:)`, the server treats that as its profile-store root and bridges it at startup into the broader persistence root expected by the current pinned `SpeakSwiftly` runtime, while keeping the server's own runtime-configuration snapshot aligned with the same on-disk state.

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

If `APP_CONFIG_FILE` points at a YAML file, the server loads it through the package's Foundation URL-backed YAML provider and [swift-configuration](https://github.com/apple/swift-configuration), with environment variables taking precedence over YAML and YAML taking precedence over built-in defaults. Missing config files fail startup loudly. LaunchAgent install and refresh paths seed the default `~/Library/Application Support/SpeakSwiftlyServer/server.yaml` from the bundled template when that canonical file is missing.

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

This repository is also packaged as a repo-local Codex plugin through [`.codex-plugin/plugin.json`](./.codex-plugin/plugin.json). The plugin points at the checked-in [`.mcp.json`](./.mcp.json) connection for the local `speak_swiftly` MCP server, the tracked [skills](./skills/) bundle that teaches Codex how to use the surface intentionally, and the plugin-managed [hooks](./hooks/hooks.json) that can speak final Codex replies through the local service.

The plugin can be installed without using `socket` through Codex's Git-backed marketplace flow. The repo-local marketplace lives at [`.agents/plugins/marketplace.json`](./.agents/plugins/marketplace.json), and its single plugin entry points at this repository root with `source.path` set to `./` because the root directory is also the plugin root.

Prefer the official Git-backed install and update path:

```bash
codex plugin marketplace add gaelic-ghost/SpeakSwiftlyServer
codex plugin marketplace upgrade SpeakSwiftlyServer
```

After Codex adds or upgrades the marketplace, restart Codex, open the plugin directory in the Codex GUI, choose the `SpeakSwiftlyServer` marketplace, and install or enable `speak-swiftly-server` there. Manual local clone marketplaces and personal copied-payload entries are development, unpublished-testing, and fallback paths rather than the default user install story.

The [`socket`](https://github.com/gaelic-ghost/socket) repository is Gale's plugin superproject and marketplace catalog. Installing from the Git-backed socket marketplace is useful when you want SpeakSwiftlyServer plus Gale's other Codex plugins available from one marketplace:

```bash
codex plugin marketplace add gaelic-ghost/socket
codex plugin marketplace upgrade socket
```

After adding `socket`, restart Codex, open the plugin directory in the Codex GUI, choose the `Socket` marketplace, and install or enable `speak-swiftly-server` plus any companion plugins you want. Use an explicit ref such as `gaelic-ghost/SpeakSwiftlyServer@vX.Y.Z` only when you want a pinned reproducible install rather than the release-aligned default branch.

End users should rely on the plugin-managed hook setup rather than copying repo-local `.codex` files into their own Codex home. The repo-local `.codex/` files are a development harness for testing hook payloads and notification behavior from this checkout.

To inspect the installed hook and voice surfaces, run:

```bash
node scripts/codex-hooks-doctor.mjs
```

The doctor checks whether the plugin manifest declares hooks, whether a legacy global `~/.codex/hooks.json` entry is still pointing at this checkout, whether the live service is reachable, and whether the hook voice profile matches the runtime voice-profile inventory.

The first plugin pass ships focused skills for:

- broad MCP orientation
- LaunchAgent setup and maintenance
- runtime, playback, and queue control
- voice workflows
- text-profile workflows
