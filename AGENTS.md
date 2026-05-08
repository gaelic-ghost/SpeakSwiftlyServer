# AGENTS.md

Use this file for durable repo-local guidance that Codex should follow before changing code, docs, or project workflow surfaces in this repository.

## Repository Scope

This root file governs the standalone Swift Package Manager repository for `SpeakSwiftlyServer`: package structure, maintainer automation, public docs, release workflow, plugin metadata, and the local HTTP, MCP, LaunchAgent, and embedded Apple-platform server surfaces.

### What This File Covers

- Treat this checkout as the primary development and release home for `SpeakSwiftlyServer`.
- Treat `Package.swift` as the source of truth for products, targets, dependencies, resources, platforms, and Swift language mode.
- Keep `Package.resolved` aligned with dependency changes from normal SwiftPM resolution.
- Treat tagged GitHub releases as the distribution surface for consumers and downstream submodule adoption.
- Keep the checked-in `maintain-project-repo` toolkit as the local-first maintainer surface for validation, sync, release, and CI wiring.
- Default user-facing Codex plugin install and update examples to `codex plugin marketplace add gaelic-ghost/socket` and `codex plugin marketplace upgrade socket`. This repository owns the `speak-swiftly` plugin payload, displayed as `Speak Swiftly`, but Socket is the supported end-user marketplace entrypoint. Keep explicit refs scoped to Socket metadata, pinned reproducible installs, and development-only diagnostics. When both standalone and Socket marketplace installs are present, prefer the Socket entry and make duplicate-enable repair explicit in the doctor before changing user config.

### Where To Look First

- `Package.swift` for package graph, products, targets, deployment target, and `swiftLanguageModes`.
- `README.md` for the public entrypoint and operator-facing overview.
- `CONTRIBUTING.md` for contributor setup, validation, review, and release expectations.
- `API.md` for the HTTP and MCP transport contract.
- `docs/maintainers/release-workflow.md` for the current release contract.
- `docs/maintainers/source-layout.md` before source-layout or module-boundary changes.
- `scripts/repo-maintenance/` for local validation, shared sync, release, and CI wrapper behavior.
- `Sources/SpeakSwiftlyServer/` for the reusable library target and `Sources/SpeakSwiftlyServerTool/` for the executable wrapper.

## Working Rules

### Change Scope

- Prefer complete, coherent passes when a repo workflow, package surface, docs surface, or operator command changes.
- Keep package graph changes together with `Package.swift`, `Package.resolved`, target layout, matching docs, and matching tests.
- Keep HTTP, MCP, LaunchAgent, and release workflow changes paired with operator-facing docs in the same change.
- Keep source files small and role-focused; split shared support into explicit helper or extension files instead of growing mixed-responsibility entry points.
- Use feature branches for normal repo work. Treat `main` as the protected release branch unless Gale explicitly says to work there for a specific task.
- Treat a feature branch as a local isolation and checkpoint surface, not automatic permission to publish, open a pull request, or start watching remote CI.
- Do not push a branch, open a pull request, enable auto-merge, or begin GitHub CI watch just because a local change exists. Do those remote handoff steps only when Gale asks for a PR/push/release, when the repo-owned release script is intentionally running a release, or when Gale explicitly asks for review handoff.
- For ordinary implementation and docs changes, finish the local pass first: inspect the diff, run the relevant local validation, explain the result, and wait for a remote handoff request unless the active task already asked for one.

### Source of Truth

- SwiftPM owns package structure here. Prefer `swift package` subcommands for structural edits when SwiftPM exposes the needed operation.
- The resolved `SpeakSwiftly` dependency declared in `Package.swift` and locked in `Package.resolved` is the source of truth for normal builds and tests.
- Do not retarget the package to a local `SpeakSwiftly` checkout unless that manifest change is the explicit task.
- If unreleased `SpeakSwiftly` behavior is needed, prefer stabilizing and tagging it upstream first, then updating this package to that release.
- Keep package resources under the owning target tree and load them through `Bundle.module`.
- Create bundled system voice profiles with the upstream `SpeakSwiftly` command plugin, not by
  manually copying live runtime profiles or hand-editing generated manifests. From this package
  checkout, the intended authoring path is `xcrun swift package plugin
  --allow-writing-to-package-directory upsert-system-voice-profile --target SpeakSwiftlyServer ...`.
  If the command plugin is not discoverable with `xcrun swift package plugin --list`, stop and
  surface that as a package/plugin exposure issue before generating resources. Use
  `SpeakSwiftlyTool --system-profile-resource-root` only for upstream debugging or plugin
  implementation work.
- Keep transport-local shaping at the HTTP and MCP edges. If `SpeakSwiftly` or `TextForSpeech` can express a concept directly, prefer deleting server-local inference over adding another translation path.

### Documentation Ownership

