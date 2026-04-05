---
name: sync-xcode-project-guidance
description: Sync repo guidance for an existing native Apple app repository managed through Xcode when the user wants to add, merge, refresh, or align AGENTS.md and project workflow guidance. Use for existing macOS, iOS, or iPadOS app repos with an .xcodeproj or .xcworkspace. Do not use for brand-new app bootstrap or plain Swift packages.
---

# Sync Xcode Project Guidance

## Purpose

Bring an existing Xcode app repository up to the expected guidance baseline without overloading the main Xcode execution skill. This skill owns repo-guidance alignment for existing Apple app repos, including deterministic `AGENTS.md` creation or bounded section append behavior, and refreshes the managed repo-maintenance toolkit alongside that guidance. `scripts/run_workflow.py` is the runtime entrypoint, and `scripts/sync_xcode_project_guidance.py` applies the current sync behavior.

## When To Use

- Use this skill when an existing macOS, iOS, or iPadOS app repo needs `AGENTS.md` added, refreshed, or merged with the current Xcode workflow baseline.
- Use this skill when the repository already has an `.xcodeproj` or `.xcworkspace` and the user wants project guidance, onboarding rules, or workflow policy brought up to date.
- Use this skill when the user wants the repo guidance that used to be implied by `xcode-app-project-workflow` to be made explicit in the repo itself.
- Do not use this skill for new-project creation from nothing.
- Do not use this skill for ordinary build, test, run, diagnostics, docs lookup, or mutation work inside an existing Xcode project.
- Do not use this skill for plain Swift packages, libraries, or tools that are not native Apple apps.
- Recommend `bootstrap-xcode-app-project` when the repo does not exist yet.
- Recommend `xcode-app-project-workflow` when the task is active execution, diagnostics, docs lookup, or mutation work inside an existing Xcode project.
- Recommend `sync-swift-package-guidance` when the repo is a plain Swift package instead of an Xcode app project.

## Single-Path Workflow

1. Collect the required inputs:
   - `repo_root`
   - optional `workspace_path`
   - optional `skip_validation`
   - optional `dry_run`
2. Classify the request as existing Xcode app-repo guidance sync before continuing:
   - continue only when the repo already contains an `.xcodeproj` or `.xcworkspace`
   - stop if the request is really new-project bootstrap or SwiftPM-only guidance sync
3. Apply the Apple docs gate before shaping workflow guidance:
   - read the relevant Apple documentation first
   - prefer Dash or local Apple docs first, then official Apple web docs when needed
   - state the documented workflow boundary being relied on before proposing repo guidance changes
   - current documented anchors for this workflow include:
     - Apple's Xcode project-creation guidance: [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating_an_xcode_project_for_an_app)
     - SwiftUI app lifecycle guidance through the `App` protocol: [App](https://developer.apple.com/documentation/swiftui/app)
     - scene composition guidance through `Scene` and `WindowGroup`: [Scene](https://developer.apple.com/documentation/swiftui/scene) and [WindowGroup](https://developer.apple.com/documentation/swiftui/windowgroup)
   - if the docs and the current guidance template conflict, stop and report that conflict
   - if no relevant Apple docs can be found, say that explicitly before proceeding
4. Apply the shared Xcode-project policy before making repo-guidance changes:
   - apply the detailed local policy in `references/snippets/apple-xcode-project-core.md`
   - preserve its simplicity-first Swift, SwiftUI, and Xcode-managed project guidance
5. Run `scripts/run_workflow.py` to normalize inputs, detect whether the repo is really Xcode-managed, and shape the sync plan.
6. Apply the sync path:
   - if `AGENTS.md` is missing, copy `assets/AGENTS.md`
   - if `AGENTS.md` exists and already contains the managed section, keep the file unchanged
   - if `AGENTS.md` exists but lacks the managed section, append `assets/append-section.md` as a bounded section
7. Validate the synced repo guidance:
   - verify `AGENTS.md` exists
   - verify the synced file mentions `xcode-app-project-workflow`
   - verify the synced file preserves the no-direct-`.pbxproj` rule
8. Refresh the repo-maintenance toolkit:
   - refresh `scripts/repo-maintenance/`
   - refresh `.github/workflows/validate-repo-maintenance.yml`
   - preserve repo-specific extra scripts that are not part of the managed file set
9. Hand off ongoing engineering work cleanly:
   - recommend `xcode-app-project-workflow` for active Xcode collaboration after the repo guidance is aligned
   - recommend `bootstrap-xcode-app-project` only when the user actually needs a fresh repo instead of guidance sync

## Inputs

- `repo_root`: optional absolute or relative path to the repository root; defaults to `.`
- `workspace_path`: optional path used only to improve Xcode-project discovery when repo-root detection is ambiguous
- `skip_validation`: optional flag to skip post-sync file validation
- `dry_run`: optional flag to emit the planned contract without writing files
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - `repo_root=.` when omitted
  - `writeMode=sync-if-needed`
  - validation runs unless `--skip-validation` is passed
  - successful mutating runs refresh the repo-maintenance toolkit in place

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
  - detected workspace or project markers
  - `AGENTS.md` path
  - actions applied or planned
  - refreshed repo-maintenance toolkit paths
  - validation result
  - one concise next step or handoff

## Guards and Stop Conditions

- Stop with `blocked` if the repo root cannot be resolved.
- Stop with `blocked` if the repo does not contain an `.xcodeproj` or `.xcworkspace`.
- Stop with `blocked` if the repo appears to be a SwiftPM-only package without Xcode-managed app markers.
- Stop with `blocked` if the chosen `writeMode` does not allow the mutation the repo still needs, such as creating a missing `AGENTS.md` or appending the bounded Xcode guidance section.
- Stop with `blocked` if the target `AGENTS.md` path exists but is not a regular file.

## Fallbacks and Handoffs

- The only current fallback is a non-mutating dry-run or guided result that explains what the sync would do.
- After a successful sync, hand off ongoing execution and diagnostics work to `xcode-app-project-workflow`.
- After a successful sync, use `scripts/repo-maintenance/validate-all.sh` for local maintainer validation and `scripts/repo-maintenance/release.sh` for releases.
- Recommend `bootstrap-xcode-app-project` when the repository still needs to be created from scratch.
- Recommend `sync-swift-package-guidance` when the repo is a plain Swift package rather than an Xcode app project.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` loads runtime-safe defaults from customization state before invoking the supported sync path.
- The current runtime-enforced customization surface is one `writeMode` knob that controls whether the workflow may create missing `AGENTS.md`, append the bounded Xcode section, or stay report-only.

## References

### Workflow References

- `references/project-detection.md`

### Contract References

- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- `assets/AGENTS.md`
- `assets/append-section.md`
- Recommend `references/snippets/apple-xcode-project-core.md` when an existing Xcode repo needs the reusable baseline policy content in a human-reviewable form.
- `references/snippets/apple-xcode-project-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/sync_xcode_project_guidance.py`
- `scripts/install_repo_maintenance_toolkit.py`
- `scripts/customization_config.py`
