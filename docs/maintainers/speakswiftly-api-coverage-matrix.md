# SpeakSwiftly API Coverage Matrix

## Purpose

This document compares the public `SpeakSwiftly` library surface resolved by this repository's current package dependency against the client-facing surfaces implemented by `SpeakSwiftlyServer`.

It answers three concrete questions:

1. Which public `SpeakSwiftly` capabilities are already exposed here?
2. Which public capabilities are intentionally adapted instead of mirrored exactly?
3. Which transport is the right client contract for each capability: HTTP, MCP, both, or neither?

Current baseline checked against the `SpeakSwiftly 4.0.5` package state resolved by this repository on `2026-04-24`. The root package now follows `SpeakSwiftly` with an up-to-next-major semantic-version requirement starting at `4.0.5`.

## Summary

`SpeakSwiftlyServer` exposes most of the public runtime control plane that makes sense outside Swift code, with the current `SpeakSwiftly 4.0.5` Qwen additions called out below as deliberate follow-up decisions:

- speech generation for live playback, retained file output, and batches
- voice design and voice cloning with explicit `vibe`
- runtime overview, runtime status, backend switching, and model reload or unload controls
- text-normalizer built-in style, state, persistence, and replacement editing
- generation queue, playback queue, playback state, queue clearing, request cancellation, retained request inspection, and retained generation artifacts

The server's normalized backend contract is now:

- published backend identifiers: `qwen3`, `chatterbox_turbo`, `marvis`
- compatibility alias accepted on HTTP and MCP runtime-control input: `qwen3_custom_voice`
- compatibility alias response behavior: always normalized back to `qwen3`

What remains intentionally non-parity:

- host-owned lifecycle such as `liftoff`, runtime startup, and runtime shutdown
- Qwen resident-model startup selection until the server runtime-configuration snapshot grows a typed field for it
- opt-in Qwen pre-model live chunking until HTTP and MCP have an explicit request-field contract for it
- raw `AsyncStream` / `AsyncThrowingStream` values as first-class wire contracts
- line-oriented parser or transport entrypoints such as `accept(line:)`
- exact Swift type shapes where HTTP or MCP need stable snake_case or resource-oriented contracts instead

That means the server is best understood as a transport adapter over the public library, not as a byte-for-byte network mirror of the Swift API.

## Coverage Matrix

