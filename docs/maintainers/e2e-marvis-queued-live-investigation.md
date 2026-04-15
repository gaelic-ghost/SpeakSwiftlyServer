# E2E Investigation: Queued Marvis Live Playback Stall

## Context

- Date observed: `2026-04-08`
- Historical full-suite command: `SPEAKSWIFTLYSERVER_E2E=1 swift test --filter ServerE2E`
- Current equivalent focused reruns:
  - `SPEAKSWIFTLYSERVER_E2E=1 swift test --filter HTTPWorkflowE2ETests`
  - `SPEAKSWIFTLYSERVER_E2E=1 swift test --filter MCPWorkflowE2ETests`
  - `SPEAKSWIFTLYSERVER_E2E=1 swift test --filter ControlE2ETests`
- Active failing lane: `httpMarvisQueuedLivePlaybackDrainsInOrder`
- Resolution status: fixed on `2026-04-09` after the `SpeakSwiftly 2.2.1` adoption, playback-control snapshot realignment, and the varied-text operator-control cleanup pass.

## Confirmed Runtime State

- The live E2E-owned server was running on `http://127.0.0.1:59123`.
- The process environment confirmed:
  - `APP_MCP_ENABLED=false`
  - `SPEAKSWIFTLY_SPEECH_BACKEND=marvis`
- Those settings narrow the stuck run to the HTTP queued-Marvis lane now housed in `Tests/SpeakSwiftlyServerE2ETests/E2EQueuedMarvisLane.swift`.

## Confirmed Failure Signals

### 1. The first queued-live request never reached a terminal event

The first live request remained active in playback and never completed:

- request id: `70A26ACF-D15D-4F48-9CAD-5B7C27AA2438`
- profile: `http-marvis-queued-femme-profile`
- snapshot endpoint: `GET /requests/70A26ACF-D15D-4F48-9CAD-5B7C27AA2438`

Observed request history:

- `acknowledged`
- `started`
- `progress.loading_profile`
- `progress.starting_playback`
- `progress.buffering_audio`
- `progress.preroll_ready`

The request never emitted:

- `progress.playback_finished`
- a terminal success event
- a terminal failure event

That leaves the E2E helper blocked in `waitForTerminalJob(id:using:timeout:server:)` while the request snapshot still reports `status: "running"`.

### 2. Generation advanced while playback still held the first request open

While playback still reported the first request as active, the runtime host overview reported:

- playback queue active request:
  - `70A26ACF-D15D-4F48-9CAD-5B7C27AA2438`
- playback queue queued count:
  - `2`
- generation queue active request:
  - `333B6133-888F-4A48-A2FA-D3471A06F555`
- generation queue queued count:
  - `0`

The later queued requests had both advanced past queueing:

- second request:
  - `4D96E961-F15E-4D73-9A83-94EBDD2EA711`
  - queued at position `1`
  - later observed at `progress.starting_playback`
- third request:
  - `333B6133-888F-4A48-A2FA-D3471A06F555`
  - profile: `http-marvis-queued-androgenous-profile`
  - queued at position `2`
  - later observed at `progress.starting_playback`

At the time of inspection, all three retained request snapshots were still `running`:

- `70A26ACF-D15D-4F48-9CAD-5B7C27AA2438` at `progress.preroll_ready`
- `4D96E961-F15E-4D73-9A83-94EBDD2EA711` at `progress.starting_playback`
- `333B6133-888F-4A48-A2FA-D3471A06F555` at `progress.starting_playback`

This means the queued-live Marvis path allowed later work to start while the first playback-owned request never drained.

## Current Interpretation

There are two plausible explanations that still need to be separated:

1. The primary bug is playback completion.
   The first queued-live request never emits `playback_finished` or a terminal event, so the playback queue never drains.

2. The secondary bug is queue/lifecycle mismatch.
   Generation-side work may be allowed to advance independently of playback completion, which may be correct internally but still leaves the server-side retained request lifecycle inconsistent with the E2E expectation that a queued-live request becomes terminal after playback finishes.

## Source-Level Findings

The current `SpeakSwiftly` `2.0.0` runtime semantics narrow the likely fault domain further:

- Live speech generation is intentionally non-terminal when generation ends.
  In `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Runtime/WorkerRuntime.swift`, the `.queueSpeech(... jobType: .live ...)` path calls `handleQueueSpeechLiveGeneration(...)` and then records `GenerationCompletionDisposition.requestStillPendingPlayback(id)`.
