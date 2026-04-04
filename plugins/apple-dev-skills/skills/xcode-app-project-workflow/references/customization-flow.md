# Xcode Workflow Customization Contract

## Purpose

Tune the documented policy defaults for MCP-first execution, fallback behavior, and mutation safety.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `mcpRetryCount` | `1` | `runtime-enforced` | Controls the retry count emitted by `scripts/run_workflow.py` for transient MCP failures. |
| `requireExplicitMutationOptInForFilesystemFallback` | `true` | `runtime-enforced` | Controls whether `scripts/run_workflow.py` blocks direct filesystem fallback planning in Xcode-managed scope without explicit opt-in. |
| `advisoryCooldownDays` | `21` | `runtime-enforced` | Controls the advisory cooldown window used by `scripts/run_workflow.py`. |
| `fallbackCommandMappingProfile` | `official-default` | `runtime-enforced` | Controls the fallback-command profile emitted by `scripts/run_workflow.py`. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` loads the effective merged customization state at runtime.
- `scripts/advisory_cooldown.py` and `scripts/detect_xcode_managed_scope.sh` remain helper scripts used by `scripts/run_workflow.py`.
- MCP tool execution remains agent-side and is not performed by the local runtime script.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md` and the affected workflow references to reflect the approved policy change.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Verify the new values appear in `scripts/run_workflow.py --operation-type build --dry-run`.

## Validation

1. Verify the docs still describe a single MCP-first execution workflow.
2. Verify retry count and mutation gate are stated consistently across the skill and references.
3. Verify `scripts/run_workflow.py` reflects the runtime-enforced knobs above.
