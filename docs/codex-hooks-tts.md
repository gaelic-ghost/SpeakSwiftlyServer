# Codex Hooks TTS Prototype

This worktree includes a small repo-local Codex prototype for speaking final
assistant replies and inspecting Codex notification payloads.

## Files

- `.codex/config.toml`
  Enables `features.codex_hooks = true` for this trusted project and wires a
  `notify` probe command.
- `.codex/hooks.json`
  Registers one `Stop` hook handler.
- `.codex/hooks/stop-tts.mjs`
  Reads the Codex `Stop` payload from `stdin`, skips empty or duplicate turns,
  ignores continuation passes by default, and queues speech through the local
  `SpeakSwiftlyServer` HTTP route at `POST /speech/live`.
- `.codex/hooks/notify-dump.mjs`
  Records whatever Codex passes to the `notify` command so we can inspect the
  real payload shape. The probe captures both the documented JSON argument and
  any unexpected stdin payload so we can compare real behavior across Codex
  surfaces.
- `.codex/logs/stop-tts.jsonl`
  Runtime log for queued, skipped, and failed TTS attempts.
- `.codex/logs/notify-events.jsonl`
  Runtime log for `notify` payload inspection.
- `.codex/state/stop-tts-seen-turns.json`
  Dedupe state keyed by `session_id + turn_id`.

## Environment Overrides

The `Stop` hook script accepts a few optional environment overrides:

- `CODEX_HOOK_TTS_BASE_URL`
  Override the default `http://127.0.0.1:7337`.
- `CODEX_HOOK_TTS_PROFILE_NAME`
  Override the default voice profile name `default-femme`.
- `CODEX_HOOK_TTS_SKIP_CONTINUATIONS`
  Defaults to `true`. Set to `false` if you want continued `Stop` turns read
  aloud too.
- `CODEX_HOOK_TTS_MAX_SEEN_TURNS`
  Controls how many dedupe keys are retained in the local state file.

## Validation Notes

The current prototype was validated with a synthetic `Stop` payload and queued a
live speech request successfully against the local server.

The current `notify` probe was validated with synthetic JSON passed both as the
documented command-line argument and over `stdin`. The current Codex docs say
the notify command receives a single JSON argument, so the probe now logs both
paths in case any Codex surface differs in practice.
