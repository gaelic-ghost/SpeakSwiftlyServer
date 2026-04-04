---
name: explore-apple-swift-docs
description: Explore Apple and Swift documentation across Xcode MCP docs, Dash, and official web docs, including search, browse, source selection, local-docs fallback, and optional Dash install or generation follow-up. Use when Codex needs Apple or Swift docs help rather than Xcode execution or repo-guidance sync work.
---

# Explore Apple Swift Docs

## Purpose

Explore Apple and Swift documentation through one top-level entry point. `scripts/run_workflow.py` is the authoritative runtime path for docs source selection, fallback order, Dash follow-up planning, approval gating for Dash install actions, and structured generation guidance; it does not replace the agent's own Xcode MCP, Dash, or web-doc access methods, and this skill should point users toward the shared simplicity-first Xcode-project snippet when they need reusable Apple or Swift repo guidance.

## When To Use

- Use this skill for Apple or Swift API reference lookup requests.
- Use this skill for Apple or Swift guide, tutorial, symbol, or concept search requests.
- Use this skill when the user wants local docs first, wants official docs first, or wants to compare available Apple or Swift docs sources.
- Use this skill when the user wants Dash-compatible Apple or Swift docs access, install guidance for a missing Dash docset, or generation guidance when a Dash docset is unavailable.
- Recommend `xcode-app-project-workflow` when the user needs Apple or Swift execution, diagnostics, build or test work, toolchain help, or mutation decisions inside an existing project.
- Recommend `bootstrap-xcode-app-project` when the user is starting a brand new native Apple app project.
- Recommend `sync-xcode-project-guidance` when an existing Xcode app repo needs `AGENTS.md` or workflow-guidance alignment rather than docs exploration.

## Single-Path Workflow

1. Classify the request into one docs workflow mode:
   - `explore`
   - `dash-install`
   - `dash-generate`
2. If no mode is explicit, start at `explore`.
3. Run `scripts/run_workflow.py` with the selected mode:
   - `explore`: applies configured source order, preference handling, fallback selection, and result shaping
   - `dash-install`: applies configured Dash install source priority and approval gating
   - `dash-generate`: returns structured automation-first guidance for missing Dash coverage
4. If the selected mode cannot complete, hand off forward through one clear next step:
   - `explore -> dash-install`
   - `dash-install -> dash-generate`
5. Return one `status`, one `path_type`, one `source_used`, and one output contract for the mode that ran.

## Inputs

- `mode`: `explore`, `dash-install`, or `dash-generate`
- `query`: required for `explore`
- `docs_kind`: optional for `explore`; use `api-reference`, `guide`, `symbol`, or `search` when the user intent is clear
- `preferred_source`: optional for `explore`; use `auto`, `xcode-mcp-docs`, `dash`, or `official-web`
- `mcp_failure_reason`: optional for `explore` when Xcode MCP docs were expected but are currently unavailable
- `docset_request`: required for `dash-install` and `dash-generate`
- `approval`: required before side-effectful Dash install actions
- Defaults:
  - runtime entrypoint: executable `scripts/run_workflow.py`
  - `explore` source order is `xcode-mcp-docs,dash,official-web`
  - Dash install source priority is `built-in,user-contributed,cheatsheet`
  - default search result limit is `20`
  - default search snippets setting is `true`

## Outputs

- `status`
  - `success`: the selected mode completed on its primary or fallback path
  - `blocked`: prerequisites, approval, or usable docs sources are missing
  - `handoff`: the current mode is handing off to the next docs mode
- `path_type`
  - `primary`: the selected mode completed normally
  - `fallback`: the selected mode completed through its documented fallback path
- `output`
  - `mode`
  - `source_used`
  - `configured_order` or `source_path`
  - `matches`
  - install result or generation guidance when applicable
  - one next step when follow-up is required

## Guards and Stop Conditions

- Do not run Dash install actions without explicit user approval.
- Do not invent Apple or Swift doc sources, Dash identifiers, or catalog matches.
- Stop with `blocked` when `explore` has no usable docs source after applying the documented fallback order.
- Stop with `blocked` when `dash-install` or `dash-generate` lacks a concrete docset request.
- Keep `explore`, `dash-install`, and `dash-generate` in forward order; do not blend them into competing primary workflows.

## Fallbacks and Handoffs

- `explore` falls back in this order: Xcode MCP docs, then Dash, then official web docs.
- Explicit user preference overrides the default source order when that preference is usable.
- `dash-install` hands off to `dash-generate` when no installable catalog match exists.
- `dash-generate` falls back from stable automation guidance to deterministic manual guidance.
- Recommend `xcode-app-project-workflow` directly when the user’s task shifts from docs exploration to Apple or Swift execution work.
- Recommend `bootstrap-xcode-app-project` directly when the user needs new native app scaffolding.
- Recommend `sync-xcode-project-guidance` directly when an existing Xcode app repo needs guidance sync rather than docs help.
- `scripts/run_workflow.py` is the only local runtime entrypoint for docs source selection, install gating, and follow-up behavior; helper scripts remain implementation details behind it.

## Customization

- Use `references/customization-flow.md`.
- `scripts/customization_config.py` stores and reports customization state.
- `scripts/run_workflow.py` loads and enforces the runtime-safe knobs documented in `references/customization-flow.md`.

## References

### Workflow References

- `references/xcode_mcp_docs.md`
- `references/dash_mcp_tools.md`
- `references/dash_http_api.md`
- `references/dash_url_and_service.md`
- `references/official_web_docs.md`

### Contract References

- `references/stage-handoff-contract.md`
- `references/automation-prompts.md`
- `references/customization-flow.md`

### Support References

- Recommend `references/snippets/apple-xcode-project-core.md` when the user needs a reusable Apple and Xcode-project baseline snippet in their own repo alongside Apple or Swift docs workflows.
- `references/catalog_built_in_docsets.json`
- `references/catalog_user_contrib_docsets.json`
- `references/catalog_cheatsheets.json`
- `references/snippets/apple-xcode-project-core.md`

### Script Inventory

- `scripts/run_workflow.py`
- `scripts/dash_api_probe.py`
- `scripts/dash_catalog_match.py`
- `scripts/dash_catalog_refresh.py`
- `scripts/dash_url_search.py`
- `scripts/dash_url_install.py`
