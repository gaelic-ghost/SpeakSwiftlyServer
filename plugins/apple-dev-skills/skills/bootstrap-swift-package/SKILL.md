---
name: bootstrap-swift-package
description: Bootstrap new Swift Package Manager repositories with consistent defaults, generated AGENTS guidance, validation, and customizable bootstrap settings. Use when creating a new Swift package, choosing platform or version presets, scaffolding its initial structure, or maintaining this skill's bootstrap defaults.
---

# Bootstrap Swift Package

## Purpose

Create a new Swift package repository with one top-level entry point and a simplicity-first Swift baseline. `scripts/run_workflow.py` is the runtime wrapper, and `scripts/bootstrap_swift_package.sh` remains the implementation core for scaffold creation and validation.

## When To Use

- Use this skill for new Swift package scaffolding.
- Use this skill when the user wants consistent package defaults, `AGENTS.md` generation, and immediate validation.
- Use this skill when the user wants to customize the documented bootstrap defaults for future runs.
- Do not use this skill as the default path for normal Xcode app collaboration work.
- Do not use this skill as the default path for guidance sync inside an already-existing Swift package repo.
- Recommend `xcode-app-project-workflow` when the user is working in an existing Xcode project or needs Apple-platform execution after bootstrap.
- Recommend `sync-swift-package-guidance` when an existing Swift package repo needs `AGENTS.md` or workflow-guidance alignment rather than fresh bootstrap.
- Recommend `explore-apple-swift-docs` when the user needs Apple or Swift docs exploration, Dash-compatible lookup, or Dash follow-up work.

## Single-Path Workflow

1. Collect the required inputs:
   - `name`
   - `type`
   - `destination`
   - `platform`
   - `version_profile`
   - optional `testing_mode`
   - optional `skip_validation`
2. Normalize aliases exactly as `scripts/bootstrap_swift_package.sh` does:
   - `macos -> mac`
   - `ios -> mobile`
   - `both -> multiplatform`
   - `latest -> latest-major`
   - `minus-one -> current-minus-one`
   - `minus-two -> current-minus-two`
3. Run `scripts/run_workflow.py` so documented defaults are loaded from customization state and normalized into one JSON contract.
4. Select testing mode before scaffold creation:
   - require a supported and validated `Swift 5.10+` toolchain floor before bootstrap planning continues
   - prefer `swift-testing` on supported current toolchains
   - use `xctest` when explicitly requested or when the supported toolchain requires it
   - stop with `blocked` when the local toolchain is older than `5.10` or when the local `swift package init` command cannot select the requested testing mode
5. Let the wrapper invoke the bundled script:
   ```bash
   scripts/bootstrap_swift_package.sh --name <Name> --type <library|executable|tool> --destination <dir> --platform <mac|macos|mobile|ios|multiplatform|both> --version-profile <latest-major|current-minus-one|current-minus-two|latest|minus-one|minus-two> --testing-mode <swift-testing|xctest>
   ```
6. Verify the generated repository:
   - `Package.swift`
   - `.git`
   - `AGENTS.md`
   - `Tests/`
   - `swift build` and `swift test` unless `--skip-validation` was requested
7. Ensure the generated guidance encodes the shared Swift policy:
   - apply the detailed local policy in `references/snippets/apple-swift-package-core.md`
   - keep the generated repo aligned with the simplicity-first, shape-preserving, and anti-ceremony Swift guidance in that snippet
   - preserve the project-appropriate logging and telemetry guidance from that snippet
8. Hand off package execution guidance cleanly:
   - use `swift build` and `swift test` by default
   - recommend `sync-swift-package-guidance` when a later repo-guidance refresh or merge is needed for the created package repo
   - recommend `xcode-app-project-workflow` for package builds that need Xcode-managed toolchain behavior, such as package builds that depend on Xcode-provided Metal or other Apple-managed build assets
9. Return one JSON execution summary with the created path, normalized options, and validation result.

## Inputs

- `name`: required; must start with a letter and contain only letters, numbers, `_`, or `-`.
- `type`: `library`, `executable`, or advanced explicit `tool`.
- `destination`: parent directory for the new package.
- `platform`: `mac`, `mobile`, or `multiplatform`, with aliases normalized by the script.
- `version_profile`: `latest-major`, `current-minus-one`, or `current-minus-two`, with aliases normalized by the script.
- `testing_mode`: `swift-testing` or `xctest`.
- `skip_validation`: optional flag to skip `swift build` and `swift test`.
- `dry_run`: optional flag to resolve defaults and emit the normalized command contract without creating files.
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - `type` defaults to `library`
  - `destination` defaults to `.`
  - `platform` defaults to `multiplatform`
  - `version_profile` defaults to `current-minus-one`
  - `testing_mode` defaults to `swift-testing`
  - validation runs unless `--skip-validation` is passed
  - supported and validated Swift toolchain floor is `5.10+`

## Outputs

- `status`
  - `success`: the package was created and verification succeeded
  - `blocked`: prerequisites, unsupported toolchains, unsupported testing-mode selections, or target-directory constraints prevented the run
  - `failed`: the script started but did not complete successfully
- `path_type`
  - `primary`: the bundled script completed successfully
  - `fallback`: manual scaffold guidance is being used instead of the bundled script
- `output`
  - resolved package path
  - normalized inputs
  - validation result
  - one concise next step

## Guards and Stop Conditions

- Stop with `blocked` if `swift` is missing.
- Stop with `blocked` if `swift --version` cannot be parsed into a supported toolchain version.
- Stop with `blocked` if the local Swift toolchain is older than `5.10`.
- Stop with `blocked` if `git` is missing.
- Stop with `blocked` if `assets/AGENTS.md` is missing.
- Stop with `blocked` if the target exists and contains non-ignorable files.
- Stop with `blocked` if `name` is missing.
- Stop with `blocked` if the requested testing mode cannot be honored by the active `swift package init` command.

## Fallbacks and Handoffs

- Preferred path is always `scripts/bootstrap_swift_package.sh`.
- Use manual `swift package init` guidance only when the script is unavailable or the user explicitly asks for the manual path.
- `tool` is an advanced explicit passthrough, not a default branch of the workflow.
- After a successful scaffold, hand off build, test, or Xcode-managed package execution tasks to `xcode-app-project-workflow`.
- After a successful scaffold, hand off later repo-guidance alignment work to `sync-swift-package-guidance`.
- For ordinary package work, prefer `swift build` and `swift test`.
- For package builds that need Xcode-managed SDK or toolchain behavior, use `xcode-app-project-workflow` and `xcodebuild` guidance instead of stretching the bootstrap skill into an execution skill.
- Recommend `explore-apple-swift-docs` directly when the user’s next step is Apple or Swift docs exploration or Dash-compatible docs management.
- `scripts/run_workflow.py` is the top-level runtime entrypoint and converts the shell script result into the documented JSON contract.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` loads runtime-safe defaults from customization state before invoking the shell script.
- `scripts/bootstrap_swift_package.sh` now honors the wrapper's git and `AGENTS.md` copy flags.

## References

### Workflow References

- `references/package-types.md`

### Contract References

- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- Recommend `references/snippets/apple-swift-package-core.md` when the new package repo should start with reusable SwiftPM baseline policy content next to the generated `AGENTS.md`.
- `assets/AGENTS.md`
- `references/snippets/apple-swift-package-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/bootstrap_swift_package.sh`
- `scripts/customization_config.py`
