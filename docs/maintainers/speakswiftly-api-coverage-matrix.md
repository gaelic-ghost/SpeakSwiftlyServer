# SpeakSwiftly API Coverage Matrix

## Purpose

This document compares the public `SpeakSwiftly` library surface resolved by this repository's current package dependency against the client-facing surfaces implemented by `SpeakSwiftlyServer`.

It answers three concrete questions:

1. Which public `SpeakSwiftly` capabilities are already exposed here?
2. Which public capabilities are intentionally adapted instead of mirrored exactly?
3. Which transport is the right client contract for each capability: HTTP, MCP, both, or neither?

Current baseline checked against the `SpeakSwiftly` package state resolved by this repository on `2026-05-31`: prerelease `v11.0.0-alpha.1`.

## Summary

`SpeakSwiftlyServer` exposes most of the public runtime control plane that makes sense outside Swift code, with the current aligned `SpeakSwiftly` observation surface called out below as deliberate transport shaping:

- speech generation for live playback, retained file output, and batches
- voice design and voice cloning with explicit `vibe`
- host overview, runtime snapshots, backend switching, and model reload or unload controls
- text-normalizer built-in style, state, persistence, and replacement editing
- generation snapshots, playback snapshots, queue clearing, request cancellation, retained request inspection, and retained generation artifacts

The server's normalized backend contract is now:

- published backend identifiers: `qwen3_smol`, `qwen3_smol_4bit`, `qwen3_smol_5bit`, `qwen3_smol_6bit`, `qwen3_smol_8bit`, `qwen3_smol_bf16`, `qwen3_big`, `qwen3_big_4bit`, `qwen3_big_5bit`, `qwen3_big_6bit`, `qwen3_big_8bit`, `qwen3_big_bf16`
- opt-in Qwen live request chunking field: `qwen_pre_model_text_chunking`

What remains intentionally non-parity:

- host-owned lifecycle such as `liftoff`, runtime startup, and runtime shutdown
- raw `AsyncStream` / `AsyncThrowingStream` values as first-class wire contracts
- line-oriented parser or transport entrypoints such as `accept(line:)`
- exact Swift type shapes where HTTP or MCP need stable snake_case or resource-oriented contracts instead

That means the server is best understood as a transport adapter over the public library, not as a byte-for-byte network mirror of the Swift API.

## Coverage Matrix