| Public `SpeakSwiftly` symbol or capability | Server coverage | HTTP surface | MCP surface | Notes |
| --- | --- | --- | --- | --- |
| `SpeakSwiftly.liftoff(configuration:)` | Indirect | None | None | Server-owned lifecycle concern. Intentionally not client-exposed. |
| `runtime.start()` / `runtime.shutdown()` | Indirect | None | None | Owned by process or embedded-session lifecycle, not by clients. |
| `runtime.statusEvents()` | Adapted | `GET /healthz`, `GET /readyz`, `GET /runtime/host`, `GET /runtime/status`, `GET /requests/{request_id}/events` | `get_runtime_overview`, `get_runtime_status`, live resources and subscriptions | Exposed through host snapshots, retained request history, and typed resource updates instead of raw streams. |
| `runtime.overview()` | Full | `GET /runtime/host` | `get_runtime_overview`, `speak://runtime/overview` | The host now trusts the atomic runtime overview instead of reconstructing queue or playback state locally. |
| `runtime.status()` | Full | `GET /runtime/status` | `get_runtime_status`, `speak://runtime/status` | Returned as runtime status data plus server-owned live backend-transition state so clients can observe queued backend switches without treating persisted configuration as live state. |
| `SpeakSwiftly.Configuration.qwenResidentModel` | Not exposed | None | None | New in `SpeakSwiftly 4.0.5`. The server currently uses the upstream default resident Qwen model because runtime configuration persistence only carries `speech_backend`. Exposing this needs a deliberate runtime-configuration surface update, not just a dependency bump. |
| `runtime.switchSpeechBackend(to:)` | Full | `POST /runtime/backend` | `switch_speech_backend` | Queues an ordered live backend switch and returns an accepted request. Transport-facing input accepts `qwen3`, `chatterbox_turbo`, and `marvis`, and still normalizes legacy `qwen3_custom_voice` input onto `qwen3`. Pending live transition state is observable from runtime overview/status and the retained request resource. |
| `runtime.reloadModels()` / `runtime.unloadModels()` | Full | `POST /runtime/models/reload`, `POST /runtime/models/unload` | `reload_models`, `unload_models` | Immediate runtime-control operations. |
| `runtime.generate.speech(...)` | Partial | `POST /speech/live` | `generate_speech` | Carries `text_profile_id`, `request_context`, `cwd`, `repo_root`, `text_format`, `nested_source_format`, and `source_format`. The new `qwenPreModelTextChunking` flag from `SpeakSwiftly 4.0.5` is not exposed yet; omitted requests keep upstream's single-pass Qwen live-playback default. |
| `runtime.generate.audio(...)` | Full | `POST /speech/files` | `generate_audio_file` | Retains generated file artifacts for later reads. |
| `runtime.generate.batch(_:with:)` | Full | `POST /speech/batches` | `generate_batch` | Uses the same retained-request and generated-batch shaping as the other submission lanes. |
| `runtime.voices.create(design:from:vibe:voice:outputPath:)` | Full | `POST /voices/from-description` | `create_voice_profile_from_description` | Accepted-request flow with retained request inspection. |
| `runtime.voices.create(clone:from:vibe:transcript:)` | Full | `POST /voices/from-audio` | `create_voice_profile_from_audio` | Accepted-request flow with explicit `vibe` and transcript handling. |
| `runtime.voices.list()` | Full | `GET /voices` | `list_voice_profiles`, `speak://voices` | Exposed through cached host profile snapshots. |
| `runtime.voices.rename(_:to:)` | Full | `PUT /voices/{profile_name}/name` | `update_voice_profile_name` | Accepted-request flow that updates cached profile identity after the runtime mutation completes. |
| `runtime.voices.reroll(_)` | Full | `POST /voices/{profile_name}/reroll` | `reroll_voice_profile` | Accepted-request flow that rebuilds one stored profile in place from its persisted source inputs. |
| `runtime.voices.delete(named:)` | Full | `DELETE /voices/{profile_name}` | `delete_voice_profile` | Accepted-request removal flow. |
| `runtime.normalizer.style.getActive()` / `setActive(to:)` | Full | `GET /text-profiles/style`, `PUT /text-profiles/style`, plus `built_in_style` inside `GET /text-profiles` | `get_text_profile_style`, `set_text_profile_style`, `get_text_normalizer_snapshot`, `speak://text-profiles`, `speak://text-profiles/style` | Built-in style is now first-class operator state rather than hidden base-profile configuration. |
| `runtime.normalizer.profiles.getActive()` / `get(id:)` / `list()` / `getEffective()` | Full | `GET /text-profiles`, `GET /text-profiles/base`, `GET /text-profiles/active`, `GET /text-profiles/effective`, `GET /text-profiles/effective/{profile_id}`, `GET /text-profiles/stored/{profile_id}` | `get_text_normalizer_snapshot`, `speak://text-profiles`, `speak://text-profiles/base`, `speak://text-profiles/active`, `speak://text-profiles/effective`, `speak://text-profiles/effective/{profile_id}`, `speak://text-profiles/stored/{profile_id}` | Exposed as synchronous state, not as retained generation jobs. |
| `runtime.normalizer.persistence.load()` / `save()` | Full | `POST /text-profiles/load`, `POST /text-profiles/save` | `load_text_profiles`, `save_text_profiles` | Operator-triggered persistence refresh and flush. |
| `runtime.normalizer.profiles.create` / `rename` / `setActive` / `delete` / `factoryReset` / `reset(id:)` | Full | `POST /text-profiles/stored`, `PUT /text-profiles/stored/{profile_id}/name`, `PUT /text-profiles/active`, `DELETE /text-profiles/stored/{profile_id}`, `POST /text-profiles/factory-reset`, `POST /text-profiles/stored/{profile_id}/reset` | `create_text_profile`, `rename_text_profile`, `set_active_text_profile`, `delete_text_profile`, `factory_reset_text_profiles`, `reset_text_profile` | The server now mirrors the released profile lifecycle directly instead of exposing whole-profile store or use shims. |
| `runtime.normalizer.profiles.addReplacement` / `patchReplacement` / `removeReplacement` | Full | `POST`, `PUT`, and `DELETE` replacement routes under active and stored profile paths | `add_text_replacement`, `replace_text_replacement`, `remove_text_replacement` | Supports both active custom profile mutation and stored profile mutation. |
| `runtime.jobs.generationQueue()` | Full | `GET /generation/queue` | `list_generation_queue` | Exposed directly from runtime-owned queue data. |
| `runtime.jobs.list()` / `job(id:)` / `expire(id:)` | Full | `GET /generation/jobs`, `GET /generation/jobs/{job_id}`, `DELETE` equivalent via expiry route family when present in HTTP flow | `list_generation_jobs`, `get_generation_job`, `expire_generation_job`, `speak://generation/jobs`, `speak://generation/jobs/{job_id}` | Retained generation-job reads and expiry controls now follow the runtime terminology instead of older server-only job wrappers. |
| `runtime.artifacts.files()` / `file(id:)` / `batches()` / `batch(id:)` | Full | `GET /generation/files`, `GET /generation/files/{artifact_id}`, `GET /generation/batches`, `GET /generation/batches/{batch_id}` | `list_generated_files`, `get_generated_file`, `list_generated_batches`, `get_generated_batch`, matching resources | Saved artifact reads are available without dropping back to direct library usage. |
| `runtime.player.list()` | Full | `GET /playback/queue` | `list_playback_queue` | Exposed as the playback queue read model. |
| `runtime.player.state()` | Full | `GET /playback/state` | `get_playback_state` | Used directly for playback state reads and control settling. |
| `runtime.player.pause()` / `resume()` | Full | `POST /playback/pause`, `POST /playback/resume` | `pause_playback`, `resume_playback` | The server now aligns its cached playback snapshot with these accepted control responses. |
| `runtime.player.clearQueue()` | Full | `DELETE /playback/queue` | `clear_playback_queue` | Returns cleared queued-count information rather than forcing clients to infer it. |
| `runtime.player.cancelRequest(_:)` | Full | `DELETE /playback/requests/{request_id}` | `cancel_request` | Cancels one active or queued playback-owned request cleanly. |
| `runtime.request(id:)` / `runtime.updates(for:)` | Adapted | `GET /requests`, `GET /requests/{request_id}`, `GET /requests/{request_id}/events` | `list_active_requests`, `speak://requests`, `speak://requests/{request_id}` | Exposed through retained host request snapshots and event history instead of raw Swift concurrency streams. |
| `accept(line:)` | Not exposed | None | None | Correctly left as an internal line-oriented parser entrypoint. |

