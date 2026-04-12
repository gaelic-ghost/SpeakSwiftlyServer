# Contributing

## Overview

This repository is the standalone Swift Package Manager home for `SpeakSwiftlyServer`. Treat it as the source of truth for package development, tags, and releases, even when a downstream monorepo consumes it as a submodule.

Start with [AGENTS.md](AGENTS.md) for the repo's package, architecture, and monorepo handoff rules. Use this document for the practical contribution path: local validation, source layout, documentation upkeep, and release-adjacent verification.

## Before You Start

- Treat `Package.swift` as the source of truth for package structure, dependencies, resources, and deployment targets.
- Prefer `swift package` subcommands for structural edits when SwiftPM already exposes the right operation.
- Keep package graph changes together in one pass, including `Package.swift`, `Package.resolved`, target layout, tests, and matching docs.
- Keep transport-local shaping at the HTTP and MCP edges. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- Keep the current standalone package baseline on macOS 15 while preserving a clean near-future iOS reuse path for the host and state model.

## Documentation Map

- [README.md](README.md) is the operator-facing entrypoint.
- [API.md](API.md) is the detailed HTTP and MCP contract reference.
- [docs/maintainers/source-layout.md](docs/maintainers/source-layout.md) is the maintainer map for the current source split.
- [ROADMAP.md](ROADMAP.md) tracks planned work and release-gate follow-through.

When the HTTP, MCP, LaunchAgent, release, or source-layout story changes, update the matching docs in the same pass instead of leaving the repo half-realigned.

## Local Workflow

The default first-pass package validation path is still:

```bash
swift build
swift test
```

The maintainer wrapper around that baseline is:

```bash
scripts/repo-maintenance/validate-all.sh
```

Use the unified tool smoke path when you want to verify the operator surface directly:

```bash
swift run SpeakSwiftlyServerTool help
swift run SpeakSwiftlyServerTool launch-agent print-plist
```

## Live End-To-End Verification

The opt-in live E2E coverage now runs as three serialized suites so maintainers can isolate transport and runtime failures without burning time on one giant rerun:

```bash
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2EHTTPWorkflowEntryTests
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2EMCPWorkflowEntryTests
SPEAKSWIFTLYSERVER_E2E=1 swift test --filter SpeakSwiftlyServerE2EControlSurfaceTests
```

Run those commands one at a time. Add `SPEAKSWIFTLY_PLAYBACK_TRACE=1` when you want the underlying playback trace logs too.

The suite split is:

- `HTTP Workflow Entry`
  Covers HTTP voice-design entry, HTTP clone entry with provided or inferred transcripts, HTTP Marvis audible live playback, and HTTP relative-path resolution.
- `MCP Workflow Entry`
  Covers the same entry and audible-runtime lanes through the MCP transport.
- `Control Surfaces`
  Covers HTTP and MCP text-profile control, playback control, queue mutation, catalog resources, prompts, and subscription behavior.

The live audible harness pins macOS built-in speakers immediately before audible startup and again immediately before audible request submission so Bluetooth route changes do not create false negatives.

## Source Layout

The shared runtime entrypoint lives in `Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`, and the unified executable wrapper lives in `Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift`.

For the current split of host, HTTP, MCP, model, and test files, use [docs/maintainers/source-layout.md](docs/maintainers/source-layout.md) instead of re-deriving ownership from file names ad hoc. If a change starts mixing HTTP, MCP, LaunchAgent, and host-state concerns into one file again, split it before adding more cases.

## Release Workflow

Use the repo-maintenance toolkit for the tagged release path:

```bash
scripts/repo-maintenance/release.sh
```

That path builds `SpeakSwiftlyServerTool` in `release` mode, stages the binary under `.release-artifacts/<tag>/SpeakSwiftlyServerTool`, copies the adjacent `Resources/default.metallib` into that staged artifact directory, and refreshes `.release-artifacts/current` to the tagged build. The live LaunchAgent install path is expected to consume that staged release artifact by default.

## Monorepo And Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and then delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.
