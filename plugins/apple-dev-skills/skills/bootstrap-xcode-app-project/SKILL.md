---
name: bootstrap-xcode-app-project
description: Bootstrap a new native Apple app project for macOS, iOS, or iPadOS when the user wants to start, begin, create, or bootstrap an Xcode app project. Use for new SwiftUI-first app repositories on macOS, with optional XcodeGen generation preference and repo-baseline setup guidance. Do not use for plain Swift packages, libraries, or tools that are not native Apple apps.
---

# Bootstrap Xcode App Project

## Purpose

Create a new native Apple app repository from nothing to a usable baseline on disk. The first implementation prioritizes a deterministic `XcodeGen` path for SwiftUI app projects and a guarded planning path for the standard Xcode-created-project flow. `scripts/run_workflow.py` is the runtime entrypoint, and `scripts/bootstrap_xcode_app_project.py` is the current implementation core for XcodeGen-backed scaffold creation.

## When To Use

- Use this skill when the user wants to start, begin, create, or bootstrap a new macOS, iOS, or iPadOS app project on macOS.
- Use this skill when the user explicitly asks for a new Xcode app, a native Apple app, or a new SwiftUI app repository.
- Use this skill when the user wants a reproducible app-project generator flow and prefers `XcodeGen`.
- Use this skill when a brand-new app repo should also get baseline repo guidance such as `AGENTS.md`.
- Do not use this skill for ordinary collaboration inside an existing Xcode project.
- Do not use this skill for plain Swift packages, libraries, or tools that are not native Apple apps.
- Recommend `bootstrap-swift-package` when the user wants a regular SwiftPM package instead of a native Apple app.
- Recommend `xcode-app-project-workflow` when the project already exists and the task is execution, diagnostics, docs lookup, mutation, build, test, or run work inside that existing project.

## Single-Path Workflow

1. Collect the required inputs:
   - `name`
   - `destination`
   - `platform`
   - `ui_stack`
   - `project_generator`
   - optional `bundle_identifier`
   - optional `org_identifier`
   - optional `skip_validation`
   - optional `dry_run`
2. Classify the request as a native Apple app bootstrap request before continuing:
   - continue only for `project_kind=app`
   - stop if the request is actually a Swift package, library, or tool bootstrap
