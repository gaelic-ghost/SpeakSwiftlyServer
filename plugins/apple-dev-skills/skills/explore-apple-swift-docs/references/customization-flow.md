# Apple Swift Docs Customization Contract

## Purpose

Tune the runtime-supported defaults for Apple and Swift docs exploration, source fallback, and subordinate Dash follow-up behavior.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `defaultSourceOrder` | `xcode-mcp-docs,dash,official-web` | `runtime-enforced` | Controls the default docs-source order used by `scripts/run_workflow.py` for `explore` mode. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` loads the effective merged customization state at runtime.
- Match count, snippet shaping, Dash install source priority, install approval gating, Dash generation policy, and blocked-state troubleshooting posture now live as workflow defaults rather than ordinary durable user customization.
- Helper scripts remain implementation details behind `scripts/run_workflow.py`.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md`, `references/automation-prompts.md`, and the affected workflow references.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Verify the runtime output with `scripts/run_workflow.py --mode explore --query Swift --dry-run`.

## Validation

1. Run `scripts/dash_api_probe.py`.
2. Run `scripts/dash_catalog_match.py --query "swift"`.
3. Verify the docs still present one primary Apple and Swift docs workflow with subordinate Dash follow-up.
4. Verify `scripts/run_workflow.py` reflects the runtime-enforced knobs above.
