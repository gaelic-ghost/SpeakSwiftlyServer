# Codex Hooks TTS

SpeakSwiftlyServer ships a Codex lifecycle hook that can speak final assistant
replies through the local `SpeakSwiftlyServer` HTTP surface.

The user-facing install path starts with the plugin-managed payload. A
user-level `~/.codex/hooks.json` entry is also a supported fallback when a
Codex surface has not yet dispatched installed plugin lifecycle config
reliably. The repository-local `.codex/` files are only a development and
testing harness for this checkout.

## User Install Surface

- `.codex-plugin/plugin.json`
  Declares `hooks: "./hooks/hooks.json"` so installed plugin users get the
  lifecycle config from the plugin.
- `hooks/hooks.json`
  Registers the speech `Stop` hook handler and a logging-only
  `PermissionRequest` probe.
- `hooks/stop-tts.mjs`
  Reads the Codex `Stop` payload from `stdin`, skips empty or duplicate turns,
  ignores continuation passes by default, and queues speech through the local
  `SpeakSwiftlyServer` HTTP route at `POST /speech/live`.
- `hooks/permission-request-log.mjs`
  Reads the Codex `PermissionRequest` payload from `stdin` and records a local
  JSONL entry without approving, rejecting, printing, or queueing speech. This
  is an observability probe for learning what approval prompts expose before
  deciding whether they should become speakable events.

The plugin-managed hook stores state and logs under
`~/.codex/speak-swiftly-server/hooks/` by default, or under `CODEX_HOME` when
that environment variable points Codex at a different home directory.
The `Stop` hook writes `logs/stop-tts.jsonl`; the permission-request probe
writes `logs/permission-request.jsonl`.