3. Apply the Apple docs gate before recommending project structure or implementation guidance:
   - read the relevant Apple documentation first
   - prefer Dash or local Apple docs first, then official Apple web docs when needed
   - state the documented behavior being relied on before design or implementation guidance
   - current documented anchors for this workflow include:
     - Apple's Xcode project-creation guidance: [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating_an_xcode_project_for_an_app)
     - SwiftUI app lifecycle guidance through the `App` protocol: [App](https://developer.apple.com/documentation/swiftui/app)
     - scene composition guidance through `Scene` and `WindowGroup`: [Scene](https://developer.apple.com/documentation/swiftui/scene) and [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
   - if the docs and the current code or planned scaffold conflict, stop and report that conflict
   - if no relevant Apple docs can be found, say that explicitly before proceeding
4. Apply the shared Swift policy before giving implementation guidance:
   - apply the detailed local policy in `references/snippets/apple-xcode-project-core.md`
   - preserve its simplicity-first, shape-preserving, and anti-ceremony Swift guidance
5. Run `scripts/run_workflow.py` to normalize inputs, load customization state, and select the supported bootstrap path.
6. Resolve the generator path:
   - prefer `xcodegen` only when the user asked for it or customization selects it
   - use `xcode` only when the user explicitly prefers the standard Xcode project-creation flow
   - if the generator setting is `ask`, stop with a clear next step rather than guessing
7. Create the project:
   - for `xcodegen`, let `scripts/bootstrap_xcode_app_project.py` generate the repo scaffold, `project.yml`, source files, tests, and `AGENTS.md`, then run `xcodegen generate`
   - for `xcode`, use a guarded guidance path for now instead of pretending the repo supports full GUI automation already
8. Validate the scaffold:
   - verify the expected app files exist
   - verify `AGENTS.md` exists when enabled
   - if validation is enabled, verify project generation and basic project introspection succeeded
9. Hand off existing-project work cleanly:
   - recommend `sync-xcode-project-guidance` when the repo guidance should be refreshed or merged after creation
   - recommend `xcode-app-project-workflow` for normal Xcode collaboration after bootstrap and guidance sync

## Inputs

- `name`: required; app project name and repo directory name.
- `destination`: parent directory for the new app repo.
- `project_kind`: defaults to `app`; any non-app value blocks the workflow.
- `platform`: `macos`, `ios`, or `ipados`.
- `ui_stack`: `swiftui`, `uikit`, or `appkit`.
- `project_generator`: `ask`, `xcode`, or `xcodegen`.
- `bundle_identifier`: optional explicit bundle identifier.
- `org_identifier`: optional organization identifier used to derive a bundle identifier when `bundle_identifier` is omitted.
- `skip_validation`: optional flag to skip post-generation verification.
- `dry_run`: optional flag to resolve inputs and emit the planned execution contract without creating files.
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - `project_kind` defaults to `app`
  - `destination` defaults to `.`
  - `platform` defaults to `ask` through customization unless explicitly set
  - `ui_stack` defaults to `swiftui`
  - `project_generator` defaults to `ask`
  - `copy_agents_md` defaults to `true`
  - validation runs unless `--skip-validation` is passed

## Outputs

- `status`
  - `success`: bootstrap completed on the supported path
  - `blocked`: prerequisites, unsupported selections, or safety rules prevented completion
  - `failed`: the implementation path started but did not complete successfully
- `path_type`
  - `primary`: the documented supported path completed
  - `fallback`: a guided fallback or non-mutating plan was returned instead
- `output`
  - resolved project path
  - normalized inputs
  - resolved bundle identifier
  - generator path
  - validation result
  - one concise next step or handoff

## Guards and Stop Conditions

- Stop with `blocked` if `name` is missing.
- Stop with `blocked` if `project_kind` is not `app`.
- Stop with `blocked` if the platform cannot be resolved safely.
- Stop with `blocked` if `project_generator=ask` and the request does not make the generator preference clear.
- Stop with `blocked` if `ui_stack` is not supported by the current implementation path.
- Stop with `blocked` if the target directory already exists and contains non-ignorable files.
- Stop with `blocked` if `project_generator=xcodegen` and `xcodegen` is not available on `PATH`.
- Stop with `blocked` if the user chose the standard Xcode flow and the repo cannot safely automate that path yet.

## Fallbacks and Handoffs

- Preferred implementation path in the first iteration is `XcodeGen` plus generated scaffold files.
- Use the standard Xcode-created-project path only as a guided fallback for now.
- After a successful bootstrap, hand off to `sync-xcode-project-guidance` for repo-guidance alignment when needed, then to `xcode-app-project-workflow` for build, test, run, diagnostics, mutation, and docs work.
- Recommend `bootstrap-swift-package` directly when the task is really package bootstrap.
- Recommend `sync-xcode-project-guidance` when the repo already exists and only needs repo-guidance or documentation alignment.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` loads runtime-safe defaults from customization state before invoking the supported implementation path.
- Current runtime-enforced knobs include the default platform, UI stack, generator preference, bundle-ID prefix, `AGENTS.md` copy behavior, and validation mode.

## References

### Workflow References

- `references/project-generators.md`
- `references/platform-matrix.md`

### Contract References

- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- `assets/AGENTS.md`
- Recommend `references/snippets/apple-xcode-project-core.md` when the new app repo should start with reusable Xcode-project baseline policy content next to the generated `AGENTS.md`.
- `references/snippets/apple-xcode-project-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/bootstrap_xcode_app_project.py`
- `scripts/customization_config.py`