- Keep `README.md` nontechnical and focused on end users, evaluators, integrators, and agents deciding whether and how to use `Speak Swiftly`.
- Keep `README.md` contributor handoff limited to a short link to `CONTRIBUTING.md` and `AGENTS.md`; do not reintroduce maintainer setup, release, validation, embedding, configuration, or plugin-debugging procedures there.
- Keep contributor-facing and maintainer-facing workflow detail in `CONTRIBUTING.md` or a linked document under `docs/maintainers/`.
- Keep agent-facing maintainer rules in this `AGENTS.md` file when the rule changes how Codex should edit, validate, release, or route work in this repository.
- Preserve the README `Overview > What This Project Is` and `Overview > Motivation` subsections as user-authored prose. Use `TBD` as the placeholder until Gale provides replacement text.

### Codex Plugin Hooks

- This repository supports the Socket-managed Codex plugin path only. Do not add or maintain Claude Code, Anthropic, `.claude`, or `.claude-plugin` support surfaces here; if historical Claude-specific support appears in tracked docs, scripts, manifests, or examples, remove it instead of keeping parity.
- Treat plugin-managed hooks as the required end-user path for Speak Swiftly Codex TTS. Do not add `~/.codex/hooks.json` as a repair path for normal installs.
- Current Codex builds require both `features.codex_hooks = true` and `features.plugin_hooks = true` before installed plugin lifecycle hooks become runnable. `codex_hooks` enables the hook system; `plugin_hooks` enables hooks loaded from installed plugins.
- If the installed plugin manifest and `hooks/hooks.json` are correct but no `Stop` row appears in `~/.codex/speak-swiftly-server/hooks/logs/stop-tts.jsonl`, check `features.plugin_hooks` before changing hook commands, adding global hooks, or blaming the live service.
- Use `node scripts/codex-hooks-doctor.mjs --repair-plan` as the first audit surface for hook feature flags, installed plugin metadata, duplicate user-level hooks, live runtime reachability, and recent hook logs.
- Keep user-level `~/.codex/hooks.json` Speak Swiftly entries classified as duplicate or legacy repair targets. A missing user-level Stop hook is the healthy state when the installed plugin-managed hook is intended.

### Communication and Escalation

- Surface architectural pivots before implementing them when they introduce a new ownership boundary, queue, storage model, release path, or live-service behavior.
- If Linux support would require compromising the Apple-platform package shape, stop and discuss whether a separate Rust implementation is cleaner.
- If a validation step would touch the live LaunchAgent-backed service, say so first unless the task explicitly asked for that live-service operation.
- If maintainer automation and current repo-specific release behavior disagree, align the docs and scripts in the same pass instead of leaving both stories active.

## Commands

### Setup

```bash
xcrun swift package resolve
```

Install local formatting and linting tools when running the full maintainer gate outside CI:

```bash
brew install swiftformat swiftlint
```

### Validation

Use the repo-owned maintainer gate for complete validation:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Use the remote CI wrapper lane when checking the GitHub workflow path locally:

```bash
sh scripts/repo-maintenance/validate-ci.sh
```

The GitHub Actions workflow itself runs the lighter CI wrapper through `sh scripts/repo-maintenance/validate-ci.sh`. Keep the full maintainer gate local through `validate-all.sh` and the release script so release candidates get DocC, CLI smoke, SwiftFormat, SwiftLint, and live E2E before remote handoff without making every remote check repeat that whole local gate.

Use the local live end-to-end release gate when checking the transport smoke suite manually:

```bash
sh scripts/repo-maintenance/validate-local-e2e.sh
```

The standard release flow runs this local live end-to-end gate by default after `validate-all.sh`. The gate unloads resident models from the installed LaunchAgent-backed service, runs the live transport E2E suite, and reloads resident models afterward.

Use the default SwiftPM package lane for ordinary source work:

```bash
xcrun swift build
xcrun swift test
```

### Optional Project Commands

Run the server in the foreground:

```bash
xcrun swift run SpeakSwiftlyServerTool serve
```

Inspect the operator surface:

```bash
xcrun swift run SpeakSwiftlyServerTool help
xcrun swift run SpeakSwiftlyServerTool healthcheck --base-url http://127.0.0.1:7338
```

Run repo-maintenance sync and release entrypoints:

```bash
sh scripts/repo-maintenance/sync-shared.sh
sh scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
sh scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z --remote-ci-mode defer
sh scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z --skip-local-e2e
```

The release flow runs `scripts/repo-maintenance/version-bump.sh` so version-bearing repo surfaces move with the release before the tag is created.
Use `--remote-ci-mode defer` when full local validation has already run and the remote CI wait is long enough that Codex should resume from a thread wakeup instead of holding a shell process open just to poll GitHub.
Use `--skip-local-e2e` only when the release intentionally cannot touch the live LaunchAgent-backed service on this machine and the maintainer has another concrete live E2E signal for the release candidate.

