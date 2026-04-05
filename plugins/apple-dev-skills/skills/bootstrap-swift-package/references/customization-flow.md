# Bootstrap Customization Contract

## Purpose

Adjust the documented bootstrap defaults while keeping runtime behavior grounded in the actual script.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `defaultVersionProfile` | `current-minus-one` | `runtime-enforced` | Sets the runtime default version profile used by `scripts/run_workflow.py`. |
| `defaultTestingMode` | `swift-testing` | `runtime-enforced` | Sets the runtime default testing mode used by `scripts/run_workflow.py`. |
| `initializeGit` | `true` | `runtime-enforced` | Controls whether the wrapper asks the shell script to initialize git. |
| `copyAgentsMd` | `true` | `runtime-enforced` | Controls whether the wrapper asks the shell script to copy `AGENTS.md`. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` loads the effective merged customization state at runtime.
- Package type and platform preset are now inference-first workflow choices or explicit CLI inputs rather than durable user customization.
- `scripts/bootstrap_swift_package.sh` remains the implementation core and now honors the wrapper's git and `AGENTS.md` copy flags.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md`, `references/package-types.md`, and `references/automation-prompts.md` to reflect the approved policy change.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Use `scripts/customization_config.py reset` only when the user explicitly wants to clear customization state.
6. Verify runtime defaults with `scripts/run_workflow.py --name DemoPkg --dry-run`.

## Validation

1. Run the bootstrap workflow once with defaults.
2. Run the bootstrap workflow once with explicit overrides.
3. Verify `Package.swift`, `.git`, `AGENTS.md`, and `Tests/` exist.
4. Verify `scripts/run_workflow.py` reflects the runtime-enforced knobs above, including the selected testing mode.
