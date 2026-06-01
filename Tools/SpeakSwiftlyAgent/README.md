# SpeakSwiftlyAgent

`SpeakSwiftlyAgent` is a maintainer-side repo assistant for `SpeakSwiftlyServer`.
It is intentionally not part of the Swift package products and does not expose a runtime
transport surface.

The first slice is a safe, read-mostly LangGraph workflow that can:

- summarize the repository state;
- plan a dependency update;
- audit merged branches without deleting anything;
- produce Codex handoff prompts for guidance-sync skills.

See [`docs/next-slices.md`](docs/next-slices.md) for the next planned maintainer-agent slices.

## Run

```bash
uv run speak-swiftly-agent overview
uv run speak-swiftly-agent dependency-plan --package SpeakSwiftly --target-version v11.0.0-alpha.1
uv run speak-swiftly-agent branch-audit
uv run speak-swiftly-agent guidance-sync --kind swift-package
```

Run from `Tools/SpeakSwiftlyAgent`, or pass `--repo-root` to point at a checkout.

## Validate

```bash
uv run pytest
uv run ruff check .
uv run mypy .
```

The repository-local `sh scripts/repo-maintenance/validate-all.sh` gate also runs these checks when
`Tools/SpeakSwiftlyAgent` is present.

## Safety

The agent does not push, tag, release, delete branches, or touch the live LaunchAgent-backed
service. It reports commands and handoff prompts that a maintainer can approve and run through the
normal Codex or repo-maintenance workflow.

## Guidance Sync

The agent cannot directly invoke Codex-installed skills from inside an ordinary Python process.
Instead, it keeps a small handoff catalog for skills such as `sync-swift-package-guidance` and emits
copyable prompts and local validation commands. That keeps the skill boundary explicit while still
making guidance-sync work discoverable from the agent.
