# Skills Surface Audit

Last audited: 2026-05-03

This note records the repo-local Codex skill surface audit against the current `SpeakSwiftlyServer` package, HTTP API, MCP catalog, plugin metadata, and operator documentation.

## Current Skill Set

The checked-in plugin exposes five focused skills under `skills/`:

- `speak-swiftly-mcp`: orientation and routing for the local `speak_swiftly` MCP server.
- `speak-swiftly-runtime-operator`: runtime, queue, playback, request, backend, and model-residency operations.
- `speak-swiftly-voice-workflows`: voice-profile creation and editing, live speech, retained files, retained batches, and artifact inspection.
- `speak-swiftly-text-profiles`: text-normalization style, stored profile, replacement, and persistence workflows.
- `speak-swiftly-launchagent-setup`: supported LaunchAgent setup, promotion, inspection, uninstall, and healthcheck flow.

The root plugin manifest at `.codex-plugin/plugin.json` points at `./skills/`, `./.mcp.json`, and `./hooks/hooks.json`. The local marketplace entry at `.agents/plugins/marketplace.json` points at the repository root because the root is the plugin root.

## Source-Of-Truth Surfaces Checked

- `Package.swift` confirms this is the SwiftPM source of truth for the `SpeakSwiftlyServer` library, `SpeakSwiftlyServerTool` executable, and test targets.
- `Sources/SpeakSwiftlyServer/MCP/MCPToolCatalog.swift` is the MCP tool catalog source of truth.
- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift` is the MCP resource and resource-template source of truth.
- `Sources/SpeakSwiftlyServer/MCP/MCPPrompts.swift` is the MCP prompt source of truth.
- `Sources/SpeakSwiftlyServer/HTTP/` is the HTTP route source of truth.
- `API.md` is the dense public transport inventory.
- `README.md` is the concise public operator and plugin install entrypoint.

## Alignment Result

The skill set is conceptually aligned with the current project shape. The five-skill split still maps cleanly onto the real product surfaces: broad MCP orientation, LaunchAgent service setup, runtime operation, voice workflows, and text-profile authoring.

The skill-referenced MCP tool names, prompt names, and `speak-swiftly://` resource families are present in the current source catalog. The runtime skill already names the current generation/playback split controls, including `clear_generation_queue`, `cancel_generation`, and `cancel_playback`. The voice skill names the retained generation job, file, and batch inspection tools now exposed by the MCP catalog.

The skills now match the resources-first MCP guidance: use `speak-swiftly://overview`, `speak-swiftly://voices`, `speak-swiftly://text-profiles`, and focused detail resources for read-only inspection, and reserve tools for queueing speech, runtime changes, profile/text-profile mutations, cancellation, clearing, playback control, and compatibility clients that cannot read resources cleanly.

## Drift Fixed In This Pass

- `API.md` did not list the current generation-side HTTP clear/cancel routes even though `HTTPGenerationRoutes.swift` exposes `DELETE /generation/queue` and `DELETE /generation/requests/{request_id}`.
- `API.md` did not list `DELETE /generation/jobs/{job_id}` even though the route backs retained job expiry.
- `API.md` did not list the current MCP `clear_generation_queue`, `cancel_generation`, and `cancel_playback` tools even though the MCP catalog and runtime skill already use them.
- `speak-swiftly-voice-workflows` mentioned explicit text-format fields but did not call out the current `qwen_pre_model_text_chunking` live-speech option from the MCP catalog and API notes.
- The MCP, runtime, voice, and text-profile skills still treated read-only MCP tools as normal first reads. They now point agents at `speak-swiftly://...` resources first and describe read-only tools as compatibility paths.
- The voice workflow skill still described `swift-signal` and `swift-anchor` as planned/reserved names. It now treats them as package-owned built-in defaults.

## Healthy Constraints To Preserve

- Keep `.mcp.json` pointed at the LaunchAgent default service URL, `http://127.0.0.1:7337/mcp`; direct foreground runs default to `7338`, and embedded app-owned sessions default to `7339`.
- Keep skills focused on MCP/operator behavior. Do not turn them into general package-maintenance docs; `AGENTS.md`, `README.md`, `API.md`, and maintainer docs own that broader guidance.
- Keep destructive queue and profile operations behind exact-id or exact-name confirmation guidance.
- Trust the current MCP source files over older prose when a tool, resource, prompt, or request field appears to disagree.

## Next Audit Checklist

When the HTTP or MCP surface changes again, compare:

1. `MCPToolCatalog.swift` tool names against every backticked MCP tool name in `skills/*/SKILL.md`.
2. `MCPResources.swift` resources and templates against every `speak-swiftly://...` URI in `skills/*/SKILL.md`.
3. `MCPPrompts.swift` prompt names against every prompt name in `skills/*/SKILL.md`.
4. `Sources/SpeakSwiftlyServer/HTTP/*.swift` route registrations against the HTTP inventory in `API.md`.
5. `.mcp.json`, `skills/*/agents/openai.yaml`, and README plugin-install wording for service URL and install-flow agreement.
6. `.codex-plugin/plugin.json`, `hooks/hooks.json`, and `scripts/codex-hooks-doctor.mjs` for plugin-managed hook agreement.
