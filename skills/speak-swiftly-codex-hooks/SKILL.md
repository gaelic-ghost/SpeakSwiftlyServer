---
name: speak-swiftly-codex-hooks
description: Use when a user wants Speak Swiftly to read Codex replies aloud automatically through Codex lifecycle hooks, including plugin-managed hook setup, hook command path diagnosis, hook doctor interpretation, duplicate-hook diagnosis, centralized hook logs, permission-request payload probes, final-reply TTS troubleshooting, or validation from another working directory.
---

# Speak Swiftly Codex Hooks

Use this skill when the task is about Codex lifecycle hooks that send final assistant replies to the local Speak Swiftly service.

## Start Here

- Read [docs/codex-hooks-tts.md](../../docs/codex-hooks-tts.md) before changing guidance or setup. It is the repo source of truth for the plugin hook, command path behavior, logs, state, and known Codex payload behavior.
- Verify the live service before changing hook config: read `speak-swiftly://overview` or run `node scripts/codex-hooks-doctor.mjs --repair-plan` from the repository root.
- Treat `speak-swiftly@socket` as the preferred plugin entry when both Socket and standalone marketplaces are present.
- Keep the legacy `speak-swiftly-server@socket` config entry disabled unless the user explicitly asks for legacy-plugin investigation.
- For plugin-managed hooks, confirm both `features.codex_hooks = true` and `features.plugin_hooks = true` in `~/.codex/config.toml`; current Codex CLI source gates runnable plugin hooks behind the separate `plugin_hooks` feature.

## Setup Model

- Preferred install surface: the Speak Swiftly plugin manifest declares `hooks: "./hooks/hooks.json"`, and installed plugins can bundle lifecycle config through that manifest.
- Do not copy the repo-local `.codex/hooks.json` into `~/.codex/`; that command sets `CODEX_HOOK_TTS_DATA_DIR` for checkout-scoped development logs and state. Do not add a user-level `~/.codex/hooks.json` Speak Swiftly hook for normal installs.
- Plugin-managed hook commands must target the installed Socket Codex cache payload path at `~/.codex/plugins/cache/socket/speak-swiftly/6.0.0/hooks/...`. Do not keep stale standalone `SpeakSwiftlyServer` cache commands in the Socket-managed manifest.
- Treat `PermissionRequest` as logging-only unless the user explicitly asks to make approval prompts speakable. The probe must not approve, reject, or print text to `stdout`.

## Doctor Interpretation

- Warn on user-level hooks that point at `.codex/hooks/stop-tts.mjs`, include `CODEX_HOOK_TTS_DATA_DIR`, or duplicate the plugin-managed `Stop` hook. Treat them as duplicate or legacy repair targets, not fallback hooks.
- Warn on duplicate enabled plugin entries. Keep the canonical Socket entry and disable or remove duplicate standalone or legacy plugin entries after confirmation.
- Runtime default voice mismatch is not automatically a hook failure. The hook uses `CODEX_HOOK_TTS_PROFILE_NAME` or `default-femme`; confirm the profile exists in the cached voice inventory.

## Validation

- Validate syntax and focused fixtures with `sh scripts/repo-maintenance/validations/25-codex-plugin.sh`.
- Run `node scripts/codex-hooks-doctor.mjs --repair-plan` and inspect both centralized and repo-local recent hook log summaries, including `permission-request.jsonl` when approval-prompt behavior is under investigation.
- To prove all-directory coverage, run a tiny Codex CLI turn from a different working directory and then tail `~/.codex/speak-swiftly-server/hooks/logs/stop-tts.jsonl`.
- Treat a queued log entry with the probe `cwd`, `sessionId`, `turnId`, and `request.request_id` as the proof that the hook fired and the service accepted the speech request.
- If the installed plugin manifest is correct but no `Stop` row appears, check `features.plugin_hooks` before adding any user-level fallback.

## Troubleshooting

- If a direct manual run of the installed plugin's `hooks/stop-tts.mjs` queues speech but normal assistant final replies do not add a fresh row to `~/.codex/speak-swiftly-server/hooks/logs/stop-tts.jsonl`, inspect whether the plugin-managed commands still include stale direct commands for absent cache paths before blaming the live service.
- `speech-route-unreachable` means the hook could not reach the local HTTP route.
- HTTP `503` from `/speech/live` means the service is reachable but not ready for speech work yet.
- `duplicate-turn` means shared dedupe blocked a repeated `session_id + turn_id`; that is expected when more than one matching hook source starts.
- `structured-assistant-metadata` means Codex produced compact UI or automation metadata instead of speakable final prose.
- Permission-request probe entries with `outcome=logged` mean Codex fired the approval hook and the payload was recorded for later inspection.
- If the live service itself is unhealthy, switch to `$speak-swiftly-launchagent-setup` for service setup or `$speak-swiftly-runtime-operator` for runtime readiness, queue, playback, or backend state.