## Review and Delivery

### Review Expectations

- Summarize what changed, which repo surfaces moved, and why those surfaces needed to move together.
- Call out whether validation used the full maintainer gate or a narrower SwiftPM check.
- Mention docs updates when behavior changed for HTTP, MCP, LaunchAgent, embedding, release, or plugin consumers.
- Do not describe local work as PR-ready unless the branch has actually reached a requested review or release handoff point.
- For release work, make sure `scripts/repo-maintenance/release.sh` is the documented entrypoint unless a historical release note is intentionally describing an older flow.

### Definition of Done

- The worktree is clean except for intentional changes.
- Relevant source, docs, tests, package graph files, and maintainer scripts are updated together.
- `sh scripts/repo-maintenance/validate-all.sh` passes, or any skipped portion is explicitly explained with the reason.
- README, CONTRIBUTING, AGENTS, maintainer docs, and release guidance agree about the current command path.
- Live end-to-end suites are run one at a time after the live-service resident-model unload preflight has created enough memory headroom.

## Safety Boundaries

### Never Do

- Never edit or experiment in `../../speak-to-user/monorepo` as a feature workspace; keep it as the clean integration checkout.
- Never retarget public dependency declarations to machine-local paths such as `/Users/...`, `~/...`, or `../...`.
- Never run overlapping SwiftPM, Xcode, or live end-to-end test processes on this machine.
- Never run live `SpeakSwiftlyServerTransportE2ETests` before the live-service resident-model unload preflight has completed.
- Never make live-service code changes directly in a live local service repo when a separate development repo exists.
- Never leave duplicate release command stories active after a release workflow alignment.

### Ask Before

- Ask before changing the package's core architecture, deployment baseline, persistence root, LaunchAgent behavior, or live-service promotion flow.
- Ask before widening the public HTTP, MCP, or embedded API contract beyond the requested task.
- Ask before publishing tags, creating GitHub releases, refreshing the live service, or changing repository visibility/settings.
- Ask before replacing the `maintain-project-repo` managed release contract with a repo-specific fork.

## Local Overrides

No deeper `AGENTS.md` files are currently checked in below this repository root. If a future subdirectory adds a closer `AGENTS.md`, that file refines this root guidance for work inside its subtree.

## Swift Package Workflow

- Use `xcrun swift build` and `xcrun swift test` as the default first-pass validation commands so repo-local SwiftPM work stays on the Xcode-selected toolchain.
- Treat the live `SpeakSwiftlyServerTransportE2ETests` target as a one-process, one-suite-at-a-time surface. Even though the target is split into HTTP, MCP, and control suites, those live end-to-end suites must always be run sequentially in separate foreground commands and must never overlap in parallel.
- Before running any live end-to-end suite, use the live-service resident-model unload preflight so the installed LaunchAgent-backed service stays installed while the test-owned helper has enough memory headroom. Do not uninstall the live service as an E2E preflight.
- Use `bootstrap-swift-package` only when a brand-new Swift package repository still needs to be created from scratch.
- Use `sync-swift-package-guidance` when this repo guidance drifts and needs a deliberate refresh against the current Swift package baseline.
- Use `swift-package-build-run-workflow` for manifest, dependency, build, run, resource, and packaging work when `Package.swift` is the source of truth.
- Use `swift-package-testing-workflow` for Swift Testing, XCTest holdouts, fixtures, and package test diagnosis.
- When generating `Resources/SystemProfiles` voice resources, prefer the upstream
  `upsert-system-voice-profile` SwiftPM command plugin. Run it from a normal user shell or an
  explicitly unsandboxed agent command if the Codex sandbox cannot access the default Metal GPU.
- Prefer `xcode-build-run-workflow` or `xcode-testing-workflow` only when package work genuinely needs Xcode-managed SDK, toolchain, Metal, or test behavior that SwiftPM does not cover cleanly.
- Read relevant SwiftPM, Swift, and Apple documentation before proposing package-structure, dependency, concurrency, or architecture changes, and prefer Dash or local docs first when available.

## Monorepo And Submodule Handoff

- Treat `../../speak-to-user/monorepo/packages/SpeakSwiftlyServer` as the integration submodule copy, not as the primary development home.
- Treat the local `../../speak-to-user/monorepo` checkout as a clean base checkout that stays on `main` and stays clean.
- Never use that clean base checkout for feature work, experiments, release bumps, or submodule-pointer edits.
- For monorepo work, create a dedicated `git worktree`, do the work there, open a pull request, and delete the merged worktree and branch afterward.
- When `speak-to-user` adopts a new server version, prefer updating the submodule pointer to a tagged `SpeakSwiftlyServer` release instead of an arbitrary branch tip.
