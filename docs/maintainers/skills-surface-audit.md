# Skills Surface Audit

Last audited: 2026-06-24

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

The MCP source catalog is intentionally slim. It keeps `generate_speech` as the core agent-facing tool, keeps prompt authoring surfaces, and keeps a compact read-only resource set for overview, voice-profile list/guidance, text-profile list/guidance, playback state/guidance, and focused request detail.

Voice-profile mutation, text-profile mutation, retained generation, playback controls, runtime controls, cancellation, queue clearing, network-audio selection, generation jobs, and generated artifacts are HTTP-first workflows. Skills should teach agents the HTTP routes for those actions instead of asking the MCP catalog to mirror the REST API.

The public HTTP and MCP guidance now treats request-context metadata as transport-owned by default. Callers can omit `request_context` for ordinary speech calls; they only need to provide it when they know richer source, topic, path, or caller attributes than the server can infer.

## Drift Fixed In This Pass

- Slimmed the MCP tool catalog to `generate_speech` and moved duplicate mutation/control workflows back to HTTP guidance.
- Slimmed MCP resources to high-value agent reads and removed detailed duplicate resources for runtime status/configuration, playback queue, network-audio selection, generation jobs, artifacts, voice detail, and text-profile detail.
- Preserved MCP prompts because they add agent-native authoring value instead of duplicating HTTP.
- Updated `API.md` so it describes MCP as an agent affordance layer, not a full HTTP mirror.

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
