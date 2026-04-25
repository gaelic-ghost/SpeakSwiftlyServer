# Codex Hooks TTS Prototype

This worktree includes a small repo-local Codex hooks prototype for speaking
final assistant replies and inspecting Codex notification payloads.

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
  The hook now reserves a turn before posting to the speech route, under a
  small local state lock, so concurrent duplicate `Stop` invocations for the
  same `session_id + turn_id` do not queue duplicate audio jobs.
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

Both hook scripts now resolve their `.codex` state and log directories from the
script location itself instead of from `process.cwd()`. That matches the
official Codex hooks guidance to keep repo-local hook paths stable even when
Codex is started from a subdirectory.

## Environment Overrides

The `Stop` hook script accepts a few optional environment overrides:

- `CODEX_HOOK_TTS_BASE_URL`
  Override the default `http://127.0.0.1:7337`.
- `CODEX_HOOK_TTS_PROFILE_NAME`
  Override the default voice profile name `default-femme`.
- `CODEX_HOOK_TTS_SKIP_CONTINUATIONS`
  Defaults to `true`. Set to `false` if you want continued `Stop` turns read
  aloud too.
- `CODEX_HOOK_TTS_SKIP_STRUCTURED_MESSAGES`
  Defaults to `true`. Skips compact structured assistant payloads such as
  `{"title":"..."}`, `{"suggestions":[...]}`, and `{"exclude":[...]}` because
  those are UI or automation metadata rather than speakable final prose.
- `CODEX_HOOK_TTS_LOG_FULL_PAYLOAD`
  Defaults to `false`. Set to `true` only during focused debugging when the log
  needs the full raw Codex hook payload and parsed payload.
- `CODEX_HOOK_TTS_MAX_SEEN_TURNS`
  Controls how many dedupe keys are retained in the local state file.
- `CODEX_HOOK_TTS_STATE_LOCK_TIMEOUT_MS`
  Defaults to `3000`. Controls how long a hook process waits for the local
  dedupe-state lock before logging an unexpected hook failure.
- `CODEX_HOOK_TTS_STATE_LOCK_POLL_MS`
  Defaults to `50`. Controls how frequently a waiting hook process retries the
  local dedupe-state lock.

## Runtime Insights

The ignored logs under `.codex/logs/` have turned out to be useful as a small
operator observability surface:

- `Stop` is the right TTS trigger because it carries the final assistant text
  in `last_assistant_message`.
- `notify` is a good payload probe, but the observed Desktop process often runs
  the notify command with process `cwd` as `/`; use the event's own `cwd` field
  when interpreting where the turn happened.
- Duplicate `Stop` invocations can happen for the same `session_id + turn_id`,
  so state reservation must happen before the hook posts speech.
- Some assistant messages are compact JSON metadata used by Codex UI or
  automation flows. Those should be logged and skipped, not spoken aloud.
- The speech route can distinguish a reachable-but-not-ready runtime from an
  unreachable runtime:
  - HTTP `503` with `SpeakSwiftly is not ready yet...` means the server is up
    but not accepting speech work.
  - `speech-route-unreachable` means the hook could not reach the local
    `SpeakSwiftlyServer` route at all.

The hook also sends `request_context` with each queued speech request. That
keeps Codex-originated speech inspectable through the existing
`SpeakSwiftlyServer` request model without adding a hook-specific server API.
The context includes the Codex model, permission mode, transcript path, session
id, turn id, and event name when those fields are available.

## Product Ideas From The Logs

The current hook logs suggest a few reusable surfaces for this repo and sibling
products:

- A small queue inspector could group speech requests by `request_context`
  source, project, model, and turn id so Codex-, app-, browser-, and editor-
  originated speech are easy to tell apart.
- A readiness widget could expose the difference between “server reachable but
  not ready” and “route unreachable,” which is more actionable than a single
  failed/success state.
- A future Codex or editor integration should treat structured assistant
  metadata as UI state, not spoken text.
- `notify` payloads are a promising source for client identity and input-turn
  summaries, while `Stop` remains the safer source for speakable final replies.

## Validation Notes

The current prototype was rechecked against the current official Codex hooks
documentation:

- `Stop` receives one JSON object on `stdin`, including `turn_id`,
  `stop_hook_active`, and `last_assistant_message`.
- `Stop` must not emit plain text on `stdout`.
- repo-local hooks should resolve from the git root or another stable path, not
  by assuming the session `cwd` is the repository root.
- `notify` is a top-level Codex configuration command that receives a JSON
  payload from Codex; it is not nested under `[features]`.

The `Stop` hook script matches that current payload shape and was validated with
a synthetic `Stop` payload plus real runtime requests queued through the local
server.

Observed current behavior in this repo's live Codex TUI runs:

- the `Stop` hook payload arrives on `stdin`
- the `notify` command currently arrives as one JSON command-line argument
- the current notify runs observed here did not include any `stdin` payload

The `notify` probe still logs both the documented JSON argument and any `stdin`
payload so future Codex surfaces can be compared without rewriting the hook.
