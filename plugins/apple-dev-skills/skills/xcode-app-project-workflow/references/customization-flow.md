# Xcode Workflow Customization Contract

## Purpose

Tune the documented policy defaults for MCP-first execution, fallback behavior, and mutation safety.

## Knobs

This skill no longer exposes ordinary user-facing customization knobs.

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` still loads customization state, but the current workflow uses fixed safety defaults rather than ordinary user-facing customization knobs.
- `scripts/advisory_cooldown.py` and `scripts/detect_xcode_managed_scope.sh` remain helper scripts used by `scripts/run_workflow.py`.
- MCP tool execution remains agent-side and is not performed by the local runtime script.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md` and the affected workflow references to reflect the approved policy change.
3. Keep `references/customization.template.yaml` present for install-surface consistency even when `settings` is empty.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Verify `scripts/run_workflow.py --operation-type build --dry-run` still emits the fixed workflow defaults.

## Validation

1. Verify the docs still describe a single MCP-first execution workflow.
2. Verify the mutation gate and fallback posture are still stated consistently across the skill and references.
3. Verify `scripts/run_workflow.py` reflects the fixed workflow defaults described above.