| Public `SpeakSwiftly` symbol or capability | Server coverage | HTTP surface | MCP surface | Notes |
| --- | --- | --- | --- | --- |
| `SpeakSwiftly.liftoff(configuration:)` | Indirect | None | None | Server-owned lifecycle concern. Intentionally not client-exposed. |
| `runtime.start()` / `runtime.shutdown()` | Indirect | None | None | Owned by process or embedded-session lifecycle, not by clients. |
| `runtime.updates()` | Adapted | `GET /healthz`, `GET /readyz`, `GET /overview`, `GET /status`, `GET /requests/{request_id}/events` | slim live resources and subscriptions | Exposed through host snapshots, retained request history, and typed resource updates instead of raw streams. |
| `runtime.snapshot()` / `runtime.generate.snapshot()` / `runtime.playback.snapshot()` | Full | `GET /overview` | `speak-swiftly://overview` | The host refreshes the three runtime-owned snapshots together instead of reconstructing queue or playback state through older request-style reads. |
| `runtime.playback.updates()` | Adapted | `GET /playback/state`, `GET /requests/{request_id}/events` | `speak-swiftly://playback`, playback resource subscriptions | The host subscribes to sequenced playback updates, stores the latest stable playback milestone in shared playback state, and mirrors request-specific playback milestones into retained request progress events. |
| `runtime.snapshot()` | Full | `GET /status` | None | Returned as direct runtime snapshot fields plus server-owned live backend-transition state so clients can observe queued backend switches without treating persisted configuration as live state. |
| `SpeakSwiftly.Configuration.speechBackend` values | Full | `GET /configuration`, `PUT /configuration` with `speech_backend` | None | Startup-only configuration. Exact Qwen variants are selected through published `SpeechBackend` raw values; separate resident-model policy knobs are no longer exposed. |
| `runtime.switchSpeechBackend(to:)` | Full | `POST /backend` | None | Queues an ordered live backend switch and returns an accepted request. Transport-facing input accepts all published `SpeakSwiftly.SpeechBackend` raw values. Pending live transition state is observable from runtime overview/status and the retained request resource. |
| `runtime.reloadModels()` / `runtime.unloadModels()` | Full | `POST /models/reload`, `POST /models/unload` | None | Immediate runtime-control operations. |
| `runtime.generate.speech(...)` | Full | `POST /speech/live` | `generate_speech` | Carries `text_profile_id`, `request_context`, `cwd`, `repo_root`, `qwen_pre_model_text_chunking`, and `generation_location`. HTTP and MCP speech surfaces apply request purpose from the route or tool, then fill transport-owned request-context defaults; MCP also folds session `clientInfo` into provenance when available. Caller-provided request context can override source/topic/path/attributes and optional preface policy, but not request purpose. The Qwen chunking flag is opt-in and defaults to `false`, matching upstream's single-pass Qwen live-playback default when omitted. `generation_location` defaults to local generation; remote generation locations call another server's authenticated `POST /speech/stream` and route the returned canonical chunks to local playback or the selected LAN receiver. Source-format hints are no longer a speech-submission field; SpeakSwiftly's package-owned normalizer infers structure from request text and path context. |
| `runtime.generate.audioStream(...)` | Full | `POST /speech/stream` | Indirect through `generate_speech` remote generation locations | Server-to-server generated-audio stream boundary gated by `app.remoteGeneration.allowRemoteStreamRequests` and `X-SpeakSwiftly-Remote-Generation-Token`. The response body is newline-delimited JSON, one `SpeakSwiftly.HTTPGeneratedAudioFrame` per generated chunk, so remote callers can decode chunk metadata, payload bytes, and final markers without making the runtime own remote sessions. |
| `runtime.generate.audio(...)` | Full | `POST /speech/files` | None | Retains generated audio artifacts for later reads. |
| `runtime.generate.batch(_:with:)` | Full | `POST /speech/batches` | None | Uses the same retained-request and generation-job shaping as the other submission lanes. |
| `runtime.voices.create(design:from:vibe:voice:outputPath:)` | Full | `POST /voices/from-description` | None | Accepted-request flow with retained request inspection. |
| `runtime.voices.create(clone:from:vibe:transcript:)` | Full | `POST /voices/from-audio` | None | Accepted-request flow with explicit `vibe` and transcript handling. |
| `runtime.voices.list()` | Full | `GET /voices` | `speak-swiftly://voices` | Exposed through cached host profile snapshots. |
| `runtime.voices.rename(_:to:)` | Full | `PUT /voices/{profile_name}/name` | None | Accepted-request flow that updates cached profile identity after the runtime mutation completes. |
| `runtime.voices.reroll(_)` | Full | `POST /voices/{profile_name}/reroll` | None | Accepted-request flow that rebuilds one stored profile in place from its persisted source inputs. |
| `runtime.voices.delete(named:)` | Full | `DELETE /voices/{profile_name}` | None | Accepted-request removal flow. |
| `runtime.normalizer.style.getActive()` / `setActive(to:)` | Full | `GET /text-profiles/style`, `PUT /text-profiles/style`, plus `built_in_style` inside `GET /text-profiles` | `speak-swiftly://text-profiles` | Built-in style is now first-class operator state rather than hidden base-profile configuration. |
| `runtime.normalizer.profiles.getActive()` / `get(id:)` / `list()` / `getEffective()` | Full | `GET /text-profiles`, `GET /text-profiles/base`, `GET /text-profiles/active`, `GET /text-profiles/effective`, `GET /text-profiles/effective/{profile_id}`, `GET /text-profiles/stored/{profile_id}` | `speak-swiftly://text-profiles` | Exposed as synchronous state, not as retained generation jobs. |
| `runtime.normalizer.persistence.load()` / `save()` | Full | `POST /text-profiles/load`, `POST /text-profiles/save` | None | Operator-triggered persistence refresh and flush. |
| `runtime.normalizer.profiles.create` / `rename` / `setActive` / `delete` / `factoryReset` / `reset(id:)` | Full | `POST /text-profiles/stored`, `PUT /text-profiles/stored/{profile_id}/name`, `PUT /text-profiles/active`, `DELETE /text-profiles/stored/{profile_id}`, `POST /text-profiles/factory-reset`, `POST /text-profiles/stored/{profile_id}/reset` | None | The server now mirrors the released profile lifecycle directly instead of exposing whole-profile store or use shims. |
| `runtime.normalizer.profiles.addReplacement` / `patchReplacement` / `removeReplacement` | Full | `POST`, `PUT`, and `DELETE` replacement routes under active and stored profile paths | None | Supports both active custom profile mutation and stored profile mutation. |
| `runtime.generate.snapshot()` | Full | `GET /generation/queue` | `speak-swiftly://overview` | Exposed directly from runtime-owned generation queue data. |
| `runtime.jobs.list()` / `job(id:)` / `expire(id:)` | Full | `GET /generation/jobs`, `GET /generation/jobs/{job_id}`, `DELETE` equivalent via expiry route family when present in HTTP flow | None | Retained generation-job reads and expiry are HTTP-first workflows. |
| `runtime.artifacts()` / `artifact(id:)` | Full | `GET /generation/artifacts`, `GET /generation/artifacts/{artifact_id}` | None | Saved artifact reads use one retained artifact family; batch membership is read through generation jobs instead of a separate batch read family. |
| `runtime.playback.snapshot()` | Full | `GET /playback/queue`, `GET /playback/state` | `speak-swiftly://overview`, `speak-swiftly://playback` | Exposed as both the playback queue read model and the playback state read/control-settling source. |
| `runtime.playback.pause()` / `resume()` | Full | `POST /playback/pause`, `POST /playback/resume` | None | The server now aligns its cached playback snapshot with these accepted control responses. |
| `runtime.playback.clearQueue()` | Full | `DELETE /playback/queue` | None | Returns cleared queued-count information rather than forcing clients to infer it. |
| `runtime.cancelRequest(_:)` / queue-scoped cancellation | Full | `DELETE /requests/{request_id}` with optional `?scope=generation\|playback` | None | Cancels one active or queued request by id, with scope only when the caller deliberately needs queue-specific protection. |
| `runtime.request(id:)` / `runtime.updates(for:)` | Adapted | `GET /requests`, `GET /requests/{request_id}`, `GET /requests/{request_id}/events` | `speak-swiftly://requests/{request_id}` | Exposed through retained host request snapshots and event history instead of raw Swift concurrency streams. |
| `accept(line:)` | Not exposed | None | None | Correctly left as an internal line-oriented parser entrypoint. |

## Intentional Adaptations

These are transport-local choices, not missing library support:

- snake_case HTTP fields and MCP argument names instead of Swift method labels
- retained request snapshots and event history instead of exposing raw request-event streams directly
- the product-shaped MCP `generate_speech` tool for the core agent action
- read-oriented MCP resources for overview, voice-profile list/guidance, text-profile list/guidance, playback state/guidance, and focused request detail

Those adaptations are deliberate because HTTP and MCP consumers need stable, navigable, inspectable contracts more than they need a perfect transcription of Swift declarations.

## Remaining Cleanup Bias

At this point, the remaining surface work should stay focused on clarity rather than parity theater:

1. keep trimming any server-local wrappers that do not add real transport clarity now that runtime snapshots, jobs, artifacts, runtime configuration, and text-normalizer APIs are all directly available
2. keep README and maintainer docs synchronized whenever the resolved `SpeakSwiftly` version or MCP surface changes
3. keep the small live E2E smoke suite pointed at the current HTTP and MCP names so release verification proves the actual shipped transport surface
