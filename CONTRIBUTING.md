# Contributing

Practical contributor and maintainer guide for working on `SpeakSwiftlyServer`, including local setup, validation, live end-to-end coverage, pull request workflow, and release handoff.

## Table of Contents

- [Overview](#overview)
- [Contribution Workflow](#contribution-workflow)
- [Local Setup](#local-setup)
- [Development Expectations](#development-expectations)
- [Maintainer Reference](#maintainer-reference)
- [Pull Request Expectations](#pull-request-expectations)
- [Communication](#communication)
- [Documentation Map](#documentation-map)
- [License and Contribution Terms](#license-and-contribution-terms)

## Overview

### Who This Guide Is For

This guide is for contributors and maintainers making source, docs, test, release, or operator-surface changes in the standalone `SpeakSwiftlyServer` repository.

### Before You Start

- Treat `Package.swift` as the source of truth for package structure, dependencies, resources, and deployment targets.
- Start with [AGENTS.md](./AGENTS.md) for the repo's package, architecture, and workflow rules.
- Keep package graph changes together in one pass, including `Package.swift`, `Package.resolved`, tests, and matching docs.
- Keep transport-local shaping at the HTTP and MCP edges. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- Keep `SpeakSwiftlyServer` and `SpeakSwiftlyServerTool` as the supported public entrypoints. The `SSSCore`, `SSSHTTP`, and `SSSMCP` targets are package-internal implementation modules.
- Preserve the current standalone package baseline on macOS 15 while keeping the host and state model friendly to the near-future iOS reuse path.
- Use Xcode's selected Swift toolchain through `xcrun`; this package declares Swift tools version 6.3 and macOS 15.0 in `Package.swift`.
- Expect the ordinary package lane to work without secrets, without changing the installed LaunchAgent, and without a live service. Live end-to-end coverage is opt-in and documented separately below.

## Contribution Workflow

### Choosing Work

Choose work from the current repo state rather than from stale assumptions. Use [README.md](./README.md) for the product and agent-facing story, [ROADMAP.md](./ROADMAP.md) for planned work, the active maintainer docs under [docs/maintainers](./docs/maintainers/) when the task touches current architecture or workflow, the historical release records under [docs/releases](./docs/releases/) when you need prior release context, and [docs/investigations](./docs/investigations/) when you need past incident or debugging context.

For substantial changes, work on a feature branch instead of local `main`. When a task already has active release or bug-fix context on a branch, keep the follow-on work stacked on that line unless maintainers explicitly want a separate branch.

A feature branch is the local work surface, not an automatic publishing step. Push the branch or open a pull request only when the maintainer asks for remote review, asks for a push, asks for a release, or intentionally runs the repo-owned release workflow. For ordinary local implementation or documentation passes, finish the coherent local change, run the relevant local validation, inspect the diff, and report the status before starting any GitHub handoff.

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

Before asking for review, make sure the affected docs are in sync, the local validation path for the change has run, and any release-relevant or operator-facing behavior changes are called out plainly. Do not open a pull request just because local edits exist; treat pull requests as explicit review or release handoffs. For release work, use the documented branch-to-`main` split instead of trying to tag directly from a feature branch.

## Local Setup

### Runtime Config

The concrete runtime config surfaces in this repo are:

- [`server.yaml`](./server.yaml) for local config examples
- the bundled `default-server.yaml` resource in the `SSSCore` target
- the persisted `~/Library/Application Support/SpeakSwiftlyServer/server.yaml` config seeded from that resource
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
- the staged release artifact under `.release-artifacts/current/` for LaunchAgent-owned runs

The server loads persisted YAML through the package's Foundation URL-backed YAML provider and `swift-configuration`; environment variables remain a developer override surface, and persisted YAML takes precedence over bundled defaults. The normal standalone path seeds `~/Library/Application Support/SpeakSwiftlyServer/server.yaml` from the bundled `default-server.yaml` resource when that persisted file is missing. Runtime startup choices live in the same document under `app.runtime`, so HTTP, MCP, embedded, and tool-managed saves no longer maintain a separate runtime JSON file.

The tool-managed LaunchAgent layout is centered on one per-user location under `~/Library/Application Support/SpeakSwiftlyServer`, with logs in `~/Library/Logs/SpeakSwiftlyServer`. The `SpeakSwiftlyServerTool` target owns that layout through `AppManagedInstallLayout.swift`; the library target stays focused on embedded server state, runtime hosting, HTTP, and MCP.

The default build and unit-test loop does not require secrets or a running LaunchAgent. Use `server.yaml` only when you want to run the executable, inspect configuration loading, or inspect LaunchAgent-owned behavior locally.

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

The server-owned Application Support config is LaunchAgent-oriented and defaults to `127.0.0.1:7337`. The in-memory default profiles still reserve `7338` for ad hoc standalone executable configs and `7339` for embedded app-owned configs when a config file omits an explicit port.

For Codex plugin or hook changes, keep end-user behavior plugin-managed and use the repo-local `.codex/` files only as a development harness. Current Codex builds require both `features.hooks = true` and `features.plugin_hooks = true` before installed plugin lifecycle hooks run; do not add `~/.codex/hooks.json` as a normal repair path. Codex 0.129.0 stores per-hook review decisions under `[hooks.state]` in `~/.codex/config.toml`; use the hooks settings panel to approve expected Speak Swiftly hooks instead of bypassing review with a user-level hook. The hook doctor summarizes the active install, hook feature flags, hook review state, and voice-profile state:

```bash
node scripts/codex-hooks-doctor.mjs
```

When testing Codex plugin payload behavior, keep Gale's personal Codex scope reserved for stable production installs. Use [docs/maintainers/plugin-install-testing.md](./docs/maintainers/plugin-install-testing.md) to inspect this repository's manifest, hooks, skills, and MCP payload locally, and leave marketplace add, upgrade, remove, and catalog-reference tests to the `socket` checkout.

Before any live end-to-end run, make sure the LaunchAgent-backed live service has released resident model memory through the live-service model unload preflight. Leave the installed service in place; the E2E helper runs on its own random ports and only needs comfortable memory headroom.

### System Voice Profile Resources

Create package-owned system voice profiles through the upstream `SpeakSwiftly` command plugin from
this package checkout:

```bash
xcrun swift package plugin --allow-writing-to-package-directory upsert-system-voice-profile \
  --target SSSCore \
  --name swift-signal \
  --text "A short source text for the generated system voice." \
  --vibe femme \
  --voice-description "A clear, bright, steady technical-assistant voice."
```

The `upsert-system-voice-profile` command plugin is the normal authoring surface for
`Sources/SSSCore/Resources/SystemProfiles/profiles/<profile-name>/`. Do not manually copy
profiles out of a live runtime profile store or hand-edit generated manifests to make them appear
system-authored. If `xcrun swift package plugin --list` does not show the `upsert-system-voice-profile`
verb, treat that as a package/plugin exposure issue to fix before generating resources.

Profile generation uses MLX/Metal. If a Codex sandboxed process cannot see the default Metal GPU,
rerun the command plugin from a normal user shell or an explicitly unsandboxed command. Use the
lower-level `SpeakSwiftlyTool --system-profile-resource-root` entrypoint only for upstream debugging
or plugin implementation work, not for ordinary server resource authoring.

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

Remote GitHub Actions intentionally runs the lighter CI wrapper:

```bash
sh scripts/repo-maintenance/validate-ci.sh
```

That wrapper keeps the toolkit, plugin, workflow, package build, and package test checks on pull requests and `main` pushes while leaving DocC, CLI smoke, SwiftFormat, SwiftLint, and live E2E to the local maintainer and release gates.

Direct formatter and linter commands are:

```bash
swiftformat --lint --config .swiftformat .
swiftformat --config .swiftformat .
swiftlint lint --config .swiftlint.yml
```

The live end-to-end gate is intentionally small and should still be run in one foreground process at a time:

```bash
sh scripts/repo-maintenance/validate-local-e2e.sh
```

The script unloads resident models from the installed LaunchAgent-backed service, runs `SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter ServerTransportE2ETests`, and reloads resident models afterward. The standard release workflow runs this local live E2E gate by default after the normal maintainer validation gate. Use `--skip-local-e2e` on `release.sh` only when the current release intentionally cannot touch the live service on this machine and another concrete live E2E signal exists for the release candidate.

This suite is a transport-owned smoke pass, not a second copy of SpeakSwiftly's broader worker end-to-end coverage. Keep this repo's live E2E focused on proving the shipped server can boot the published runtime, answer over HTTP and MCP, deliver MCP resource updates, and retain completed request state.

## Maintainer Reference

### Embedding

The supported public embedding surface is `EmbeddedServer`, defined in `Sources/SpeakSwiftlyServer/EmbeddedServer.swift`. App code owns that one observable object directly, calls `liftoff()`, binds UI to its observable properties, and uses the same object for runtime controls, playback controls, voice-profile actions, and direct live speech submission through `queueLiveSpeech(...)`.

Embedded app callers should pass `SpeakSwiftly.RequestContext` directly when the app has richer caller, project, or origin metadata than the server can infer. HTTP and MCP speech surfaces add transport defaults for that context automatically.

If callers do not pass `EmbeddedServer.Options(port:)`, the embedded host defaults to `127.0.0.1:7339`. If callers pass `EmbeddedServer.Options(runtimeProfileRootURL:)`, the server treats that as its profile-store root, resolves it to the containing state root, and passes that state root directly into `SpeakSwiftly.liftoff(configuration:stateRootURL:)`, while keeping the server's own runtime-configuration snapshot aligned with the same on-disk state.

### Codex Plugin

This repository is the canonical payload source for the Socket-managed `Speak Swiftly` Codex plugin. The root `.codex-plugin/plugin.json` points at the checked-in `.mcp.json` connection, the tracked `skills/` bundle, and the plugin-managed `hooks/hooks.json` file.

This repo does not maintain Claude Code or Anthropic plugin parity. Keep plugin work focused on the Socket-managed Codex path, and remove tracked Claude-specific docs, manifests, scripts, or examples if they appear.

Default user-facing install and update examples should use the Socket marketplace entry:

```bash
codex plugin marketplace add gaelic-ghost/socket
codex plugin marketplace upgrade socket
```

The plugin identity is `speak-swiftly`, with display name `Speak Swiftly`; older standalone installs may still appear as `speak-swiftly-server` until upgraded or disabled. Do not use a repo-local marketplace file from this checkout for normal installs. Socket is the supported marketplace entrypoint for end users.

Marketplace installation gives Codex the plugin payload: skills, MCP registration for `http://127.0.0.1:7337/mcp`, and lifecycle hooks. It does not by itself start, install, or update the native Swift service.

End users should start with plugin-managed hook setup rather than copying repo-local `.codex` files into their own Codex home. User-level `~/.codex/hooks.json` Speak Swiftly entries are duplicate or legacy repair targets, not the healthy default path.

Current Codex builds require both `features.hooks = true` and `features.plugin_hooks = true` before installed plugin lifecycle hooks become runnable. `hooks` enables the hook system generally; `plugin_hooks` enables hook sources loaded from installed plugins. Codex 0.129.0 also persists per-hook review decisions under `[hooks.state]` in `~/.codex/config.toml`; missing Speak Swiftly entries there mean the operator needs to approve the plugin-managed hooks in Codex settings.

Use the hook doctor as the first audit surface for installed plugin metadata, duplicate user-level hooks, hook review state, live runtime reachability, and recent hook logs:

```bash
node scripts/codex-hooks-doctor.mjs
node scripts/codex-hooks-doctor.mjs --repair-plan
```

For install-surface testing, use [docs/maintainers/plugin-install-testing.md](./docs/maintainers/plugin-install-testing.md). Keep personal production Codex installs untouched by running manifest and payload checks from this repository; run actual marketplace add, upgrade, and catalog-reference tests from the `socket` checkout.

### Monorepo and Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and then delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.

### Release Workflow

Use the repo-maintenance release entrypoint intentionally:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

Run standard mode from a feature branch or worktree while keeping a separate local checkout on `main`. The release worktree owns the candidate and PR; after merge, the script fast-forwards the `main` checkout, creates the tag from that reviewed commit, publishes the GitHub release, promotes the local service, and cleans up merged branches when safe.

The release flow runs `scripts/repo-maintenance/version-bump.sh` before tagging so version-bearing repo surfaces move with the release. After the release PR is merged, local `main` is fast-forwarded, the annotated tag is pushed, and the GitHub release exists, the standard flow refreshes the LaunchAgent-backed live service from the synced `main` checkout and runs the HTTP plus MCP healthcheck. Use `--skip-live-service-update` only when this machine should not be touched by that release.

Before the release branch is pushed, the standard flow also runs `scripts/repo-maintenance/validate-local-e2e.sh` after the normal maintainer validation gate. That makes local live transport E2E part of the default release signal instead of a separate manual checklist item.

Use deferred remote CI when full local validation has already passed and GitHub's check wait would otherwise keep a Codex shell process open just to poll:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z --remote-ci-mode defer
```

Deferred mode still performs the local release preparation, branch push, pull request creation, and initial check discovery. The release is not complete until the same thread resumes after CI settles and reruns the standard release command to finish review checks, merge, tagging, GitHub release creation, live-service update, and cleanup.

For the detailed contract and edge cases, use [docs/maintainers/release-workflow.md](./docs/maintainers/release-workflow.md).

## Pull Request Expectations

Summarize what changed, why it changed, and what reviewers should pay attention to first. For release work, make sure the branch-side candidate preparation is complete before handing it off to `main` for the final publish step.

## Communication

Raise uncertainty early when a task starts pushing on architecture, release semantics, or live-service behavior. If the clean path needs wider scope than the original request, say so before the change sprawls. If a behavior changed across docs, HTTP, MCP, LaunchAgent, or embedding surfaces, mention that explicitly instead of assuming reviewers will reconstruct it from the diff.

## Documentation Map

- [README.md](./README.md) is the product and agent-facing entrypoint.
- [API.md](./API.md) is the detailed HTTP and MCP contract reference.
- [docs/maintainers/source-layout.md](./docs/maintainers/source-layout.md) is the maintainer map for the current source split.
- [docs/maintainers/release-workflow.md](./docs/maintainers/release-workflow.md) is the current `maintain-project-repo` release contract.
- [docs/maintainers](./docs/maintainers/) holds active maintainer-facing architecture, workflow, and cleanup notes.
- [docs/releases](./docs/releases/) holds historical release notes and release checklists.
- [docs/investigations](./docs/investigations/) holds historical investigations and incident writeups.

## License and Contribution Terms

This repository is licensed under [Apache License 2.0](./LICENSE). By contributing, you are contributing changes under that same project license.
