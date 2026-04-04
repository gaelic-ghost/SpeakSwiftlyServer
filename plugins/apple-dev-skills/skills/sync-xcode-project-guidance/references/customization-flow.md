# Xcode Project Guidance Sync Customization Contract

## Purpose

Adjust the documented guidance-sync defaults while keeping runtime behavior grounded in the actual wrapper and implementation scripts.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `copyAgentsTemplateWhenMissing` | `true` | `runtime-enforced` | Controls whether the workflow creates `AGENTS.md` from `assets/AGENTS.md` when the file is missing. |
| `appendSectionWhenAgentsExists` | `true` | `runtime-enforced` | Controls whether the workflow appends the bounded Xcode guidance section when `AGENTS.md` already exists but lacks that section. |
| `validationMode` | `full` | `runtime-enforced` | Controls whether the supported path verifies the synced `AGENTS.md` content after writing. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` loads the effective merged customization state at runtime.
- `scripts/sync_xcode_project_guidance.py` remains the implementation core for the current guidance-sync path.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md`, `assets/AGENTS.md`, and `assets/append-section.md` to reflect the approved policy change.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Use `scripts/customization_config.py reset` only when the user explicitly wants to clear customization state.
6. Verify runtime defaults with `scripts/run_workflow.py --repo-root . --dry-run`.

## Validation

1. Run the workflow once with `--dry-run`.
2. Run the workflow once on a repo with no `AGENTS.md`.
3. Run the workflow once on a repo with an existing `AGENTS.md` that lacks the Xcode section.
4. Verify `scripts/run_workflow.py` reflects the runtime-enforced knobs above.
