# Contributing

Practical contributor and maintainer guide for working on `SpeakSwiftlyServer`, including local setup, validation, live end-to-end coverage, pull request workflow, and release handoff.

## Table of Contents

- [Overview](#overview)
- [Contribution Workflow](#contribution-workflow)
- [Local Setup](#local-setup)
- [Development Expectations](#development-expectations)
- [Pull Request Expectations](#pull-request-expectations)
- [Communication](#communication)
- [License and Contribution Terms](#license-and-contribution-terms)

## Overview

### Who This Guide Is For

This guide is for contributors and maintainers making source, docs, test, release, or operator-surface changes in the standalone `SpeakSwiftlyServer` repository.

### Before You Start

- Treat `Package.swift` as the source of truth for package structure, dependencies, resources, and deployment targets.
- Start with [AGENTS.md](./AGENTS.md) for the repo's package, architecture, and workflow rules.
- Keep package graph changes together in one pass, including `Package.swift`, `Package.resolved`, tests, and matching docs.
- Keep transport-local shaping at the HTTP and MCP edges. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- Preserve the current standalone package baseline on macOS 15 while keeping the host and state model friendly to the near-future iOS reuse path.
- Use Xcode's selected Swift toolchain through `xcrun`; this package declares Swift tools version 6.3 and macOS 15.0 in `Package.swift`.
- Expect the ordinary package lane to work without secrets, without changing the installed LaunchAgent, and without a live service. Live end-to-end coverage is opt-in and documented separately below.

## Contribution Workflow

### Choosing Work

Choose work from the current repo state rather than from stale assumptions. Use [README.md](./README.md) for the product and operator story, [ROADMAP.md](./ROADMAP.md) for planned work, the active maintainer docs under [docs/maintainers](./docs/maintainers/) when the task touches current architecture or workflow, the historical release records under [docs/releases](./docs/releases/) when you need prior release context, and [docs/investigations](./docs/investigations/) when you need past incident or debugging context.

For substantial changes, work on a feature branch instead of local `main`. When a task already has active release or bug-fix context on a branch, keep the follow-on work stacked on that line unless maintainers explicitly want a separate branch.

### Making Changes

Use the `xcrun` SwiftPM path intentionally in this repository:

```bash
xcrun swift build
xcrun swift test
```

This repo documents the `xcrun` form because the standalone Swiftly-selected Swift 6.3 toolchain currently reproduces a transitive `_NumericsShims` module-loading failure that does not appear when SwiftPM runs through Xcode's selected toolchain.

Keep work bounded and coherent:

- keep transport concerns at the HTTP and MCP edges
- keep host ownership narrow instead of adding new coordinator layers casually
- update docs in the same pass when HTTP, MCP, LaunchAgent, release, or source-layout behavior changes
- prefer the repo-maintenance scripts over one-off release or validation command chains when the repo already owns a workflow

### Asking For Review

Before asking for review, make sure the affected docs are in sync, the local validation path for the change has run, and any release-relevant or operator-facing behavior changes are called out plainly. For release work, use the documented branch-to-`main` split instead of trying to tag directly from a feature branch.

## Local Setup

### Runtime Config

The concrete runtime config surfaces in this repo are:

- [`server.yaml`](./server.yaml) for local config examples
- `APP_CONFIG_FILE` for YAML-backed configuration
- `SPEAKSWIFTLY_PROFILE_ROOT` for the runtime-owned profile and persistence root
- the staged release artifact under `.release-artifacts/current/` for LaunchAgent-owned runs

The shared server supports the same environment variables documented in [README.md](./README.md#configuration), including the `APP_*` transport settings and `SPEAKSWIFTLY_PROFILE_ROOT`.

The default build and unit-test loop does not require secrets or a running LaunchAgent. Use `server.yaml` only when you want to run the executable or inspect LaunchAgent-owned behavior locally.

### Runtime Behavior

For a fresh checkout, resolve dependencies once and then use the normal package loop:

```bash
xcrun swift package resolve
xcrun swift build
xcrun swift test
```

Use the unified tool surface when you want to inspect the operator path directly:

```bash
xcrun swift run SpeakSwiftlyServerTool help
xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

Direct executable runs default to `127.0.0.1:7338`. LaunchAgent installs default to `127.0.0.1:7337`. Embedded app-owned sessions default to `127.0.0.1:7339`.

For Codex plugin or hook changes, keep end-user behavior plugin-managed and use the repo-local `.codex/` files only as a development harness. The hook doctor summarizes the active install and voice-profile state:

```bash
node scripts/codex-hooks-doctor.mjs
```

When testing Codex marketplace add, remove, or upgrade behavior, keep Gale's personal Codex scope reserved for stable production installs. Use [docs/maintainers/plugin-install-testing.md](./docs/maintainers/plugin-install-testing.md) to run local checkout and Git-backed tests with a temporary `CODEX_HOME`, remove the test marketplace before cleanup, and leave Socket catalog-reference tests to the `socket` checkout.

Before any live end-to-end run, make sure the LaunchAgent-backed live service has released resident model memory through the live-service model unload preflight. Leave the installed service in place; the E2E helper runs on its own random ports and only needs comfortable memory headroom.

## Development Expectations

### Naming Conventions

Keep user-facing lifecycle vocabulary consistent across docs, scripts, and commands. In this repo that means preferring pairs like `install` and `uninstall`, treating `install` as the normal all-in-one staged-artifact plus LaunchAgent refresh path, keeping `promote-live` as the explicit staged-to-live promotion spelling, and avoiding alternate verbs for the same operator action unless a compatibility surface already requires them.

The built-in voice names are `swift-signal` and `swift-anchor`. Treat them as package-owned seed
identities, not user-owned example names. If an existing user profile already owns one of those
names, default-voice installation falls back to a `-builtin` suffix for the package copy instead of
overwriting or renaming the user's profile.

Normal voice-profile creation flows should remain user-owned. Built-in voice work should preserve a
clear distinction between user-authored profiles and package-authored system profiles, and should not
add public API fields unless application consumers need those fields to make a user-visible decision.

Match the current boundary language in the code:

- `EmbeddedServer` is the public app-owned embedding surface
- transport-local shaping belongs at the HTTP and MCP edges
- internal host ownership should stay behind the package boundary instead of leaking new public helpers casually

### Accessibility Expectations

This repository does not currently maintain a separate top-level `ACCESSIBILITY.md`. For relevant work, treat accessibility and operator clarity as part of normal change quality: keep user-facing logs, errors, and documentation explicit, readable, and unambiguous, and call out any new user-visible limitation plainly in docs or review notes when it matters.

### Verification

The maintainer validation entrypoint is:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

That validation path now includes the default package lane (`xcrun swift build` and
`xcrun swift test`) before the repo-owned DocC, formatting, and lint checks, so maintainers
do not need a separate "ordinary SwiftPM lane" command chain just to get the standard package
signal.

It also owns the repo-specific CLI smoke checks that prove the built tool still renders
`help` output and LaunchAgent property lists correctly, so GitHub can rely on one
authoritative maintainer lane instead of duplicating package build, test, and DocC steps in a
second workflow.

Direct formatter and linter commands are:

```bash
swiftformat --lint --config .swiftformat .
swiftformat --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

The live end-to-end gate is intentionally small and should still be run in one foreground process at a time:

```bash
curl -X POST http://127.0.0.1:7337/models/unload
SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter ServerTransportE2ETests
curl -X POST http://127.0.0.1:7337/models/reload
```

This suite is a transport-owned smoke pass, not a second copy of SpeakSwiftly's broader worker end-to-end coverage. Keep this repo's live E2E focused on proving the shipped server can boot the published runtime, answer over HTTP and MCP, deliver MCP resource updates, and retain completed request state.

## Pull Request Expectations

Summarize what changed, why it changed, and what reviewers should pay attention to first. For release work, make sure the branch-side candidate preparation is complete before handing it off to `main` for the final publish step.

## Communication

Raise uncertainty early when a task starts pushing on architecture, release semantics, or live-service behavior. If the clean path needs wider scope than the original request, say so before the change sprawls. If a behavior changed across docs, HTTP, MCP, LaunchAgent, or embedding surfaces, mention that explicitly instead of assuming reviewers will reconstruct it from the diff.

## Documentation Map

- [README.md](./README.md) is the product and operator-facing entrypoint.
- [API.md](./API.md) is the detailed HTTP and MCP contract reference.
- [docs/maintainers/source-layout.md](./docs/maintainers/source-layout.md) is the maintainer map for the current source split.
- [docs/maintainers/release-workflow.md](./docs/maintainers/release-workflow.md) is the current `maintain-project-repo` release contract.
- [docs/maintainers](./docs/maintainers/) holds active maintainer-facing architecture, workflow, and cleanup notes.
- [docs/releases](./docs/releases/) holds historical release notes and release checklists.
- [docs/investigations](./docs/investigations/) holds historical investigations and incident writeups.

## Monorepo and Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and then delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.

## Release Workflow

Use the repo-maintenance release entrypoint intentionally:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

Run standard mode from a feature branch or worktree. It validates the checkout, creates the annotated tag, pushes the branch and tag, opens or updates the release PR, watches CI, checks review state, merges the PR, fast-forwards local `main`, creates the GitHub release, and cleans up merged branches when safe.

The release flow runs `scripts/repo-maintenance/version-bump.sh` before tagging so version-bearing repo surfaces move with the release. Run live-service refresh or staged-artifact promotion only when that operation is explicitly part of the release task.

For the detailed contract and edge cases, use [docs/maintainers/release-workflow.md](./docs/maintainers/release-workflow.md).

## License and Contribution Terms

This repository is licensed under [Apache License 2.0](./LICENSE). By contributing, you are contributing changes under that same project license.
