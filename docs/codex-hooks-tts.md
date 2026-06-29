# Codex Hooks TTS

SpeakSwiftlyServer ships a Codex lifecycle hook that can speak final assistant
replies through the local `SpeakSwiftlyServer` HTTP surface.

The user-facing install path starts with the plugin-managed payload. The
repository-local `.codex/` files are only a development and testing harness for
this checkout.

## User Install Surface

- `.codex-plugin/plugin.json`
  Declares `hooks: "./hooks/hooks.json"` so installed plugin users get the
  lifecycle config from the plugin.
- `hooks/hooks.json`
  Registers the speech `Stop` hook handler.
- `hooks/stop-tts.mjs`
  Reads the Codex `Stop` payload from `stdin`, skips empty or duplicate turns,
  ignores continuation passes by default, optionally projects sectioned final
  replies into a shorter spoken form, and queues speech through the local
  `SpeakSwiftlyServer` HTTP route at `POST /speech/live`.

The plugin-managed hook commands use Codex cache payload paths instead of
assuming `./hooks/...` is relative to the session working directory. Codex
loads `hooks/hooks.json` from the plugin root, but hook commands themselves run
with the session `cwd`.

Socket marketplace command set:

```json
{
  "Stop": "node ~/.codex/plugins/cache/socket/speak-swiftly/11.1.2/hooks/stop-tts.mjs"
}
```

Do not register stale standalone `SpeakSwiftlyServer` cache commands in the
Socket-managed manifest. The Socket install path is the supported command path.

Normal installs must not add a user-level `~/.codex/hooks.json` Speak Swiftly
hook; if one is present, treat it as a duplicate or legacy repair target rather
than a fallback.

The plugin-managed hook stores state and logs under
`~/.codex/speak-swiftly-server/hooks/` by default, or under `CODEX_HOME` when
that environment variable points Codex at a different home directory.
The `Stop` hook writes `logs/stop-tts.jsonl`.

Current Codex builds gate runnable plugin-bundled hooks behind both lifecycle
hooks and plugin hooks feature flags. For plugin-managed TTS, confirm the user
configuration includes:

```toml
[features]
hooks = true
plugin_hooks = true
```

Codex 0.129.0 also stores per-hook review decisions in `~/.codex/config.toml`
under `[hooks.state]`. The keys identify the hook source, event, matcher-group
index, and command index, and each reviewed command gets a `trusted_hash`.
For the Socket-managed Speak Swiftly plugin, the expected review keys are:

```toml
[hooks.state."speak-swiftly@socket:hooks/hooks.json:stop:0:0"]
trusted_hash = "sha256:..."
```

If Codex says hooks need review, use the Codex hooks settings panel to review
the plugin-managed Speak Swiftly `Stop` hook. Do not add a user-level
`~/.codex/hooks.json` fallback to bypass review; review is per hook command and
lives beside the active Codex configuration.

