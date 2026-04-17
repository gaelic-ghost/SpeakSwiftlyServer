# AGENTS.md

## Purpose

- This repository is the standalone Swift Package Manager home for `SpeakSwiftlyServer`.
- Keep this file focused on repo-owned workflow guidance, not on repeating the full bootstrap template for every Swift package.
- When the repo workflow or package policy changes materially, refresh this file intentionally instead of letting scaffold language linger.

## Repository Expectations

- Treat `Package.swift` as the source of truth for package structure, products, targets, dependencies, resources, and deployment targets.
- Prefer `swift package` subcommands for structural edits when SwiftPM already exposes the right operation.
- Keep package graph changes together in one pass, including `Package.swift`, `Package.resolved`, target layout, and any matching docs or tests.
- Use `scripts/repo-maintenance/validate-all.sh` for maintainer validation, `scripts/repo-maintenance/sync-shared.sh` for repo-local sync steps, `scripts/repo-maintenance/release-prepare.sh` for branch or worktree release prep, and `scripts/repo-maintenance/release-publish.sh` for the final release cut from the release branch. `scripts/repo-maintenance/release.sh` remains the compatibility dispatcher.
- Keep package resources under the owning target tree and load them through `Bundle.module`.
- Treat tagged releases as the distribution surface for this repository, especially when the staged LaunchAgent artifact path changes.

## Repo Workflow

- Treat this standalone `SpeakSwiftlyServer` repository as the source of truth for development, tags, and releases.
- Treat `main` as the release branch for this repository unless a future repo-local change says otherwise.
- Use `scripts/repo-maintenance/release-prepare.sh` from feature branches and worktrees when the job is to validate a release candidate, push the branch, open or update the pull request, and queue auto-merge.
- Use `scripts/repo-maintenance/release-publish.sh` only from local `main` after the release PR has merged when the job is to cut the annotated tag and GitHub release.
- If local `main` is ahead of `origin/main`, do not try to publish from that unsynced checkout. Move that work onto a feature branch or keep it on the existing branch, run `release-prepare.sh`, merge the PR, fast-forward local `main`, and only then run `release-publish.sh`.
- Do not publish release tags or GitHub releases directly from a feature branch or feature worktree in this repository.
- Treat the resolved `SpeakSwiftly` dependency declared in `Package.swift` and locked in `Package.resolved` as the source of truth for normal `xcrun swift build` and `xcrun swift test` runs here.
- Do not retarget this package to a local `../SpeakSwiftly` checkout unless the manifest is being changed intentionally for a specific local-integration task.
- If unreleased `SpeakSwiftly` changes are needed here, prefer stabilizing and tagging them in `SpeakSwiftly` first, then update this repository to that release instead of integrating against half-finished sibling checkout work.
- Treat `macOS 15` as the current standalone package baseline and keep the host and state model friendly to a near-future `iOS 18` reuse path.
- Prefer maintainable Apple-platform architecture over speculative Linux abstraction. If Linux support would require major design compromise, stop and discuss whether a separate Rust implementation is the cleaner path.

## Monorepo And Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not as the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and then delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.

## Swift Package Workflow

- Use `xcrun swift build` and `xcrun swift test` as the default first-pass validation commands so repo-local SwiftPM work stays on the Xcode-selected toolchain.
- Treat the live `SpeakSwiftlyServerE2ETests` target as a one-process, one-suite-at-a-time surface. Even though the target is split into HTTP, MCP, and control suites, those live end-to-end suites must always be run sequentially in separate foreground commands and must never overlap in parallel.
- Before running any live end-to-end suite, stop the LaunchAgent-backed live service first so the machine does not end up speaking from both the always-on service and the test-owned helper at the same time. Use `./.release-artifacts/current/SpeakSwiftlyServerTool launch-agent uninstall` for that shutdown step unless a future repo-owned operator command replaces it.
- Use `bootstrap-swift-package` only when a brand-new Swift package repository still needs to be created from scratch.
- Use `sync-swift-package-guidance` when this repo guidance drifts and needs a deliberate refresh against the current Swift package baseline.
- Use `swift-package-build-run-workflow` for manifest, dependency, build, run, resource, and packaging work when `Package.swift` is the source of truth.
- Use `swift-package-testing-workflow` for Swift Testing, XCTest holdouts, fixtures, and package test diagnosis.
- Prefer `xcode-build-run-workflow` or `xcode-testing-workflow` only when package work genuinely needs Xcode-managed SDK, toolchain, Metal, or test behavior that SwiftPM does not cover cleanly.
- Read relevant SwiftPM, Swift, and Apple documentation before proposing package-structure, dependency, concurrency, or architecture changes, and prefer Dash or local docs first when available.

## Coding And Architecture

- Prefer the simplest correct Swift that is easiest to read, reason about, and maintain.
- Prefer synthesized and framework-provided behavior over handwritten wrappers, conversion layers, or boilerplate.
- Keep dependency direction unidirectional and data flow straight.
- Keep transport-local shaping at the HTTP and MCP edges. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference instead of adding another translation layer.
- Keep `ServerHost` ownership narrow and explicit. Do not introduce helper coordinators, manager layers, or wrapper objects unless a real ownership boundary changes.
- Prefer Swift Testing by default unless an external constraint requires XCTest.
- Validate both Debug and Release behavior when optimization, packaging, or staged release artifacts matter.

## Docs And Maintenance

- Keep `README.md`, maintainer docs, and release guidance aligned with the current public transport and install surfaces.
- Use repository docs to describe the real current command path and artifact layout; do not leave scaffold wording or guessed maintenance files behind.
- When the source split changes meaningfully, refresh `docs/maintainers/source-layout.md` in the same pass.
- When the HTTP, MCP, LaunchAgent, or release workflow changes, update the operator-facing docs in the same change instead of deferring that cleanup.
