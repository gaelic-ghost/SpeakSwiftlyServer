# Apple Swift Docs Automation Contract

## Purpose

Provide one consistent automation contract for Apple and Swift docs exploration and subordinate Dash follow-up modes.

## Inputs

- `mode`
- `query`
- `docs_kind`
- `preferred_source`
- `docset_request`
- `max_results`
- `search_snippets`
- `report_path`

## Constraints

- Use Xcode MCP docs first when they are available and the user has not asked for another source.
- Do not perform Dash install actions inside an `explore` automation run.
- Do not perform Dash install actions without explicit approval.
- Keep Dash-specific follow-up subordinate to the main Apple and Swift docs workflow.

## Status Values

- `success`
- `blocked`
- `handoff`

## Output

- `status`
- `path_type`
- `mode`
- `source_used` or `source_path`
- concise result summary
- one next step when follow-up is needed

## Codex App Prompt Template

```text
Use $explore-apple-swift-docs.

Run docs mode `<MODE>` with:
- Query or request: <QUERY>
- Docs kind: <DOCS_KIND>
- Preferred source: <PREFERRED_SOURCE>
- Docset request: <DOCSET_REQUEST>
- Max results: <MAX_RESULTS>
- Search snippets: <SEARCH_SNIPPETS>
- Report path: <REPORT_PATH>

Execution order:
1) Classify the request into one mode: `explore`, `dash-install`, or `dash-generate`.
2) If no mode is explicit, start with `explore`.
3) Use the mode's documented primary path.
4) Use the documented fallback order only if the primary source is unavailable.
5) When the next action belongs to the next mode, return a `handoff` output instead of mixing workflows.

Behavior:
- If `<MODE>` is `explore`, prefer `xcode-mcp-docs -> dash -> official-web`.
- If `<MODE>` is `dash-install`, follow `built-in -> user-contributed -> cheatsheet`.
- If `<MODE>` is `dash-generate`, use stable automation guidance first and manual guidance only as fallback.
- Write a short report to `<REPORT_PATH>` only when that path is provided.
- Keep the response aligned to the documented `status`, `path_type`, and `output` contract.
```

## Codex CLI Prompt Template

```text
Use $explore-apple-swift-docs for a non-interactive CLI run.

Task:
1) Run docs mode `<MODE>`.
2) Use `<QUERY>` or `<DOCSET_REQUEST>` as the mode input.
3) Follow the mode's documented primary path and fallback order.
4) Produce a machine-readable summary and optional markdown report at `<REPORT_PATH>`.

Constraints:
- Keep the run scoped to the requested mode.
- Use `handoff` instead of crossing into another primary workflow.
- Keep recommendations deterministic and concise.

Return contract:
- `status: success|blocked|handoff`
- `path_type: <primary|fallback>`
- `mode: <MODE>`
- `source_used_or_source_path: <value>`
- `next_step: <text>`
```

## Customization Knobs

- `<MODE>`: `explore`, `dash-install`, or `dash-generate`
- `<QUERY>`: Apple or Swift search phrase
- `<DOCS_KIND>`: `api-reference`, `guide`, `symbol`, or `search`
- `<PREFERRED_SOURCE>`: `auto`, `xcode-mcp-docs`, `dash`, or `official-web`
- `<DOCSET_REQUEST>`: Dash follow-up request for install or generation guidance
- `<MAX_RESULTS>`: Integer limit for `explore`
- `<SEARCH_SNIPPETS>`: `true` or `false` for `explore`
- `<REPORT_PATH>`: Optional report destination path

## Guardrails and Stop Conditions

- Stop with `blocked` if the selected mode has no usable primary path or fallback path.
- Do not invent docset identifiers or catalog matches.
- Do not cross from `explore` into `dash-install` or from `dash-install` into `dash-generate` without returning `status: handoff`.
