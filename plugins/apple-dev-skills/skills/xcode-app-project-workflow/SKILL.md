---
name: xcode-app-project-workflow
description: Guide Apple and Swift development work in or around Xcode, including workspace inspection, diagnostics, builds, tests, runs, toolchain checks, mutation guard decisions, and official CLI fallback planning. Use for existing Apple or Swift projects when Xcode-aware execution is needed.
---

# Xcode App Project Workflow

## Purpose

Use this skill as the top-level entry point for Apple and Swift execution work in or around Xcode. The skill guides agent-side tool use and applies the shared simplicity-first Swift policy, while `scripts/run_workflow.py` enforces local policy, mutation guards, advisory cooldown behavior, and structured fallback planning. New layers and dependencies are often unnecessary and need extra review; keep this workflow focused on execution rather than broadening it back into docs-management or repo-sync responsibilities. Codex Plugin and Claude Code Plugin installs for the bundled Apple skill set are now the preferred install path going forward.

## When To Use

- Use this skill for Xcode workspace inspection, read or search, diagnostics, build, test, and run tasks.
- Use this skill for Swift toolchain checks and official Apple CLI fallback.
- Use this skill when direct filesystem mutation in an Xcode-managed scope may be required.
- Use this skill after Apple or Swift docs have already been gathered through `explore-apple-swift-docs` and the work has shifted into execution or implementation.
- Recommend `explore-apple-swift-docs` when the user needs Apple or Swift documentation lookup, source selection, Dash compatibility, or docs install follow-up rather than execution work.
- Recommend `swift-style-tooling-workflow` when the user needs to integrate or maintain SwiftLint or SwiftFormat across CLI, Xcode, SwiftPM, Git hooks, GitHub Actions, or SwiftFormat config export rather than active Xcode execution work.
- Recommend `bootstrap-swift-package` when the user needs to create a brand new Swift package rather than work inside an existing Xcode or Swift project.
- Recommend `sync-xcode-project-guidance` when an existing Xcode app repo needs `AGENTS.md` or workflow-guidance alignment rather than active engineering work.
- Mention that older references to `apple-xcode-workflow` now map to `xcode-app-project-workflow`.
- Mention that Codex Plugin or Claude Code Plugin installs are the preferred install path going forward.

## Single-Path Workflow

1. Classify the request into one operation type:
   - workspace or session inspection
   - read, search, or diagnostics
   - build, test, or run
   - package or toolchain management
   - mutation
2. Apply the Apple docs gate before any Apple design, architecture, implementation, or refactor guidance:
   - use `explore-apple-swift-docs` to gather the relevant Apple documentation first
   - state the documented API behavior, lifecycle rule, or workflow requirement being relied on before proposing changes
   - do not rely on memory as the primary source when Apple docs exist
   - if the docs and the current code conflict, stop and report that conflict
   - if no relevant Apple docs can be found, say that explicitly before proceeding
3. Apply the shared Swift policy before giving implementation guidance:
   - apply the detailed local policy in `references/snippets/apple-xcode-project-core.md`
   - preserve its simplicity-first, shape-preserving, and anti-ceremony Swift guidance
   - preserve its project-appropriate logging, telemetry, and SwiftUI architecture guidance
4. Run `scripts/run_workflow.py` to apply runtime configuration, mutation-guard checks, advisory cooldown, and CLI fallback planning.
5. Use the guidance in `references/mcp-tool-matrix.md` for agent-executed MCP operations.
6. If MCP fails, use the structured fallback output from `scripts/run_workflow.py` together with `references/cli-fallback-matrix.md`.
7. Report which parts were agent-executed, which parts were locally enforced by script, the Apple docs relied on, and any required next step.

## Inputs

- `operation_type`: one of the operation types listed above.
- `workspace_path`: optional absolute path for the target Xcode or Swift workspace.
- `tab_identifier`: optional MCP tab identifier when already known.
- `mcp_failure_reason`: optional input when continuing from an earlier MCP failure.
- `filesystem_fallback_opt_in`: optional explicit opt-in when planning direct filesystem fallback in Xcode-managed scope.
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - agent-side MCP retries once for transient failures
  - advisory cooldown is `21` days
  - mutation operations require the explicit guard in Xcode-managed scope

## Outputs

- `status`
  - `success`: the workflow completed on its primary or fallback path
  - `blocked`: prerequisites, policy, or mutation safeguards prevented completion
  - `handoff`: the workflow is handing off supporting context to another step or skill
- `path_type`
  - `primary`: the guided agent-side MCP path completed successfully
  - `fallback`: the official CLI fallback path completed successfully
- `output`
  - operation type
  - `guard_result`
  - `fallback_commands`
  - advisory status
  - one next step or handoff payload when needed

## Guards and Stop Conditions

- Apply the mutation guard from `references/mutation-risk-policy.md` only when the operation type is `mutation`.
- Do not skip the mutation guard for direct filesystem edits inside Xcode-managed scope.
- Stop with `blocked` when the required workspace context cannot be resolved and the operation cannot safely continue.
- Stop with `blocked` when allowlist or sandbox rules prevent the official CLI fallback and no safe alternative exists.

## Fallbacks and Handoffs

- Official CLI execution is the only fallback path when the primary agent-side MCP path cannot complete.
- Use `references/mcp-failure-handoff.md` for the canonical fallback and handoff payload.
- Use `references/allowlist-guidance.md` when a safe official CLI fallback is blocked by local rules.
- Recommend `explore-apple-swift-docs` directly when the task becomes Apple or Swift docs exploration work.
- Recommend `swift-style-tooling-workflow` directly when the task becomes SwiftLint or SwiftFormat setup, config export, or style-tooling maintenance work.
- Recommend `bootstrap-swift-package` directly when the task becomes new-package scaffolding.
- Recommend `sync-xcode-project-guidance` directly when the repo needs Xcode-specific guidance sync rather than execution.
- `scripts/run_workflow.py` plans fallback commands; MCP execution itself remains agent-side tool usage guided by this skill.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` still reads customization state, but the current workflow uses fixed safety defaults rather than ordinary user-facing customization knobs.
- MCP tool execution itself remains agent-side and is not performed by the local runtime entrypoint or by the skill as a direct runtime.

## References

### Workflow References

- `references/workflow-policy.md`
- `references/mcp-tool-matrix.md`
- `references/cli-fallback-matrix.md`
- `references/toolchain-management.md`
- `references/mutation-risk-policy.md`
- `references/mutation-via-mcp.md`

### Contract References

- `references/mcp-failure-handoff.md`
- `references/customization-flow.md`

### Support References

- Recommend `explore-apple-swift-docs` when the user needs Apple or Swift docs exploration or Dash-compatible docs access.
- Recommend `swift-style-tooling-workflow` when the user needs SwiftLint or SwiftFormat setup rather than active Xcode execution.
- Recommend `sync-xcode-project-guidance` when the user needs repo guidance aligned inside an existing Xcode app repo.
- Recommend `references/snippets/apple-xcode-project-core.md` when the user needs to add or merge the shared Xcode-project guidance into an end-user repo.
- `references/allowlist-guidance.md`
- `references/skills-installation.md`
- `references/mcp-setup-advisory.md`
- `references/skills-discovery.md`
- `references/snippets/apple-xcode-project-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/advisory_cooldown.py`
- `scripts/detect_xcode_managed_scope.sh`
- `scripts/customization_config.py`
