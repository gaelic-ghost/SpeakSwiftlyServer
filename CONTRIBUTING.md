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
- [docs/maintainers/release-workflow.md](docs/maintainers/release-workflow.md) is the maintainer release contract for feature branches, worktrees, and the final publish step on `main`.
- [docs/maintainers/docc-spi-hosting-plan.md](docs/maintainers/docc-spi-hosting-plan.md) tracks the first DocC pass and the SPI-hosted documentation plan.
- [ROADMAP.md](ROADMAP.md) tracks planned work and release-gate follow-through.

When the HTTP, MCP, LaunchAgent, release, or source-layout story changes, update the matching docs in the same pass instead of leaving the repo half-realigned.

## Local Workflow

The default first-pass package validation path is still:

```bash
xcrun swift build
xcrun swift test
```

Use the `xcrun` form intentionally. In this repo, the standalone Swiftly-selected Swift 6.3 toolchain currently reproduces a transitive `_NumericsShims` module-loading failure that does not appear when SwiftPM runs through Xcode's selected toolchain.

The maintainer wrapper around that baseline is:

```bash
scripts/repo-maintenance/validate-all.sh
```

## Formatting

SpeakSwiftlyServer uses the checked-in [.swiftformat](.swiftformat) file as the repository source of truth for Swift formatting and the checked-in [.swiftlint.yml](.swiftlint.yml) file for a deliberately small set of non-formatting policy checks.

Use these commands from the package root:

```bash
sh scripts/repo-maintenance/validate-all.sh
swiftformat --lint --config .swiftformat .
swiftformat --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

Use `validate-all.sh` when you want the shared repo-maintenance gate that backs the sample pre-commit hook and the repo-maintenance GitHub Actions workflow. Use the first `swiftformat` command when you want to inspect formatting drift without rewriting files. Use the second `swiftformat` command when you intentionally want to apply formatting changes. Use the SwiftLint command for the smaller safety and maintainability checks that intentionally stay outside SwiftFormat.

Treat SwiftFormat as the primary style tool in this repository. Keep SwiftLint focused on non-formatting policy checks instead of duplicating formatter behavior.

Use the unified tool smoke path when you want to verify the operator surface directly:

```bash
xcrun swift run SpeakSwiftlyServerTool help
xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist
```

The `help` path now also has CI coverage so obvious executable-surface regressions are less likely to escape into release or Swift Package Index builds. The `help` path is expected to exit with the tool's usage-error status while still printing the supported command surface.

If your local clone wants automatic hook enforcement, copy `scripts/repo-maintenance/hooks/pre-commit.sample` into `.git/hooks/pre-commit` and make it executable. That hook intentionally stays optional, but it runs the same validation entry point as the repo-maintenance workflow.

## Live End-To-End Verification

The opt-in live E2E coverage now runs as three serialized suites so maintainers can isolate transport and runtime failures without burning time on one giant rerun:

```bash
SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter HTTPWorkflowE2ETests
SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter MCPWorkflowE2ETests
SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter ControlE2ETests
```

Run those commands one at a time, in separate foreground processes, and never overlap them. Do not background one suite while starting another, and do not run the HTTP, MCP, or control suites in parallel.

Before any live E2E run, stop the LaunchAgent-backed live service first:

```bash
./.release-artifacts/current/SpeakSwiftlyServerTool launch-agent uninstall
```

That shutdown step matters because the live service and the test-owned helper can both speak audible test strings if they are alive together. The harness now fails fast when the LaunchAgent-backed service is still loaded or when another `SpeakSwiftlyServerTool serve` helper is already running, because live E2E coverage is intentionally a one-speaking-server surface.

Add `SPEAKSWIFTLY_PLAYBACK_TRACE=1` when you want the underlying playback trace logs too.

The suite split is:

- `HTTP Workflow Entry`
  Covers HTTP voice-design entry, HTTP clone entry with provided or inferred transcripts, HTTP Marvis audible live playback, and HTTP relative-path resolution.
- `MCP Workflow Entry`
  Covers the same entry and audible-runtime lanes through the MCP transport.
- `Control Surfaces`
  Covers HTTP and MCP text-profile control, playback control, queue mutation, catalog resources, prompts, and subscription behavior.

The checked-in `Tests/SpeakSwiftlyServer-Package-E2E.xctestplan` is the dedicated live E2E plan for the `SpeakSwiftlyServerE2ETests` target, while `Tests/SpeakSwiftlyServer-Package-Main.xctestplan` stays on the non-E2E targets. The suite-level `.serialized` traits in `Tests/SpeakSwiftlyServerE2ETests/E2ESuite.swift` keep each suite ordered within a process, and the helper-side execution-lane lock keeps separate live E2E processes from owning the speaking server at the same time.

The live audible harness pins macOS built-in speakers immediately before audible startup and again immediately before audible request submission so Bluetooth route changes do not create false negatives.

## Source Layout

The shared runtime entrypoint lives in `Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`, and the unified executable wrapper lives in `Sources/SpeakSwiftlyServerTool/SpeakSwiftlyServerToolMain.swift`.

For the current split of host, HTTP, MCP, model, and test files, use [docs/maintainers/source-layout.md](docs/maintainers/source-layout.md) instead of re-deriving ownership from file names ad hoc. If a change starts mixing HTTP, MCP, LaunchAgent, and host-state concerns into one file again, split it before adding more cases.

## Release Workflow

Use the repo-maintenance toolkit's release split intentionally:

```bash
scripts/repo-maintenance/release-prepare.sh --version vX.Y.Z
scripts/repo-maintenance/release-publish.sh --version vX.Y.Z --skip-live-service-refresh
```

Use `release-prepare.sh` from a feature branch or worktree when the job is "push this release candidate, open or update the PR, and queue auto-merge." Use `release-publish.sh` from local `main` after that PR merges when the job is "cut the actual tag and GitHub release." The compatibility wrapper `release.sh` now defaults to the publish path and refuses to run from a non-release branch.

The publish path builds `SpeakSwiftlyServerTool` in `release` mode, stages the binary under `.release-artifacts/<tag>/SpeakSwiftlyServerTool`, copies the adjacent `Resources/default.metallib` into that staged artifact directory, refreshes `.release-artifacts/current` to the tagged build, tags `HEAD`, pushes the tag, creates the GitHub release, and can refresh the live per-user LaunchAgent-backed service by default with `~/Library/Application Support/SpeakSwiftlyServer/server.yaml`. Use `--skip-live-service-refresh` when you need a tag-only or artifact-only release pass, or `--live-service-config-file /absolute/path/to/server.yaml` when the live service should be refreshed against a different config file.

For the current release contract, use [docs/maintainers/release-workflow.md](docs/maintainers/release-workflow.md). For the historical patch release target and the first Swift Package Index submission pass, use [docs/maintainers/v3.1.1-release-and-spi-checklist.md](docs/maintainers/v3.1.1-release-and-spi-checklist.md) instead of reconstructing that older flow from memory.

## Monorepo And Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and then delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.
