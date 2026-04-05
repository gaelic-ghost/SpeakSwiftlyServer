# Swift Style Tooling Automation Contract

## Purpose

Provide one consistent automation contract for selecting and applying a supported SwiftLint or SwiftFormat integration path.

## Inputs

- `tool_selection`
- `surface`
- `repository_kind`
- `config_goal`
- `swiftformat_export_source`

## Constraints

- Do not imply support for a tool on a surface it does not actually ship.
- Prefer checked-in project config over user-local-only state.
- Keep the chosen path explicit about whether it is the preferred or fallback path.
- When exporting SwiftFormat for Xcode settings, prefer the host app export flow before the shared-defaults script unless the request explicitly calls for the scriptable path.

## Status Values

- `success`
- `handoff`
- `blocked`

## Output

- `status`
- `path_type`
- `tool_selection`
- `surface`
- `recommended_path`
- `config_files`
- `caveats`
- `verification`

## Codex App Prompt Template

```text
Use $swift-style-tooling-workflow.

Choose one supported SwiftLint and/or SwiftFormat setup path with:
- Tool selection: <TOOL_SELECTION>
- Surface: <SURFACE>
- Repository kind: <REPOSITORY_KIND>
- Config goal: <CONFIG_GOAL>
- SwiftFormat export source preference: <SWIFTFORMAT_EXPORT_SOURCE>

Execution requirements:
1) Check `references/integration-matrix.md` before proposing steps.
2) Use only the documented tool-specific surface guidance from `references/swiftformat-surfaces.md`, `references/swiftlint-surfaces.md`, and `references/swiftformat-xcode-config-export.md`.
3) If the request is for SwiftFormat for Xcode settings export, prefer the host app export path unless the script path is explicitly needed.
4) If the request is for the scriptable export path, use `scripts/export_swiftformat_xcode_config.py`.
5) Stop and return `blocked` if the requested tool and surface combination is unsupported.

Return the documented contract only:
- `status`
- `path_type`
- `tool_selection`
- `surface`
- `recommended_path`
- `config_files`
- `caveats`
- `verification`
```

## Codex CLI Prompt Template

```text
Use $swift-style-tooling-workflow for a deterministic style-tooling setup pass.

Task:
Set up or explain one supported path for:
- `tool_selection=<TOOL_SELECTION>`
- `surface=<SURFACE>`
- `repository_kind=<REPOSITORY_KIND>`
- `config_goal=<CONFIG_GOAL>`
- `swiftformat_export_source=<SWIFTFORMAT_EXPORT_SOURCE>`

Constraints:
- Do not invent unsupported integrations.
- Prefer repo-pinned and checked-in configuration where the upstream tool supports it.
- Name the exact caveats that affect the chosen path.
- If exporting SwiftFormat for Xcode settings, prefer the host app export path before the shared-defaults script unless the task explicitly requires scriptable output.

Verification:
- Confirm the selected path is documented in the skill references.
- Confirm the chosen config file locations are explicit.
- Confirm the follow-up step tells the user how to verify the integration actually runs.

Return contract:
- `status: success|handoff|blocked`
- `path_type: <primary|fallback>`
- `tool_selection: <resolved tools>`
- `surface: <resolved surface>`
- `recommended_path: <brief summary>`
- `config_files: <expected files>`
- `caveats: <source-backed caveats>`
- `verification: <one follow-up verification step>`
```
