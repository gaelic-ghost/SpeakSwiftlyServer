# Xcode App Bootstrap Customization Contract

## Purpose

Adjust the documented bootstrap defaults while keeping runtime behavior grounded in the actual wrapper and implementation scripts.

## Knobs

| Knob | Default | Status | Effect |
| --- | --- | --- | --- |
| `defaultProjectKind` | `app` | `runtime-enforced` | Keeps the workflow constrained to native Apple app bootstrap. |
| `defaultPlatform` | `ask` | `runtime-enforced` | Sets the runtime default platform when the request does not make it clear. |
| `defaultUIStack` | `swiftui` | `runtime-enforced` | Sets the runtime default UI stack. |
| `defaultProjectGenerator` | `ask` | `runtime-enforced` | Controls whether the wrapper chooses `xcode`, `xcodegen`, or blocks for confirmation. |
| `defaultOrgIdentifier` | `com.example` | `runtime-enforced` | Provides the bundle-ID prefix when an explicit bundle identifier is not supplied. |
| `copyAgentsMd` | `true` | `runtime-enforced` | Controls whether the wrapper copies `assets/AGENTS.md` into the new repo. |
| `validationMode` | `full` | `runtime-enforced` | Controls whether the supported path runs project introspection after generation. |

## Runtime Behavior

- `scripts/customization_config.py` reads, writes, resets, and reports customization state.
- `scripts/run_workflow.py` loads the effective merged customization state at runtime.
- `scripts/bootstrap_xcode_app_project.py` remains the implementation core for the current XcodeGen-backed scaffold path.

## Update Flow

1. Inspect current settings with `scripts/customization_config.py effective`.
2. Update `SKILL.md`, `references/project-generators.md`, and `references/automation-prompts.md` to reflect the approved policy change.
3. Persist the metadata change with `scripts/customization_config.py apply --input <yaml-file>`.
4. Re-run `scripts/customization_config.py effective` and confirm the stored values match the docs.
5. Use `scripts/customization_config.py reset` only when the user explicitly wants to clear customization state.
6. Verify runtime defaults with `scripts/run_workflow.py --name DemoApp --platform macos --project-generator xcodegen --dry-run`.

## Validation

1. Run the bootstrap workflow once with defaults through `--dry-run`.
2. Run the bootstrap workflow once with explicit overrides.
3. Verify `scripts/run_workflow.py` reflects the runtime-enforced knobs above.
4. When the supported implementation path changes, add coverage for the new runtime behavior in `tests/`.
