---
name: swift-style-tooling-workflow
description: Guide SwiftLint and SwiftFormat integration across CLI, Xcode build phases, Xcode source-editor workflows, Swift Package plugins, AppleScript, Git hooks, and GitHub Actions, including exporting SwiftFormat for Xcode settings into a checked-in project config file.
---

# Swift Style Tooling Workflow

## Purpose

Use this skill as the top-level workflow for integrating and maintaining SwiftLint and SwiftFormat in Apple or Swift repositories. The skill keeps the support matrix explicit, teaches the shortest correct path for each surface, and includes a deterministic helper script for turning SwiftFormat for Xcode shared settings into a project-root `.swiftformat` file when the host app export path is unavailable or inconvenient.

## When To Use

- Use this skill when the user wants to add or maintain `swiftformat`, `swiftlint`, or both in a Swift repository.
- Use this skill when the user wants guidance for one of these integration surfaces:
  - CLI
  - Xcode Run Script Build Phase
  - Xcode source editor extension
  - Swift Package Manager plugin
  - AppleScript or Automator-style local triggers
  - Git pre-commit hook
  - GitHub Actions
- Use this skill when the user wants to promote personal SwiftFormat for Xcode settings into a checked-in `.swiftformat` file.
- Use this skill when the user needs the supported-path caveats for SwiftLint or SwiftFormat, such as plugin config-path limitations, Xcode script sandboxing, or per-project config gaps in the SwiftFormat extension.
- Recommend `bootstrap-swift-package` when the user is creating a brand new Swift package and style tooling is only one part of that scaffold.
- Recommend `bootstrap-xcode-app-project` when the user is creating a brand new native Apple app project and style tooling is only one part of that scaffold.
- Recommend `xcode-app-project-workflow` when the task shifts from style-tooling integration to active Xcode execution, diagnostics, or mutation work in an existing project.
- Recommend `sync-xcode-project-guidance` or `sync-swift-package-guidance` when the user is aligning `AGENTS.md` and repo guidance rather than integrating style tooling itself.

## Single-Path Workflow

1. Classify the request by tool selection:
   - `swiftformat`
   - `swiftlint`
   - `both`
2. Classify the request by surface:
   - `cli`
   - `xcode-build-phase`
   - `xcode-source-extension`
   - `swiftpm-plugin`
   - `applescript`
   - `git-pre-commit`
   - `github-actions`
   - `swiftformat-xcode-config-export`
3. Check the support matrix in `references/integration-matrix.md` before proposing or generating steps.
4. Choose one documented path:
   - for SwiftFormat settings export, prefer the host app export flow in `references/swiftformat-xcode-config-export.md`
   - use `scripts/export_swiftformat_xcode_config.py` only when a deterministic shared-defaults export is needed
   - for all other surfaces, use the tool-specific references instead of inventing a hybrid path
5. Return one supported setup path, one set of caveats, and one follow-up verification step.

## Inputs

- `tool_selection`: `swiftformat`, `swiftlint`, or `both`
- `surface`: one of the workflow surfaces listed above
- `repository_kind`: optional context such as `swift-package`, `xcode-project`, or `mixed`
- `config_goal`: optional; use values such as `new-config`, `reuse-existing`, or `export-xcode-settings`
- `swiftformat_export_source`: optional; use `host-app-export` or `shared-defaults-script`
- Defaults:
  - prefer checked-in project-root config files
  - prefer package or repo-pinned tooling over developer-local version drift
  - prefer SwiftLint plugins for plugin-based SwiftLint adoption
  - prefer the SwiftFormat host app export path before the shared-defaults script path

## Outputs

- `status`
  - `success`: a supported path was selected and explained
  - `handoff`: another skill should own the next step
  - `blocked`: the requested tool and surface combination is unsupported or lacks prerequisites
- `path_type`
  - `primary`: the documented preferred path for the selected tool and surface
  - `fallback`: the documented secondary path for that tool and surface
- `output`
  - `tool_selection`
  - `surface`
  - `recommended_path`
  - `config_files`
  - `caveats`
  - `verification`

## Guards and Stop Conditions

- Do not imply support for `swiftlint` through the Xcode source editor extension. SwiftLint does not ship that surface.
- Do not imply that the SwiftFormat for Xcode extension reads per-project config automatically. The config must be imported into the host app.
- Do not imply that SwiftLint build tool plugins accept arbitrary `--config` paths. When config placement is incompatible with the plugin, switch to the documented shim or Run Script path.
- Stop with `blocked` when the user asks for one tool on a surface that only the other tool supports.
- Stop with `blocked` when the shared-defaults SwiftFormat export path is requested on a machine that does not expose the SwiftFormat shared defaults domain and no exported plist input is provided.

## Fallbacks and Handoffs

- SwiftFormat config export falls back from host-app export to `scripts/export_swiftformat_xcode_config.py`.
- SwiftLint plugin adoption falls back to an Xcode Run Script Build Phase when plugin constraints conflict with config placement or project layout.
- SwiftFormat build-phase adoption falls back from package-managed or pinned local binaries to the locally installed CLI path only when shared-version drift is acceptable.
- Recommend `xcode-app-project-workflow` when the task becomes Xcode execution or diagnostics work.
- Recommend `bootstrap-swift-package` or `bootstrap-xcode-app-project` when the user really needs a full project scaffold instead of isolated style-tooling setup.
- Recommend `sync-xcode-project-guidance` or `sync-swift-package-guidance` when the repository needs broader `AGENTS.md` and workflow-baseline alignment.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` reads, writes, resets, and reports per-skill customization metadata.
- The current customization surface is one policy-only guidance default for tool selection. This skill has no `run_workflow.py` runtime entrypoint at present.

## References

### Workflow References

- `references/integration-matrix.md`
- `references/swiftformat-surfaces.md`
- `references/swiftlint-surfaces.md`
- `references/swiftformat-xcode-config-export.md`

### Contract References

- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- Recommend `references/snippets/apple-xcode-project-core.md` when the user wants the shared Apple and Xcode-project baseline guidance in the same repo that is adopting SwiftLint or SwiftFormat.
- `references/snippets/apple-xcode-project-core.md`

### Script Inventory

- `scripts/customization_config.py`
- `scripts/export_swiftformat_xcode_config.py`