## Intentional Adaptations

These are transport-local choices, not missing library support:

- snake_case HTTP fields and MCP argument names instead of Swift method labels
- retained request snapshots and event history instead of exposing raw request-event streams directly
- product-shaped MCP names such as `generate_speech`, `generate_audio_file`, `generate_batch`, `get_staged_runtime_config`, `set_staged_config`, and `get_text_normalizer_snapshot`
- read-oriented MCP resources for runtime, text-profile, request, generation-job, and artifact state

Those adaptations are deliberate because HTTP and MCP consumers need stable, navigable, inspectable contracts more than they need a perfect transcription of Swift declarations.

## Remaining Cleanup Bias

At this point, the remaining surface work should stay focused on clarity rather than parity theater:

1. keep trimming any server-local wrappers that do not add real transport clarity now that the runtime overview, jobs, artifacts, and text-normalizer APIs are all directly available
2. add an explicit server-side decision for `qwenPreModelTextChunking` before exposing it on HTTP and MCP, because it changes live-playback generation shape for Qwen requests while file generation now intentionally stays single-pass upstream
3. decide whether `qwenResidentModel` belongs in the server's persisted runtime configuration snapshot before exposing the new upstream startup choice to operators
4. keep README and maintainer docs synchronized whenever the resolved `SpeakSwiftly` version or MCP surface changes
5. keep the small live E2E smoke suite pointed at the current HTTP and MCP names so release verification proves the actual shipped transport surface