- Live speech only becomes terminal through playback completion.
  In `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Playback/PlaybackOperations.swift`, `completePlaybackJob(_:result:)` reconstructs the live `queueSpeech` request and calls `completeRequest(...)`, which is what should eventually deliver the terminal `.completed` event that `SpeakSwiftlyServer` records.
- `preroll_ready` is only a mid-flight playback progress event.
  In `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Playback/PlaybackOperations.swift`, `.prerollReady(...)` maps to `progress.preroll_ready` plus the `playback_started` log event, but not terminal completion.
- Final success still depends on playback drain.
  In `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Playback/PlaybackController.swift`, the live playback path calls `waitForPlaybackDrain(...)` after generation finishes. That drain wait only completes when queued audio reaches zero, or fails with `audioPlaybackTimeout` if the local audio player stops reporting drain progress.
- The server is not adding an extra terminality rule here.
  In `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`, retained request snapshots only become terminal when the runtime request stream emits a `.completed` or `.failed` event.

## Important Runtime Asymmetry

One upstream runtime rule explains part of the confusing queued state without fully explaining the stall:

- Live speech does require playback ownership.
  In `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Runtime/WorkerProtocol.swift`, `requiresPlayback` is `true` for `.queueSpeech(... jobType: .live ...)`.
- But live speech does not require playback drain before later generation starts.
  In that same file, `requiresPlaybackDrainBeforeStart` is only `true` for `switchSpeechBackend`, `reloadModels`, and `unloadModels`, not for live speech.

That means the runtime is explicitly allowed to start generation for later queued live requests while an earlier live request is still active in playback. The focused rerun showed exactly that behavior. By itself, that concurrency is not necessarily a bug. The bug is that the earlier playback-owned request still failed to emit `playback_finished` and terminal completion.

## Upstream Test Expectation

This repository's E2E expectation still matches upstream `SpeakSwiftly` tests:

- `.build/checkouts/SpeakSwiftly/Tests/SpeakSwiftlyTests/Runtime/WorkerRuntimePlaybackTests.swift`
  `speakLiveBackgroundAcknowledgesQueueBeforePlaybackStartsAndOnlySucceedsOnce()`
  proves a queued live request should eventually emit `playback_finished` and then a single terminal success.
- `.build/checkouts/SpeakSwiftly/Tests/SpeakSwiftlyTests/E2E/MarvisWorkflowE2ETests.swift`
  `marvisAudibleLivePlaybackPrequeuesThreeJobsAndDrainsInOrder()`
  expects all three queued Marvis live requests to complete audibly in order.

So the server-side E2E lane is not asserting a novel contract here. It is exposing a case where the local live server integration does not reach the terminal behavior that upstream v2 still expects.

## Focused Lane Rerun

A later focused rerun of only `httpMarvisQueuedLivePlaybackDrainsInOrder` produced a stronger signal:

- first request:
  - `53A3932B-0F18-435D-B449-F684B57712A0`
  - reached `progress.playback_finished`
  - reached a terminal success event
- second request:
  - `D68325FD-D4B8-4EE6-93F5-812CF48B4944`
  - advanced through `progress.preroll_ready`
  - remained `running`
- third request:
  - `60B73D71-3996-4C94-8BE5-4A319DF03D0B`
  - started after the first request completed
  - advanced to `progress.starting_playback` while the second request was still only at `preroll_ready`

That focused rerun shifts the problem statement:

- the failure is not strictly "the first queued-live request always stalls"
- the stronger invariant break is that a later queued-live request can begin advancing while an earlier playback-owned request is still non-terminal
- once that happens, the earlier request can remain parked at `preroll_ready` indefinitely

## Likely Next Checks

1. Capture one more focused stalled run and confirm whether the stuck request ever emits a raw runtime `.completed` event or a `playback_finished` stderr log event before the server snapshot stalls.
2. Trace why `waitForPlaybackDrain(...)` is not resuming or timing out for the stuck Marvis request even though a later queued-live request has already advanced.
3. If the runtime stream does emit terminal completion but the server snapshot stays `running`, narrow the fault to `ServerHost.consume(handle:)`; otherwise, treat this as an upstream `SpeakSwiftly` Marvis playback-drain bug and patch or report it there first.

## Pending Upstream Alignment

