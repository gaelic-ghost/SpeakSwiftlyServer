# Release Workflow

## Purpose

This document is the maintainer-facing release contract for the standalone `SpeakSwiftlyServer` repository.

Historical release notes and release checklists live under [`docs/releases`](../releases/). Keep this file focused on the current release process rather than per-release records.

The current release surface is aligned with the checked-in `maintain-project-repo` toolkit. That means `scripts/repo-maintenance/release.sh` is the standing entrypoint for release automation, and the selected profile lives in `scripts/repo-maintenance/config/profile.env`.

## Standard Release Command

Run the standard release flow from a feature branch or worktree:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

The standard flow runs `scripts/repo-maintenance/version-bump.sh` before tagging. That hook updates the checked-in Codex plugin manifest version to match the release version so plugin consumers, marketplace metadata, and GitHub release tags do not drift silently.

The standard flow is a durable repo-maintenance path. It validates the checkout, creates the annotated tag locally, pushes the branch and tag, opens or updates the release PR, watches CI, checks for review comments, merges the PR, fast-forwards local `main`, creates the GitHub release with `gh release create --verify-tag`, and cleans up merged local branches when safe.

## Context Rules

### Feature Branch Or Worktree

Use the standard flow from a named feature branch or worktree:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

The flow refuses to run standard mode from the protected base branch. If release-candidate commits were accidentally made directly on local `main`, branch from that tip before continuing so the release still goes through a pull request.

### Local `main`

Local `main` is the protected release branch and should normally be a sync surface, not the release automation workspace. After the standard release flow merges its PR, it attempts to fast-forward local `main` from `origin/main`.

If another worktree owns `main`, fast-forward that checkout manually after the release flow completes.

### Submodule Mode

Use submodule mode only when this repository is checked out as a submodule and the parent pointer update remains a separate follow-up:

```bash
scripts/repo-maintenance/release.sh --mode submodule --version vX.Y.Z
```

Submodule mode runs the dispatch scripts under `scripts/repo-maintenance/release/` and then leaves the parent repository pointer update to a separate commit.

## Script Inventory

### `scripts/repo-maintenance/release.sh`

Purpose:

- standard feature-branch release automation
- submodule release dispatch
- local validation before release work
- branch, tag, PR, CI, merge, GitHub release, and cleanup behavior for standard mode

Key flags:

- `--mode <standard|submodule>`
- `--version vX.Y.Z`
- `--base-branch <branch>`
- `--skip-validate`
- `--skip-version-bump`
- `--skip-gh-release`
- `--review-comments-addressed`
- `--skip-branch-cleanup`
- `--dry-run`

### `scripts/repo-maintenance/validate-all.sh`

Purpose:

- one local maintainer validation entrypoint
- the command CI calls through `.github/workflows/validate-repo-maintenance.yml`
- dispatch of repo-maintenance validation scripts under `scripts/repo-maintenance/validations/`

## Expected Flow

1. Finish release-candidate work on a feature branch or worktree.
2. Keep the worktree clean.
3. Run the standard release command:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

4. Let the repo-maintenance validation check run.
5. Let the script push the branch and tag, open or update the PR, watch CI, check review state, merge, fast-forward `main`, create the GitHub release, and clean up merged branches.
6. Run any post-release live-service refresh or staged-artifact promotion only when that operation is explicitly part of the release task.

## Validation Shape

The repository uses one authoritative GitHub validation workflow: `.github/workflows/validate-repo-maintenance.yml`.

That workflow installs the local formatting and linting tools and then runs:

```bash
bash scripts/repo-maintenance/validate-all.sh
```

The local validation dispatcher covers the managed toolkit checks and the repo-specific Swift package checks that remain under `scripts/repo-maintenance/validations/`, including build, test, DocC, CLI smoke, SwiftFormat, and SwiftLint.

Keep new required validation inside `validate-all.sh` unless there is a clear reason a separate GitHub-only workflow must own it.

## Defaults

Release defaults live in `scripts/repo-maintenance/config/release.env`.

Current defaults:

- default release mode: `standard`
- release branch: `main`

The explicit repo-maintenance profile lives in `scripts/repo-maintenance/config/profile.env` and is currently `swift-package`.

## Safety Properties

- Standard mode requires a named feature branch or worktree.
- Standard mode refuses to run from the configured base branch.
- Standard mode requires a clean worktree before release work starts.
- Standard mode creates the annotated tag before pushing the branch and tag.
- Standard mode uses a pull request and watches CI before merge.
- Standard mode stops on requested changes or unresolved review/discussion comments unless rerun with `--review-comments-addressed` after the comment pass is intentionally complete.
- Standard mode creates the GitHub release from the pushed tag with `--verify-tag`.
- Submodule mode leaves parent repository pointer updates to a separate follow-up commit.
