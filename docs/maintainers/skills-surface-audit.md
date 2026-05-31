# Skills Surface Audit

Last audited: 2026-05-12

This note records the repo-local Codex skill surface audit against the current `SpeakSwiftlyServer` package, HTTP API, MCP catalog, plugin metadata, and operator documentation.

## Current Skill Set

The checked-in plugin exposes six focused skills under `skills/`:

- `speak-swiftly-mcp`: orientation and routing for the local `speak_swiftly` MCP server.
- `speak-swiftly-runtime-operator`: runtime, queue, playback, request, backend, and model-residency operations.
- `speak-swiftly-voice-workflows`: voice-profile creation and editing, live speech, retained artifact generation, and artifact inspection.
- `speak-swiftly-text-profiles`: text-normalization style, stored profile, replacement, and persistence workflows.
- `speak-swiftly-launchagent-setup`: supported LaunchAgent setup, promotion, inspection, uninstall, and healthcheck flow.
- `speak-swiftly-codex-hooks`: Codex lifecycle hook setup, duplicate user-level Stop hook repair, doctor interpretation, and final-reply TTS troubleshooting.

The root plugin manifest at `.codex-plugin/plugin.json` points at `./skills/`, `./.mcp.json`, and `./hooks/hooks.json`. The local marketplace entry at `.agents/plugins/marketplace.json` points at the repository root because the root is the plugin root.

## Source-Of-Truth Surfaces Checked

- `Package.swift` confirms this is the SwiftPM source of truth for the `SpeakSwiftlyServer` library, `SpeakSwiftlyServerTool` executable, and test targets.
- `Sources/SSSMCP/MCP/MCPToolCatalog.swift` is the MCP tool catalog source of truth.
- `Sources/SSSMCP/MCP/MCPResources.swift` is the MCP resource and resource-template source of truth.
- `Sources/SSSMCP/MCP/MCPPrompts.swift` is the MCP prompt source of truth.
- `Sources/SSSHTTP/HTTP/` is the HTTP route source of truth.
- `API.md` is the dense public transport inventory.
- `README.md` is the concise public operator and plugin install entrypoint.

## Alignment Result

The skill set is conceptually aligned with the current project shape. The six-skill split still maps cleanly onto the real product surfaces: broad MCP orientation, LaunchAgent service setup, Codex hook setup, runtime operation, voice workflows, and text-profile authoring.

The skill-referenced MCP tool names, prompt names, and `speak-swiftly://` resource families are present in the current source catalog. The runtime skill names the current generation/playback split controls, including `clear_generation_queue`, `clear_playback_queue`, and scoped `cancel_request`. The voice skill names the retained generation jobs and artifact resources now exposed by the MCP catalog.

The skills now match the resources-only MCP read guidance: use `speak-swiftly://overview`, `speak-swiftly://voices`, `speak-swiftly://text-profiles`, and focused detail resources for read-only inspection, and reserve tools for queueing speech, runtime changes, profile/text-profile mutations, cancellation, clearing, and playback control.

The public HTTP and MCP guidance now treats request-context metadata as transport-owned by default. Callers can omit `request_context` for ordinary speech calls; they only need to provide it when they know richer source, topic, path, or caller attributes than the server can infer.

## Drift Fixed In This Pass

- The skills now use the `speak-swiftly://...` MCP resource scheme, scoped `cancel_request`, `set_runtime_configuration`, and retained generation-job/artifact wording after the next-major API cleanup.
- `API.md` did not list the current generation-side HTTP clear route even though `HTTPGenerationRoutes.swift` exposes `DELETE /generation/queue`.
- `API.md` did not list `DELETE /generation/jobs/{job_id}` even though the route backs retained job expiry.
- `API.md` did not list the current MCP `clear_generation_queue`, `clear_playback_queue`, and scoped `cancel_request` tools even though the MCP catalog and runtime skill already use them.
- `speak-swiftly-voice-workflows` mentioned explicit text-format fields but did not call out the current `qwen_pre_model_text_chunking` live-speech option from the MCP catalog and API notes.
- The MCP, runtime, voice, and text-profile skills still treated read-only MCP tools as normal first reads. The current clean-break MCP surface removes those read tools where resources exist and points agents at `speak-swiftly://...` resources instead.
- The voice workflow skill still described `swift-signal` and `swift-anchor` as planned/reserved names. It now treats them as package-owned built-in defaults.
- Added `speak-swiftly-codex-hooks` so plugin-managed hooks, duplicate user-level Stop hook repair, centralized hook logs, and doctor interpretation have a dedicated skill instead of living only in maintainer prose.
- Added default HTTP/MCP request-context provenance to the docs and skill surfaces so future TTS and TextForSpeech behavior can rely on the same origin metadata.

## Healthy Constraints To Preserve

- Keep `.mcp.json` pointed at the LaunchAgent default service URL, `http://127.0.0.1:7337/mcp`; the shared Application Support config is LaunchAgent-oriented, while in-memory fallback profiles still reserve `7338` for ad hoc standalone configs and `7339` for embedded app-owned configs.
- Keep skills focused on MCP/operator behavior. Do not turn them into general package-maintenance docs; `AGENTS.md`, `README.md`, `API.md`, and maintainer docs own that broader guidance.
- Keep destructive queue and profile operations behind exact-id or exact-name confirmation guidance.
- Trust the current MCP source files over older prose when a tool, resource, prompt, or request field appears to disagree.

## Next Audit Checklist

When the HTTP or MCP surface changes again, compare:

1. `MCPToolCatalog.swift` tool names against every backticked MCP tool name in `skills/*/SKILL.md`.
2. `MCPResources.swift` resources and templates against every `speak-swiftly://...` URI in `skills/*/SKILL.md`.
3. `MCPPrompts.swift` prompt names against every prompt name in `skills/*/SKILL.md`.
4. `Sources/SSSHTTP/HTTP/*.swift` route registrations against the HTTP inventory in `API.md`.
5. `.mcp.json`, `skills/*/agents/openai.yaml`, and README plugin-install wording for service URL and install-flow agreement.
6. `.codex-plugin/plugin.json`, `hooks/hooks.json`, `scripts/codex-hooks-doctor.mjs`, and `skills/speak-swiftly-codex-hooks/SKILL.md` for plugin-managed hook and duplicate user-level hook repair agreement.
