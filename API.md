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

## HTTP Surface

### Health And Runtime Endpoints

- `GET /healthz`
- `GET /readyz`
- `GET /runtime/host`
- `GET /runtime/status`
- `GET /runtime/configuration`
- `POST /runtime/backend`
- `POST /runtime/models/reload`
- `POST /runtime/models/unload`
- `PUT /runtime/configuration`

### Voice Endpoints

- `GET /voices`
- `POST /voices/from-description`
- `POST /voices/from-audio`
- `POST /voices/{profile_name}/reroll`
- `PUT /voices/{profile_name}/name`
- `DELETE /voices/{profile_name}`

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
- `POST /text-profiles/active/replacements`
- `POST /text-profiles/stored/{profile_id}/replacements`
- `PUT /text-profiles/stored/{profile_id}/name`
- `PUT /text-profiles/style`
- `PUT /text-profiles/active`
- `PUT /text-profiles/active/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}`
- `DELETE /text-profiles/active/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}/replacements/{replacement_id}`

### Speech, Request, And Artifact Endpoints

- `POST /speech/live`
- `POST /speech/files`
- `POST /speech/batches`
- `GET /requests`
- `GET /requests/{request_id}`
- `GET /requests/{request_id}/events`
- `GET /generation/queue`
- `GET /generation/jobs`
- `GET /generation/jobs/{job_id}`
- `GET /generation/files`
- `GET /generation/files/{artifact_id}`
- `GET /generation/batches`
- `GET /generation/batches/{batch_id}`

### Playback Endpoints

- `GET /playback/state`
- `GET /playback/queue`
- `POST /playback/pause`
- `POST /playback/resume`
- `DELETE /playback/queue`
- `DELETE /playback/requests/{request_id}`

### Accepted Request Semantics

`POST /speech/live`, `POST /voices/from-description`, `POST /voices/from-audio`, `PUT /voices/{profile_name}/name`, `POST /voices/{profile_name}/reroll`, and `DELETE /voices/{profile_name}` all return accepted-request metadata immediately.

Those responses use `request_id`, `request_url`, and `events_url` so ordinary HTTP clients can follow one tracked request cleanly without having to learn the MCP resource model first.

`POST /speech/live` mirrors the current public live-speech queue lane and accepts optional `cwd`, `repo_root`, `text_profile_id`, `text_format`, `nested_source_format`, and `source_format` fields so callers can pass path-aware and normalization-aware context explicitly.

### Text Profile Semantics

The `/text-profiles` route family is synchronous and state-oriented rather than request-oriented. It exposes the current built-in style plus base, active, stored, and effective `TextForSpeech.Profile` state, along with replacement editing and profile persistence paths for downstream apps or agents that need to shape normalization deliberately.

`GET /text-profiles/style` and `PUT /text-profiles/style` mirror the built-in normalization-style control that now participates in effective normalization alongside custom profiles.

`POST /text-profiles/load` and `POST /text-profiles/save` map directly to the public text-profile persistence calls so operators can refresh or flush stored normalization state without reaching into the runtime process manually.

### Playback And Runtime Control Semantics

The queue and playback control routes are immediate control operations rather than long-running requests.

- `GET /generation/queue` and `GET /playback/queue` expose the generation and playback queues separately so the HTTP layer matches the runtime's split control surface.
- `GET /playback/state`, `POST /playback/pause`, and `POST /playback/resume` expose the current playback state and let clients control it directly.
- `DELETE /playback/queue` clears queued playback work and returns the number of cancelled queued requests.
- `DELETE /playback/requests/{request_id}` cancels one active or queued request and returns the cancelled request ID.

The runtime routes are also state-oriented.

- `GET /runtime/host` returns the shared-host overview with readiness, queues, transports, cached profiles, recent errors, and any live backend-switch transition.
- `GET /runtime/status` returns the underlying `SpeakSwiftly.StatusEvent` plus the same live backend-switch transition summary.
- `GET /runtime/configuration` and `PUT /runtime/configuration` expose saved next-start backend configuration. This is startup intent, not a live transition feed.
- `POST /runtime/backend` accepts an ordered backend-switch request and returns `202 Accepted` with the retained request URL and event URL. While the runtime waits for active work to settle, clients should read `GET /runtime/host`, `GET /runtime/status`, or the returned request resource to observe the requested backend, current active backend, request ID, and waiting reason.
- `POST /runtime/models/reload` and `POST /runtime/models/unload` follow the current runtime-control verbs directly.