- Gale is actively simplifying and streamlining the upstream `SpeakSwiftly` surface to remove more server-side inference.
- Once those upstream changes land, re-check this server before adding more local queue or playback heuristics.
- Prefer deleting host inference and fallback shaping where the upstream runtime can expose the same truth directly in a clearer, typed form.
- Treat upstream simplification as the preferred path for any remaining queue-state, playback-state, or multi-lane generation ambiguity in this repository.

## Follow-Up Progress: 2026-04-09

### Cleanup checkpoint landed

- Commit `d46a320` reduced extra MCP-side churn while live speech is in flight:
  - host-backed queue and playback read surfaces now use the shared host snapshot instead of issuing extra runtime queue and playback requests on every HTTP or MCP read
  - queued request details now survive through host snapshots instead of flattening to only counts
  - the MCP subscription broker now starts consuming host events only after the first actual resource subscription instead of eagerly on every session
- Those changes removed obvious local read-path pressure, but they did not eliminate the live-stall shape.

### Focused MCP operator-control rerun still stalls in the first live request

- Focused command:
  - `SPEAKSWIFTLYSERVER_E2E=1 SPEAKSWIFTLY_PLAYBACK_TRACE=1 swift test --filter mcpOperatorControlSurfaceCoversPlaybackAndQueueMutationsWithoutCatalogSubscriptions`
- The focused rerun reached the same stuck shape after pause, resume, cancel, and queue-clear control calls had already succeeded.
- Observed server state while stalled:
  - active request:
    - `FB9AA7DB-7060-44FA-8191-DD4352681A56`
  - playback:
    - `state: playing`
    - `active_request.id: FB9AA7DB-7060-44FA-8191-DD4352681A56`
    - `is_stable_for_concurrent_generation: true`
    - `is_rebuffering: false`
    - `stable_buffered_audio_ms: 13120`
    - `stable_buffer_target_ms: 13120`
  - generation queue:
    - one active request
    - zero queued requests
  - current generation jobs:
    - latest stage: `preroll_ready`
- Retained request history for the active request still stopped at:
  - `started`
  - `progress.loading_profile`
  - `progress.starting_playback`
  - `progress.buffering_audio`
  - `progress.preroll_ready`
- No `progress.playback_finished` or terminal success event arrived.

### Sample evidence from the stalled MCP operator-control lane

- Sample file:
  - `/tmp/SpeakSwiftlyServerTool_mcp_operator_trace.sample.txt`
- The hot stack was inside `Qwen3TTSModel.generateStream(...)` and MLX eval work, not parked in the MCP transport or server event loop.
- That means the process was still burning real generation work while the retained request snapshot remained stuck at `preroll_ready`.

### Important side finding: the operator-control test payload itself was bad

- The operator-control E2E had been building its long live request by repeating the exact same playback sentence 12 times.
- That matches the audible symptom Gale heard during local runs and was poor diagnostic input because it bakes obvious repetition into the generated speech.
- The test input has now been switched to a single longer varied passage instead of a repeated sentence block.

### Stale HTTP route expectations were still present in the operator-control E2E

- After updating that payload, the HTTP operator-control lane exposed a separate stale-surface regression in the test itself:
  - the test was still calling the old `DELETE /queue/{request_id}` and `DELETE /queue` routes
  - the server had already been realigned to `DELETE /playback/requests/{request_id}` and `DELETE /playback/queue`
- Those stale test calls are now updated to the current HTTP surface names.

### Current read

- The historical stall was real enough to deserve investigation, but the release-repair pass closed it without adding new server-side inference or compatibility shims.
- The final fix set combined the `SpeakSwiftly 2.2.1` resource-bundling update, playback-control snapshot settling in `ServerHost`, renamed HTTP/MCP surface cleanup in the live tests, and less misleading long-form operator-control text.
- The full serialized live suite now passes again, so this document should be treated as historical forensics rather than an active blocker log.

## Watch Item: 2026-04-10 Live Runtime Warning

- The `v2.0.2` live-service refresh exposed a separate LaunchAgent reinstall race that has since been fixed in `SpeakSwiftlyServer` commit `fa6e5ce`.
- That reinstall race was a launchd lifecycle issue, not evidence of a bad plist or broken staged artifact.
- Keep watching the live runtime separately for the recurring allocator warning seen in `~/Library/Logs/SpeakSwiftlyServer/stderr.log`:
  - `freed pointer was not the last allocation`
- That warning did not fail the full live E2E suite, but earlier launchd history also showed pre-fix `SIGABRT` churn, so it should stay on the maintainer watch list until a later release cycle either explains it upstream or proves it benign under repeated live use.
