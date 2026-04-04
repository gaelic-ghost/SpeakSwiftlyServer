---
name: sync-swift-package-guidance
description: Sync repo guidance for an existing Swift Package Manager repository when the user wants to add, merge, refresh, or align AGENTS.md and package workflow guidance. Use for existing Swift package repos whose source of truth is Package.swift. Do not use for brand-new package bootstrap or Xcode app projects.
---

# Sync Swift Package Guidance

## Purpose

Bring an existing Swift package repository up to the expected guidance baseline without stretching the package bootstrap skill into an ongoing repo-guidance surface. This skill owns deterministic `AGENTS.md` creation or bounded section append behavior for existing SwiftPM repos. `scripts/run_workflow.py` is the runtime entrypoint, and `scripts/sync_swift_package_guidance.py` applies the current sync behavior.

## When To Use

- Use this skill when an existing Swift package repo needs `AGENTS.md` added, refreshed, or merged with the current SwiftPM workflow baseline.
- Use this skill when the repository already has `Package.swift` and the user wants package workflow guidance, onboarding rules, or repo policy brought up to date.
- Use this skill when the user wants the repo guidance that used to be implied by the Swift package bootstrap flow to be made explicit in an existing package repo.
- Do not use this skill for brand-new package creation from nothing.
- Do not use this skill for ordinary package development, builds, tests, diagnostics, or dependency changes.
- Do not use this skill for Xcode app repos, workspaces, or native Apple app projects.
- Recommend `bootstrap-swift-package` when the package repo does not exist yet.
- Recommend `xcode-app-project-workflow` when the task is active execution, diagnostics, or Xcode-managed package work rather than repo guidance sync.
- Recommend `sync-xcode-project-guidance` when the repo is an Xcode app project instead of a plain Swift package.

## Single-Path Workflow

1. Collect the required inputs:
   - `repo_root`
   - optional `skip_validation`
   - optional `dry_run`
2. Classify the request as existing Swift package guidance sync before continuing:
   - continue only when the repo already contains `Package.swift`
   - stop if the request is really new-package bootstrap or Xcode app-repo guidance sync
   - stop if the repo boundary is ambiguous because both package and Xcode app markers are present at the same root
3. Apply the Apple and Swift docs gate before shaping workflow guidance:
   - read the relevant SwiftPM and Swift documentation first
   - prefer Dash or local Swift docs first, then official Swift or Apple web docs when needed
   - state the documented workflow boundary being relied on before proposing repo guidance changes
   - current documented anchors for this workflow include:
     - Swift Package Manager overview: [Swift Package Manager](https://www.swift.org/documentation/package-manager/)
     - package manifest structure: [PackageDescription](https://developer.apple.com/documentation/packagedescription)
     - package manifest entrypoint: [Package](https://developer.apple.com/documentation/packagedescription/package)
   - if the docs and the current guidance template conflict, stop and report that conflict
   - if no relevant SwiftPM docs can be found, say that explicitly before proceeding
4. Apply the shared Swift-package policy before making repo-guidance changes:
   - apply the detailed local policy in `references/snippets/apple-swift-package-core.md`
   - preserve its simplicity-first Swift, SwiftPM, logging, telemetry, and testing guidance
5. Run `scripts/run_workflow.py` to normalize inputs, detect whether the repo is really SwiftPM-managed, and shape the sync plan.
6. Apply the sync path:
   - if `AGENTS.md` is missing, copy `assets/AGENTS.md`
   - if `AGENTS.md` exists and already contains the managed section, keep the file unchanged
   - if `AGENTS.md` exists but lacks the managed section, append `assets/append-section.md` as a bounded section
7. Validate the synced repo guidance:
   - verify `AGENTS.md` exists
   - verify the synced file mentions `bootstrap-swift-package`
   - verify the synced file mentions `sync-swift-package-guidance`
   - verify the synced file preserves `swift build` and `swift test` as default validation paths
8. Hand off ongoing package work cleanly:
   - prefer `swift build` and `swift test` for ordinary package work after guidance sync
   - recommend `xcode-app-project-workflow` only when package work needs Xcode-managed SDK or toolchain behavior
   - recommend `bootstrap-swift-package` only when the user actually needs a fresh repo instead of guidance sync

## Inputs

- `repo_root`: optional absolute or relative path to the repository root; defaults to `.`
- `skip_validation`: optional flag to skip post-sync file validation
- `dry_run`: optional flag to emit the planned contract without writing files
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - `repo_root=.` when omitted
  - `appendSectionWhenAgentsExists=true`
  - `copyAgentsTemplateWhenMissing=true`
  - validation runs unless `--skip-validation` is passed

## Outputs

- `status`
  - `success`: guidance sync completed or was already satisfied
  - `blocked`: prerequisites, repo classification, or sync policy prevented completion
  - `failed`: the sync path started but did not complete successfully
- `path_type`
  - `primary`: the documented sync path completed
  - `fallback`: a non-mutating guided result was returned
- `output`
  - resolved repo root
  - detected package and Xcode markers
  - `AGENTS.md` path
  - actions applied or planned
  - validation result
  - one concise next step or handoff

## Guards and Stop Conditions

- Stop with `blocked` if the repo root cannot be resolved.
- Stop with `blocked` if the repo does not contain `Package.swift`.
- Stop with `blocked` if the repo root looks ambiguous because it contains both `Package.swift` and Xcode app markers.
- Stop with `blocked` if `AGENTS.md` exists but append behavior is disabled and the repo still lacks the required Swift package guidance section.
- Stop with `blocked` if the target `AGENTS.md` path exists but is not a regular file.

## Fallbacks and Handoffs

- The only current fallback is a non-mutating dry-run or guided result that explains what the sync would do.
- After a successful sync, use `swift build` and `swift test` for ordinary package work by default.
- Recommend `xcode-app-project-workflow` when package work needs Xcode-managed SDK or toolchain behavior.
- Recommend `bootstrap-swift-package` when the repository still needs to be created from scratch.
- Recommend `sync-xcode-project-guidance` when the repo root is really an Xcode app project rather than a plain Swift package.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` loads runtime-safe defaults from customization state before invoking the supported sync path.
- Current runtime-enforced knobs include whether missing `AGENTS.md` files should be created from template, whether an existing `AGENTS.md` may receive the bounded Swift package section, and whether validation runs after sync.

## References

### Workflow References

- `references/project-detection.md`

### Contract References

- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- `assets/AGENTS.md`
- `assets/append-section.md`
- Recommend `references/snippets/apple-swift-package-core.md` when an existing Swift package repo needs the reusable baseline policy content in a human-reviewable form.
- `references/snippets/apple-swift-package-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/sync_swift_package_guidance.py`
- `scripts/customization_config.py`
