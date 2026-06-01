# SpeakSwiftlyAgent Next Slices

This plan keeps `SpeakSwiftlyAgent` as a maintainer-side assistant under `Tools/`. It is not a
Swift package product, not a runtime transport, and not a replacement for the repo-owned release
scripts.

## Slice 2: Richer Repo Snapshot

- Read `Package.resolved` alongside `Package.swift` so dependency reports can distinguish declared
  requirements from the exact resolved revision.
- Detect the current pull request, latest release tag, and whether the local branch is ahead of or
  behind its upstream.
- Keep repo discovery path-tolerant so commands work from the checkout root or a nested directory.

## Slice 3: Approval-Gated Local Actions

- Add a small command registry for safe local actions such as running focused validation,
  refreshing dependency plans, or preparing a branch cleanup command list.
- Keep every action dry-run first. Branch deletion, pushes, tags, releases, live service operations,
  and GitHub writes must require explicit maintainer approval outside the agent.
- Preserve the repo release scripts as the only release entrypoint.

## Slice 4: Guidance Sync Catalog

- Expand the current guidance-sync handoff catalog to cover the repo-maintenance, Swift package,
  Python tool, and docs surfaces that this repository already uses.
- Emit concrete Codex prompts, local validation commands, and doc targets instead of trying to run
  Codex skills from inside Python.
- Keep handoffs short enough to paste into a Codex turn without losing the repo context.

## Slice 5: Explain And Update Modes

- Add an explanation mode for common maintainer questions: package layout, release flow, validation
  lanes, plugin hook diagnostics, and SpeakSwiftly dependency updates.
- Add a dependency-update assistant that prepares the intended command sequence and verification
  checklist while leaving actual edits and remote actions approval-gated.
- Consider an optional LLM-backed mode only after the deterministic workflows are useful on their
  own.

## Slice 6: Persistence And Resume

- Replace the in-memory graph checkpoint only when there is a concrete long-running workflow that
  benefits from resume support.
- Keep persisted state local to `Tools/SpeakSwiftlyAgent` and avoid storing secrets, API keys,
  LaunchAgent state, or live service payloads.