The current HTTP SSE route remains intentionally job-specific at the route boundary, but it now rides the same host-owned event backbone used by other non-UI consumers instead of keeping a separate per-job subscriber registry inside `ServerHost`.

## MCP Surface

The MCP surface is optional and mounts on the same shared Hummingbird process at `APP_MCP_PATH` when `APP_MCP_ENABLED=true`.

### MCP Tools

#### Speech And Artifact Tools

- `generate_speech`
- `generate_audio_file`
- `generate_batch`
- `list_active_requests`
- `list_generation_jobs`
- `get_generation_job`
- `expire_generation_job`
- `list_generated_files`
- `get_generated_file`
- `list_generated_batches`
- `get_generated_batch`

#### Voice Tools

- `create_voice_profile_from_description`
- `create_voice_profile_from_audio`
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
- `get_staged_runtime_config`
- `set_staged_config`
- `switch_speech_backend`
- `reload_models`
- `unload_models`
- `list_generation_queue`
- `list_playback_queue`
- `pause_playback`
- `resume_playback`
- `get_playback_state`
- `clear_playback_queue`
- `cancel_request`

`set_staged_config` changes the persisted next-start backend. `switch_speech_backend` queues live runtime work and returns an accepted request payload; read `speak://runtime/overview`, `speak://runtime/status`, or `speak://requests/{request_id}` to observe the pending and active backend state.

### MCP Resources

#### Runtime Resources

- `speak://runtime/overview`
- `speak://runtime/status`
- `speak://runtime/configuration`

#### Voice Resources

- `speak://voices`
- `speak://voices/guide`
- `speak://voices/{profile_name}`

#### Text Profile Resources

- `speak://text-profiles`
- `speak://text-profiles/style`
- `speak://text-profiles/base`
- `speak://text-profiles/active`
- `speak://text-profiles/effective`
- `speak://text-profiles/effective/{profile_id}`
- `speak://text-profiles/stored/{profile_id}`
- `speak://text-profiles/guide`

#### Request, Artifact, And Playback Resources

- `speak://requests`
- `speak://requests/{request_id}`
- `speak://generation/jobs`
- `speak://generation/jobs/{job_id}`
- `speak://generation/files`
- `speak://generation/files/{artifact_id}`
- `speak://generation/batches`
- `speak://generation/batches/{batch_id}`
- `speak://playback/guide`

Those MCP tools and resources are intentionally thin adapters over the same `ServerHost` snapshots and mutations used by the HTTP API and the app-facing `ServerState`.

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

The text-profile prompts and the `speak://text-profiles/guide` resource are there so an app-hosted or MCP-hosted agent can help a user author replacements deliberately instead of treating normalization rules like hidden implementation detail.

### MCP Resource Subscriptions

The embedded MCP surface supports resource subscriptions for the live state resources and templates backed by shared host updates.

Clients connected to the standalone MCP event stream can subscribe to:

- `speak://runtime/overview`
- `speak://runtime/status`
- `speak://runtime/configuration`
- `speak://voices`
- `speak://voices/{profile_name}`
- `speak://requests`
- `speak://requests/{request_id}`
- `speak://generation/jobs`
- `speak://generation/jobs/{job_id}`
- `speak://generation/files`
- `speak://generation/files/{artifact_id}`
- `speak://generation/batches`
- `speak://generation/batches/{batch_id}`
- `speak://text-profiles`
- `speak://text-profiles/style`
- `speak://text-profiles/base`
- `speak://text-profiles/active`
- `speak://text-profiles/effective`
- `speak://text-profiles/effective/{profile_id}`
- `speak://text-profiles/stored/{profile_id}`

Subscribed clients receive `notifications/resources/updated` when shared host events change the underlying state.

## Transport Status Notes

Transport lifecycle snapshots are intentionally tied to the shared Hummingbird process rather than static config alone. `listening` means the shared HTTP host has actually reached Hummingbird's `onServerRunning` boundary, so HTTP and MCP surface status describe real network availability instead of only configuration intent.