OpenAI's [Codex hooks documentation](https://developers.openai.com/codex/hooks#where-codex-looks-for-hooks)
lists `~/.codex/hooks.json` as one of the main hook locations and says
installed plugins can bundle lifecycle config through their plugin manifest or
`hooks/hooks.json`. OpenAI's
[plugin packaging documentation](https://developers.openai.com/codex/plugins/build#plugin-structure)
also allows a manifest `hooks` field and a default `./hooks/hooks.json`
lifecycle file. Because Codex runs every matching hook source instead of using
higher-precedence config to replace lower-precedence hooks, Speak Swiftly keeps
dedupe state in the shared hook data directory.

## Development Harness

- `.codex/config.toml`
  Enables `features.hooks = true` for this trusted project and wires a
  `notify` probe command.
- `.codex/hooks.json`
  Registers the same `Stop` hook script for local testing, with
  `CODEX_HOOK_TTS_DATA_DIR` pointed at this checkout's `.codex/` directory.
  The development `Stop` hook is logging-only so this trusted checkout can
  inspect payloads without queueing duplicate speech through the live service.
- `.codex/hooks/stop-tts.mjs`
  Dev-only forwarding entrypoint for local harness configs that need checkout
  scoped state and logs while testing hook payload behavior.
- `hooks/stop-log.mjs`
  Logging-only `Stop` probe used by the repo-local `.codex/hooks.json`
  development harness. It records Stop payload summaries under
  `.codex/logs/stop-log.jsonl` and never calls `POST /speech/live`.
- `.codex/hooks/notify-dump.mjs`
  Records whatever Codex passes to the `notify` command so maintainers can
  inspect the real payload shape.
- `.codex/logs/stop-tts.jsonl`
  Runtime log for queued, skipped, and failed development-harness TTS attempts.
  This file is historical for the current repo-local harness because the
  checked-in development `Stop` hook no longer queues speech.
- `.codex/logs/stop-log.jsonl`
  Runtime log for repo-local development-harness `Stop` payload inspection.
- `.codex/logs/notify-events.jsonl`
  Runtime log for `notify` payload inspection.
- `.codex/state/stop-tts-seen-turns.json`
  Development-harness dedupe state keyed by `session_id + turn_id`.

Do not tell end users to copy `.codex/hooks.json` or `.codex/config.toml` into
their own Codex home.

## Environment Overrides

The hook scripts share these optional environment overrides:

- `CODEX_HOOK_TTS_DATA_DIR`
  Override the state and log root. Hook scripts create their needed `state/`
  and `logs/` paths under this directory.
- `CODEX_HOOK_TTS_LOG_FULL_PAYLOAD`
  Defaults to `false`. Set to `true` only during focused debugging when the log
  needs the full raw Codex hook payload and parsed payload.

The `Stop` hook script also accepts:

- `CODEX_HOOK_TTS_BASE_URL`
  Override the default `http://127.0.0.1:7337`.
- `CODEX_HOOK_TTS_PROFILE_NAME`
  Force a specific voice profile for hook speech. When unset, the hook omits
  `profile_name` and lets the running SpeakSwiftlyServer runtime default choose
  the voice.
- `CODEX_HOOK_TTS_SKIP_CONTINUATIONS`
  Defaults to `true`. Set to `false` if continued `Stop` turns should be read
  aloud too.
- `CODEX_HOOK_TTS_SKIP_STRUCTURED_MESSAGES`
  Defaults to `true`. Skips compact structured assistant payloads such as
  `{"title":"..."}`, `{"suggestions":[...]}`, and `{"exclude":[...]}` because
  those are UI or automation metadata rather than speakable final prose.
- `CODEX_HOOK_TTS_SKIP_SECTIONS`
  Comma-separated list of final-reply sections to omit from spoken playback.
  Defaults to `Evidence,Details`. The hook recognizes top-level `Answer`,
  `Meaning`, `Evidence`, `Details`, and `Risk` headings written as Markdown
  headings, bold headings, or plain heading lines. For example,
  `Evidence,Details` keeps those sections in the written reply while omitting
  their bodies from the text sent to `POST /speech/live`.
- `CODEX_HOOK_TTS_SECTION_NOTICE`
  Controls how skipped section presence is announced in speech. Supported
  values are `brief`, `verbose`, and `none`; invalid values fall back to
  `brief`. The default `brief` mode says which configured sections were
  present but skipped.
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
- per-hook Codex review trust state from `[hooks.state]` in
  `~/.codex/config.toml`
- user-level `~/.codex/hooks.json` Speak Swiftly hook wiring, when present, as
  duplicate or legacy state to repair
- legacy or dev-only global hook entries that split state into `.codex/`
- installed plugin-cache manifests and whether they declare hooks
- `hooks = true` and enabled Speak Swiftly plugin entries such as `speak-swiftly@socket`
- `plugin_hooks = true`, which is required by current Codex builds before
  installed plugin lifecycle hooks become runnable
- live runtime reachability through `GET /overview`
- runtime default voice profile and any hook voice-profile override
- cached voice profiles
- recent centralized user/plugin and repo-local hook log outcomes

Warnings are expected if a user-level hook points at the repo-local development
harness, sets `CODEX_HOOK_TTS_DATA_DIR` to `.codex/`, or duplicates the
plugin-managed `Stop` hook. A missing user-level `Stop` hook is the healthy
state when the installed plugin-managed hook is the intended live speech path.

Warnings about missing hook review state mean Codex has discovered the hook but
has not recorded a trusted command hash for that hook source. Open the Codex
hooks settings panel and approve the expected Speak Swiftly hook commands.

## Runtime Insights

- `Stop` is the right TTS trigger because it carries the final assistant text
  in `last_assistant_message`.
- `notify` is a useful payload probe, but observed Desktop notify commands can
  run with process `cwd` as `/`; use the event's own `cwd` field when
  interpreting where the turn happened.
- Duplicate `Stop` invocations can happen for the same `session_id + turn_id`
  when multiple hook sources match. The hook reserves a turn before posting to
  the speech route so duplicate processes do not queue duplicate audio jobs.
- In this repository, duplicate `Stop` invocations are especially easy to see
  if a user-level hook duplicates the installed plugin hook while the repo-local
  `.codex/hooks.json` development harness is also active. Ordinary users should
  use only the plugin-managed hook. The repo-local `.codex/hooks.json` entry is
  for checkout-scoped hook development and now uses `hooks/stop-log.mjs` so it
  writes Stop payload summaries under `.codex/` without calling the live speech
  route.
- Some assistant messages are compact JSON metadata used by Codex UI or
  automation flows. Those should be logged and skipped, not spoken aloud.
- Section projection happens before the speech request is submitted. Hook logs
  include the known sections found in the written reply, which sections were
  spoken, and which configured sections were skipped.
- The speech route distinguishes a reachable-but-not-ready runtime from an
  unreachable runtime:
  - HTTP `503` with `SpeakSwiftly is not ready yet...` means the server is up
    but not accepting speech work.
  - `speech-route-unreachable` means the hook could not reach the local
    `SpeakSwiftlyServer` route at all.

The hook sends `request_context` with each queued speech request. That keeps
Codex-originated speech inspectable through the existing `SpeakSwiftlyServer`
request model without adding a hook-specific server API. Ordinary project
turns use source `Codex Hook` and a topic derived from the working directory.
Codex document chat workspaces whose second-to-last working-directory component
is `Codex`, or whose working directory is under `Documents/Codex`, use source
`Codex` and topic `Chat`. The context includes the Codex model, permission
mode, transcript path, session id, turn id, and event name when those fields
are available.

## Validation Notes

The hook matches the current official Codex hooks payload shape:

- `Stop` receives one JSON object on `stdin`, including `turn_id`,
  `stop_hook_active`, and `last_assistant_message`.
- `Stop` must not emit plain text on `stdout`.
- Commands run with the session `cwd`, so plugin-managed hook commands must not
  rely on `./hooks/...` resolving relative to the plugin root.
- `notify` is a top-level Codex configuration command that receives a JSON
  payload from Codex; it is not nested under `[features]`.

Observed current behavior in this repo's live Codex TUI runs:

- the `Stop` hook payload arrives on `stdin`
- the `notify` command currently arrives as one JSON command-line argument
- the current notify runs observed here did not include any `stdin` payload

The `notify` probe still logs both the documented JSON argument and any `stdin`
payload so future Codex surfaces can be compared without rewriting the hook.
