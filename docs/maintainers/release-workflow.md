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

The standard flow runs `scripts/repo-maintenance/version-bump.sh` before the release PR is pushed. That hook updates the checked-in Codex plugin manifest version to match the release version so plugin consumers, marketplace metadata, and GitHub release tags do not drift silently.

The standard flow is a durable repo-maintenance path. It validates the checkout, runs the local live E2E gate, pushes the release branch, opens or updates the release PR, watches CI, checks for review comments, merges the PR, fast-forwards local `main`, creates the annotated tag from the reviewed base-branch commit, pushes that tag, creates the GitHub release with `gh release create --verify-tag`, updates the local LaunchAgent-backed live service from the synced `main` checkout, healthchecks HTTP and MCP, and cleans up merged local branches when safe.

When full local validation has already run and the remote CI wait is expected to be long, use deferred remote CI mode:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z --remote-ci-mode defer
```

Deferred mode still validates locally, pushes the branch, opens or updates the release PR, and waits until GitHub reports initial checks. It then pauses so Codex can use a native thread Timer/Wakeup or heartbeat automation and resume in the same thread after CI settles instead of leaving a shell process open to poll GitHub.

## Context Rules

### Feature Branch Or Worktree

Use the standard flow from a named feature branch or worktree:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

The flow refuses to run standard mode from the protected base branch. It also requires a separate local checkout that owns the base branch, normally `main`: the release worktree owns the PR branch, while the base checkout fast-forwards the reviewed merge, creates the tag, and performs any live-service promotion. If release-candidate commits were accidentally made directly on local `main`, branch from that tip before continuing so the release still goes through a pull request.

### Local `main`

Local `main` is the protected release branch and should normally be a sync surface, not the release automation workspace. After the standard release flow merges its PR, it finds the checkout that owns `main`, fast-forwards it from `origin/main`, creates the tag there, and uses that synced checkout for the live-service update and HTTP/MCP healthcheck.

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
- `--skip-local-e2e`
- `--skip-version-bump`
- `--skip-gh-release`
- `--skip-live-service-update`
- `--review-comments-addressed`
- `--remote-ci-mode <full|defer>`
- `--skip-branch-cleanup`
- `--dry-run`

### `scripts/repo-maintenance/validate-all.sh`

Purpose:

- one local maintainer validation entrypoint
- dispatch of repo-maintenance validation scripts under `scripts/repo-maintenance/validations/`

### `scripts/repo-maintenance/validate-local-e2e.sh`

Purpose:

- local release-owned live end-to-end gate
- resident-model unload preflight against the installed LaunchAgent-backed service
- serialized `ServerTransportE2ETests` run with `SPEAKSWIFTLYSERVER_E2E=1`
- resident-model reload cleanup after pass or failure

### `scripts/repo-maintenance/validate-ci.sh`

Purpose:

- GitHub Actions validation entrypoint
- local compatibility wrapper for checking CI-oriented repo-maintenance wiring
- narrower CI-shape check that keeps package build and tests without repeating the full local maintainer gate

## Expected Flow

1. Finish release-candidate work on a feature branch or worktree.
2. Keep the worktree clean.
3. Run the standard release command:

```bash
scripts/repo-maintenance/release.sh --mode standard --version vX.Y.Z
```

4. Let the repo-maintenance validation check and local live E2E gate run.
5. Let the script push the branch, open or update the PR, watch CI, check review state, merge, fast-forward `main`, create and push the annotated tag, create the GitHub release, update the live LaunchAgent-backed service from synced local `main`, run `SpeakSwiftlyServerTool healthcheck`, and clean up merged branches.
6. Use `--skip-local-e2e` only when the release intentionally cannot touch the live service on this machine and another concrete live E2E signal exists for the release candidate.
7. Use `--skip-live-service-update` only when the release is intentionally metadata-only for this machine or when a maintainer will refresh the live service from a different checkout.

For deferred remote CI:

1. Run full local validation before the release command.
2. Run the standard release command with `--remote-ci-mode defer`.
3. Let the script stop after branch push, PR creation, and initial check discovery.
4. Use a native Codex thread Timer/Wakeup or heartbeat automation to resume after CI settles.
5. Rerun the standard release command without `--remote-ci-mode defer` to finish review checks, merge, tag, GitHub release creation, live-service update, and cleanup.

## Validation Shape

The repository uses one authoritative GitHub validation workflow: `.github/workflows/validate-repo-maintenance.yml`.

That workflow runs:

```bash
bash scripts/repo-maintenance/validate-ci.sh
```

The GitHub workflow uses the lighter CI wrapper so remote checks stay focused on toolkit layout, agent guidance, Codex plugin fixtures, workflow wiring, package build, and package tests. The full local maintainer gate still lives in `validate-all.sh`, including DocC, CLI smoke, SwiftFormat, and SwiftLint.

Keep new required non-live validation inside `validate-all.sh` unless it belongs specifically to a local CI-wrapper compatibility check.

Local live E2E remains release-owned instead of GitHub-owned because it intentionally touches Gale's installed LaunchAgent-backed live service to unload and reload resident models around the test helper. Keep that behavior in `validate-local-e2e.sh` and call it from `release.sh`; do not add live-service operations to the GitHub Actions maintainer gate.

## Defaults

Release defaults live in `scripts/repo-maintenance/config/release.env`.

Current defaults:

- default release mode: `standard`
- release branch: `main`
- remote CI mode: `full`

The explicit repo-maintenance profile lives in `scripts/repo-maintenance/config/profile.env` and is currently `swift-package`.

## Safety Properties

- Standard mode requires a named feature branch or worktree.
- Standard mode refuses to run from the configured base branch.
- Standard mode requires a clean worktree before release work starts.
- Standard mode runs local live E2E by default after `validate-all.sh` and before the release branch is pushed.
- Standard mode can skip that local live E2E gate with `--skip-local-e2e` only when another concrete live E2E signal exists for the release candidate.
- Standard mode can defer remote CI after initial check discovery with `--remote-ci-mode defer`; deferred mode is a pause point, not a completed release.
- Standard mode waits for the release PR to pass CI and review-comment checks before it creates the annotated tag.
- Standard mode dereferences existing annotated tags before comparing them with `HEAD` so reruns do not confuse the tag object SHA for the tagged commit SHA.
- Standard mode uses a pull request and watches CI before merge.
- Standard mode stops on requested changes or unresolved review/discussion comments unless rerun with `--review-comments-addressed` after the comment pass is intentionally complete.
- Standard mode creates the GitHub release from the pushed tag with `--verify-tag`.
- Standard mode updates the LaunchAgent-backed live service only after local `main` has been fast-forwarded and the versioned GitHub release exists.
- Standard mode immediately runs the server healthcheck after the live-service update so HTTP and MCP startup failures block the release handoff.
- Submodule mode leaves parent repository pointer updates to a separate follow-up commit.
