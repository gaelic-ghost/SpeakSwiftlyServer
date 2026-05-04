# API

## Table of Contents

- [Overview](#overview)
- [Configuration Notes](#configuration-notes)
- [HTTP Surface](#http-surface)
- [MCP Surface](#mcp-surface)
- [Transport Status Notes](#transport-status-notes)

## Overview

This document is the dense transport reference for `SpeakSwiftlyServer`. Keep the operator-facing summary in [README.md](README.md) concise and move detailed contract inventory here instead.

The server exposes one shared localhost host process with:

- an HTTP surface
- an optional MCP surface
- shared retained request, artifact, playback, and runtime snapshots behind both transports

Maintainer planning for reducing duplicate public surface area lives in
[`docs/maintainers/public-api-simplification-plan.md`](docs/maintainers/public-api-simplification-plan.md).
Keep this API reference focused on the current contract, not future cleanup proposals.

When the same host is embedded through `EmbeddedServerSession`, the transport process now runs
inside one outer service-owned lifecycle group that also owns package-level host startup,
config-watch lifetime, and optional MCP readiness and drain. The HTTP and MCP contracts described
below are unchanged by that embedding model, but the ownership story is now flatter and more
explicit for app hosts and maintainers.

## Configuration Notes

When `APP_CONFIG_FILE` is set, the server watches that YAML file through `ReloadingFileProvider<YAMLSnapshot>`. The optional `APP_CONFIG_RELOAD_INTERVAL_SECONDS` environment variable controls the polling interval and defaults to `2` seconds.

Only the host-safe subset reloads live today:

- `app.name`
- `app.environment`
- `app.sseHeartbeatSeconds`
- `app.completedJobTTLSeconds`
- `app.completedJobMaxCount`
- `app.jobPruneIntervalSeconds`

Changes to bind addresses, ports, HTTP enablement, MCP enablement, MCP path, or MCP server metadata are detected and reported, but they still require a process restart before they can take effect.

`SPEAKSWIFTLY_PROFILE_ROOT` is also a startup-only setting. On the `SpeakSwiftlyServer` side, it still refers to the server-owned profile-store root. During startup, the server bridges that value into the broader persistence root expected by the current pinned `SpeakSwiftly` runtime so the launched runtime can derive `profiles/`, `configuration.json`, and `text-profiles.json` consistently. Because that setting changes filesystem ownership rather than hot runtime state, it is intentionally not part of the live-reloaded YAML surface.

Runtime model selection is startup-only as well. Persisted runtime configuration and the matching HTTP/MCP surfaces use `speech_backend`, `qwen_resident_model`, and `marvis_resident_policy`. `SPEAKSWIFTLY_SPEECH_BACKEND` and `SPEAKSWIFTLY_QWEN_RESIDENT_MODEL` override the persisted next-start values while building the explicit `SpeakSwiftly.Configuration` passed into runtime startup.

## HTTP Surface

### Health And Runtime Endpoints

- `GET /healthz`
- `GET /readyz`
- `GET /overview`
- `GET /status`
- `GET /configuration`
- `PUT /configuration`
- `POST /backend`
- `POST /models/reload`
- `POST /models/unload`

### Voice Endpoints

- `GET /voices`
- `POST /voices/from-description`
- `POST /voices/from-audio`
- `POST /voices/{profile_name}/reroll`
- `PUT /voices/{profile_name}/name`
- `DELETE /voices/{profile_name}`

When the runtime first becomes ready, `SpeakSwiftlyServer` installs any missing bundled default voice
seeds into the active profile store before exposing the refreshed profile cache. `GET /voices`
therefore includes `swift-signal` and `swift-anchor` on a fresh store, or their `-builtin` fallback
names when a user-owned profile already occupies a preferred seed name. Those profiles are
system-authored built-ins: ordinary users should list them and select one as the default or per-request
voice, not edit their seed inputs. Encoded profile JSON exposes only narrow authorship metadata for
system profiles (`author`, `seed_id`, and `seed_version`) and redacts the built-in source text and
voice-design prompt from ordinary read surfaces.

### Text Profile Endpoints

- `GET /text-profiles`
- `GET /text-profiles/style`
- `GET /text-profiles/base`
- `GET /text-profiles/active`
- `GET /text-profiles/effective`
- `GET /text-profiles/effective/{profile_id}`
- `GET /text-profiles/stored/{profile_id}`
- `POST /text-profiles/stored`
- `POST /text-profiles/load`
- `POST /text-profiles/save`
- `POST /text-profiles/factory-reset`
- `POST /text-profiles/stored/{profile_id}/reset`
- `POST /text-profiles/replacements`
- `PUT /text-profiles/stored/{profile_id}/name`
- `PUT /text-profiles/style`
- `PUT /text-profiles/active`
- `PUT /text-profiles/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}`
- `DELETE /text-profiles/replacements/{replacement_id}`

`POST /text-profiles/replacements`
and `PUT /text-profiles/replacements/{replacement_id}` mutate the active custom profile when the
JSON body omits `profile_id`, or mutate a stored profile when the body includes `profile_id`.
`DELETE /text-profiles/replacements/{replacement_id}` follows the same target model with optional
`?profile_id=...` for stored-profile deletion.

### Speech, Request, And Artifact Endpoints

- `POST /speech/live`
- `POST /speech/files`
- `POST /speech/batches`
- `GET /requests`
- `GET /requests/{request_id}`
- `GET /requests/{request_id}/events`
- `DELETE /requests/{request_id}`
- `GET /generation/queue`
- `DELETE /generation/queue`
- `GET /generation/jobs`
- `GET /generation/jobs/{job_id}`
- `DELETE /generation/jobs/{job_id}`
- `GET /generation/artifacts`
- `GET /generation/artifacts/{artifact_id}`

### Playback Endpoints

- `GET /playback/state`
- `GET /playback/queue`
- `POST /playback/pause`
- `POST /playback/resume`
- `DELETE /playback/queue`

### Accepted Request Semantics

`POST /speech/live`, `POST /speech/files`, `POST /speech/batches`, `POST /voices/from-description`, `POST /voices/from-audio`, `PUT /voices/{profile_name}/name`, `POST /voices/{profile_name}/reroll`, and `DELETE /voices/{profile_name}` all return accepted-request metadata immediately.

Those responses use `request_id`, `request_url`, and `events_url` so ordinary HTTP clients can follow one tracked request cleanly without having to learn the MCP resource model first.

`POST /speech/live` mirrors the current public live-speech queue lane and accepts optional `cwd`, `repo_root`, `text_profile_id`, `text_format`, `nested_source_format`, `source_format`, and `qwen_pre_model_text_chunking` fields so callers can pass path-aware, normalization-aware, and Qwen live-chunking context explicitly. `qwen_pre_model_text_chunking` is an opt-in boolean for Qwen live playback only; omitted requests keep SpeakSwiftly's default single-pass Qwen live path.

`POST /speech/files` and `POST /speech/batches` use the same request-tracking shape for retained artifact generation. Clients should follow the returned request URL while generation is active, then read `GET /generation/artifacts`, `GET /generation/artifacts/{artifact_id}`, `GET /generation/jobs`, or `GET /generation/jobs/{job_id}` for retained media records and their originating jobs.

### Text Profile Semantics

The `/text-profiles` route family is synchronous and state-oriented rather than request-oriented. It exposes the current built-in style plus base, active, stored, and effective `TextForSpeech.Profile` state, along with replacement editing and profile persistence paths for downstream apps or agents that need to shape normalization deliberately.

`GET /text-profiles/style` and `PUT /text-profiles/style` mirror the built-in normalization-style control that now participates in effective normalization alongside custom profiles.

`POST /text-profiles/load` and `POST /text-profiles/save` map directly to the public text-profile persistence calls so operators can refresh or flush stored normalization state without reaching into the runtime process manually.

### Playback And Runtime Control Semantics

The queue and playback control routes are immediate control operations rather than long-running requests.

- `GET /generation/queue` and `GET /playback/queue` expose the generation and playback queues separately so the HTTP layer matches the runtime's split control surface.
- `DELETE /generation/queue` clears queued generation work and returns the number of cancelled queued requests.
- `DELETE /requests/{request_id}` cancels one active or queued request wherever it currently lives and returns the cancelled request ID. Add `?scope=generation` or `?scope=playback` only when the caller deliberately wants to constrain cancellation to one queue.
- `GET /playback/state`, `POST /playback/pause`, and `POST /playback/resume` expose the current playback state and let clients control it directly.
- `DELETE /playback/queue` clears queued playback work and returns the number of cancelled queued requests.

The runtime routes are also state-oriented.

- `GET /overview` returns the shared-host overview with readiness, queues, transports, cached profiles, recent errors, and any live backend-switch transition.
- `GET /status` returns the underlying `SpeakSwiftly.StatusEvent` plus the same live backend-switch transition summary.
- `GET /configuration` and `PUT /configuration` expose saved next-start runtime configuration. This is startup intent, not a live transition feed. The current transport fields are `speech_backend`, `qwen_resident_model`, and `marvis_resident_policy`; `speech_backend` can also be switched live through `POST /backend`, while the Qwen resident model and Marvis resident policy apply on the next runtime start.
- `POST /backend` accepts an ordered backend-switch request and returns `202 Accepted` with the retained request URL and event URL. While the runtime waits for active work to settle, clients should read `GET /overview`, `GET /status`, or the returned request resource to observe the requested backend, current active backend, request ID, and waiting reason.
- `POST /models/reload` and `POST /models/unload` follow the current runtime-control verbs directly.

The current HTTP SSE route remains intentionally job-specific at the route boundary, but it now rides the same host-owned event backbone used by other non-UI consumers instead of keeping a separate per-job subscriber registry inside `ServerHost`.

## MCP Surface

The MCP surface is optional and mounts on the same shared Hummingbird process at `APP_MCP_PATH` when `APP_MCP_ENABLED=true`.

### MCP Tools

For read-only MCP inspection, prefer resources first. Use `speak-swiftly://overview` for broad orientation, then read the most specific `speak-swiftly://...` resource for the state you need. The read-only tools remain available for compatibility and clients that cannot use MCP resources cleanly, but tools are the preferred path for queueing speech, changing runtime state, editing profiles, and cancelling or clearing work.

The MCP resource URI scheme is `speak-swiftly://`. Runtime state resources are intentionally top-level under that scheme: `speak-swiftly://overview`, `speak-swiftly://status`, and `speak-swiftly://configuration`. The older `speak://runtime/...` shape is not carried forward in the next major API because it made read routes look nested by implementation detail instead of by user job.

#### Speech And Artifact Tools

- `generate_speech`
- `generate_audio_file`
- `generate_batch`
- `list_active_requests`
- `list_generation_jobs`
- `get_generation_job`
- `expire_generation_job`

#### Voice Tools

- `create_voice_profile_from_description`
- `create_voice_profile_from_audio`
- `inspect_builtin_voice_seed`
- `update_voice_profile_name`
- `reroll_voice_profile`
- `list_voice_profiles`
- `delete_voice_profile`

#### Text Profile Tools

- `get_text_normalizer_snapshot`
- `get_text_profile_style`
- `set_text_profile_style`
- `load_text_profiles`
- `save_text_profiles`
- `create_text_profile`
- `rename_text_profile`
- `set_active_text_profile`
- `delete_text_profile`
- `factory_reset_text_profiles`
- `reset_text_profile`
- `add_text_replacement`
- `replace_text_replacement`
- `remove_text_replacement`

#### Playback And Runtime Tools

- `get_runtime_overview`
- `get_runtime_status`
- `get_runtime_configuration`
- `set_runtime_configuration`
- `switch_speech_backend`
- `reload_models`
- `unload_models`
- `list_generation_queue`
- `list_playback_queue`
- `pause_playback`
- `resume_playback`
- `get_playback_state`
- `clear_generation_queue`
- `clear_playback_queue`
- `cancel_request`

`cancel_request` accepts required `request_id` and optional `scope` (`generation` or `playback`). Omit `scope` for the primary general cancel path. `generate_speech` accepts `qwen_pre_model_text_chunking` as an opt-in boolean for Qwen live playback. `set_runtime_configuration` changes persisted next-start runtime choices with `speech_backend`, optional `qwen_resident_model`, and optional `marvis_resident_policy`. `switch_speech_backend` queues live runtime work and returns an accepted request payload; read `speak-swiftly://overview`, `speak-swiftly://status`, or `speak-swiftly://requests/{request_id}` to observe the pending and active backend state.

### MCP Resources

#### Runtime Resources

- `speak-swiftly://overview`
- `speak-swiftly://status`
- `speak-swiftly://configuration`

#### Voice Resources

- `speak-swiftly://voices`
- `speak-swiftly://voices/guide`
- `speak-swiftly://voices/{profile_name}`

#### Text Profile Resources

- `speak-swiftly://text-profiles`
- `speak-swiftly://text-profiles/style`
- `speak-swiftly://text-profiles/base`
- `speak-swiftly://text-profiles/active`
- `speak-swiftly://text-profiles/effective`
- `speak-swiftly://text-profiles/effective/{profile_id}`
- `speak-swiftly://text-profiles/stored/{profile_id}`
- `speak-swiftly://text-profiles/guide`

#### Request, Artifact, And Playback Resources

- `speak-swiftly://requests`
- `speak-swiftly://requests/{request_id}`
- `speak-swiftly://generation/jobs`
- `speak-swiftly://generation/jobs/{job_id}`
- `speak-swiftly://generation/artifacts`
- `speak-swiftly://generation/artifacts/{artifact_id}`
- `speak-swiftly://playback/guide`

Those MCP tools and resources are intentionally thin adapters over the same `ServerHost` snapshots and mutations used by the HTTP API and the app-facing `ServerState`. Resources are the canonical MCP read surface; generated artifact reads are resources-only in the next major surface so clients do not have two names for the same retained media records.

`inspect_builtin_voice_seed` is a maintainer/development tool for package-owned built-in voice seed
inspection. Normal agent and user workflows should read `speak-swiftly://voices`, choose a profile name, and
use `generate_speech` or the default-voice configuration path instead of inspecting seed prompts.

Accepted-request MCP tool results return `request_id`, `request_resource_uri`, and `status_resource_uri` so coding agents can follow one tracked request immediately while still having an obvious top-level status resource for orientation.

### MCP Prompts

The embedded MCP prompt catalog currently includes:

- `draft_profile_voice_description`
- `draft_profile_source_text`
- `draft_voice_design_instruction`
- `draft_queue_playback_notice`
- `draft_text_profile`
- `draft_text_replacement`
- `choose_surface_action`

The text-profile prompts and the `speak-swiftly://text-profiles/guide` resource are there so an app-hosted or MCP-hosted agent can help a user author replacements deliberately instead of treating normalization rules like hidden implementation detail.

### MCP Resource Subscriptions

The embedded MCP surface supports resource subscriptions for the live state resources and templates backed by shared host updates. Playback resource freshness is currently host-event-driven; the upstream `SpeakSwiftly` follow-up for runtime-level playback event streams will let this become more direct once it lands.

Clients connected to the standalone MCP event stream can subscribe to:

- `speak-swiftly://overview`
- `speak-swiftly://status`
- `speak-swiftly://configuration`
- `speak-swiftly://voices`
- `speak-swiftly://voices/{profile_name}`
- `speak-swiftly://requests`
- `speak-swiftly://requests/{request_id}`
- `speak-swiftly://generation/jobs`
- `speak-swiftly://generation/jobs/{job_id}`
- `speak-swiftly://generation/artifacts`
- `speak-swiftly://generation/artifacts/{artifact_id}`
- `speak-swiftly://text-profiles`
- `speak-swiftly://text-profiles/style`
- `speak-swiftly://text-profiles/base`
- `speak-swiftly://text-profiles/active`
- `speak-swiftly://text-profiles/effective`
- `speak-swiftly://text-profiles/effective/{profile_id}`
- `speak-swiftly://text-profiles/stored/{profile_id}`

Subscribed clients receive `notifications/resources/updated` when shared host events change the underlying state.

## Transport Status Notes

Transport lifecycle snapshots are intentionally tied to the shared Hummingbird process rather than static config alone. `listening` means the shared HTTP host has actually reached Hummingbird's `onServerRunning` boundary, so HTTP and MCP surface status describe real network availability instead of only configuration intent.
