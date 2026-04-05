# Swift Style Tooling Customization Contract

## Purpose

Tune the documented default preferences for selecting SwiftLint and SwiftFormat integration paths.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `defaultToolSelection` | `both` | `policy-only` | Sets the default planning posture when the user wants “style tooling” without naming one tool. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/export_swiftformat_xcode_config.py` is deterministic, but it does not currently read these customization knobs.
- Surface selection, plugin preference, config-file placement, and host-app export preference now live as workflow defaults rather than durable user customization.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md` and the affected references to reflect the approved default-policy change.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Verify the references and automation prompts still describe the same defaults.

## Validation

1. Verify the support matrix in `references/integration-matrix.md` still matches `SKILL.md`.
2. Verify every customization knob is described consistently across `SKILL.md`, this file, and `references/automation-prompts.md`.
3. Verify the customization template remains under `references/customization.template.yaml`.