OpenAI's [Codex hooks documentation](https://developers.openai.com/codex/hooks#where-codex-looks-for-hooks)
lists `~/.codex/hooks.json` as one of the main hook locations and says
installed plugins can bundle lifecycle config through their plugin manifest or
`hooks/hooks.json`. OpenAI's
[plugin packaging documentation](https://developers.openai.com/codex/plugins/build#plugin-structure)
also allows a manifest `hooks` field and a default `./hooks/hooks.json`
lifecycle file. Because Codex runs every matching hook source instead of using
higher-precedence config to replace lower-precedence hooks, Speak Swiftly keeps
dedupe state in the shared hook data directory.

## User-Level Fallback

Use a user-level fallback when a current Codex install recognizes the plugin
but does not dispatch the plugin-bundled `Stop` hook from every working
directory. The fallback should call the tracked source hook script directly and
should not set `CODEX_HOOK_TTS_DATA_DIR`; leaving that variable unset keeps
state and logs centralized under `~/.codex/speak-swiftly-server/hooks/`.

Example shape:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/SpeakSwiftlyServer/hooks/permission-request-log.mjs",
            "timeout": 15
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node /absolute/path/to/SpeakSwiftlyServer/hooks/stop-tts.mjs",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

Do not pair that fallback with the repo-local development harness command that
sets `CODEX_HOOK_TTS_DATA_DIR` to `.codex/`; that splits logs and dedupe state
back into the checkout.

## Development Harness

- `.codex/config.toml`
  Enables `features.codex_hooks = true` for this trusted project and wires a
  `notify` probe command.
- `.codex/hooks.json`
  Registers the same `Stop` hook script and `PermissionRequest` logging probe
  for local testing, with `CODEX_HOOK_TTS_DATA_DIR` pointed at this checkout's
  `.codex/` directory.
- `.codex/hooks/stop-tts.mjs`
  Dev-only forwarding entrypoint for local harness configs that need checkout
  scoped state and logs while testing hook payload behavior.
- `.codex/hooks/notify-dump.mjs`
  Records whatever Codex passes to the `notify` command so maintainers can
  inspect the real payload shape.
- `.codex/logs/stop-tts.jsonl`
  Runtime log for queued, skipped, and failed development-harness TTS attempts.
- `.codex/logs/permission-request.jsonl`
  Runtime log for development-harness permission-request payload inspection.
- `.codex/logs/notify-events.jsonl`
  Runtime log for `notify` payload inspection.
- `.codex/state/stop-tts-seen-turns.json`
  Development-harness dedupe state keyed by `session_id + turn_id`.

Do not tell end users to copy `.codex/hooks.json` or `.codex/config.toml` into
their own Codex home. The supported user-level fallback is a minimal
`~/.codex/hooks.json` entry that calls the source `hooks/stop-tts.mjs` script
without repo-local development-harness environment overrides.

## Environment Overrides

The `Stop` hook script accepts these optional environment overrides:

- `CODEX_HOOK_TTS_BASE_URL`
  Override the default `http://127.0.0.1:7337`.
- `CODEX_HOOK_TTS_PROFILE_NAME`
  Override the default voice profile name `default-femme`.
- `CODEX_HOOK_TTS_DATA_DIR`
  Override the state and log root. The hook creates `state/` and `logs/` under
  this directory.
- `CODEX_HOOK_TTS_SKIP_CONTINUATIONS`
  Defaults to `true`. Set to `false` if continued `Stop` turns should be read
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

## Doctor

Run this from the repository root when hook behavior or voice selection looks
off:

```bash
node scripts/codex-hooks-doctor.mjs
```

The doctor reports:

- repo plugin hook metadata
- repo development-harness hook metadata
- user-level `~/.codex/hooks.json` fallback wiring, when present
- legacy or dev-only global hook entries that split state into `.codex/`
- installed plugin-cache manifests and whether they declare hooks
- `codex_hooks = true` and enabled Speak Swiftly plugin entries such as `speak-swiftly@socket`
- live runtime reachability through `GET /overview`
- runtime default voice profile versus the hook's configured profile
- cached voice profiles
- recent centralized user/plugin and repo-local hook log outcomes
- recent centralized and repo-local permission-request probe outcomes

Warnings are expected if a global hook points at the repo-local development
harness or sets `CODEX_HOOK_TTS_DATA_DIR` to `.codex/`. A user-level hook that
calls `hooks/stop-tts.mjs` directly is a supported fallback, not a migration
failure.

## Runtime Insights

- `Stop` is the right TTS trigger because it carries the final assistant text
  in `last_assistant_message`.
- `PermissionRequest` is currently logging-only. It is useful for discovering
  whether approval prompts expose enough text to speak later, but it should not
  approve, reject, or emit text on `stdout`.
- `notify` is a useful payload probe, but observed Desktop notify commands can
  run with process `cwd` as `/`; use the event's own `cwd` field when
  interpreting where the turn happened.
- Duplicate `Stop` invocations can happen for the same `session_id + turn_id`
  when multiple hook sources match. The hook reserves a turn before posting to
  the speech route so duplicate processes do not queue duplicate audio jobs.
- Some assistant messages are compact JSON metadata used by Codex UI or
  automation flows. Those should be logged and skipped, not spoken aloud.
- The speech route distinguishes a reachable-but-not-ready runtime from an
  unreachable runtime:
  - HTTP `503` with `SpeakSwiftly is not ready yet...` means the server is up
    but not accepting speech work.
  - `speech-route-unreachable` means the hook could not reach the local
    `SpeakSwiftlyServer` route at all.

The hook sends `request_context` with each queued speech request. That keeps
Codex-originated speech inspectable through the existing `SpeakSwiftlyServer`
request model without adding a hook-specific server API. The context includes
the Codex model, permission mode, transcript path, session id, turn id, and
event name when those fields are available.

## Validation Notes

The hook matches the current official Codex hooks payload shape:

- `Stop` receives one JSON object on `stdin`, including `turn_id`,
  `stop_hook_active`, and `last_assistant_message`.
- `Stop` must not emit plain text on `stdout`.
- Commands run with the session `cwd`, so repo-local development hooks resolve
  through `git rev-parse --show-toplevel` and plugin hooks keep their command
  path relative to the plugin lifecycle config.
- `notify` is a top-level Codex configuration command that receives a JSON
  payload from Codex; it is not nested under `[features]`.

Observed current behavior in this repo's live Codex TUI runs:

- the `Stop` hook payload arrives on `stdin`
- the `notify` command currently arrives as one JSON command-line argument
- the current notify runs observed here did not include any `stdin` payload

The `notify` probe still logs both the documented JSON argument and any `stdin`
payload so future Codex surfaces can be compared without rewriting the hook.
