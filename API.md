# SpeakSwiftlyServer API Reference

Use this reference to understand the local HTTP API, MCP surface, embedded server API, request and response models, and verification paths for SpeakSwiftlyServer.

## Table of Contents

- [Overview](#overview)
- [API Surface](#api-surface)
- [Authentication and Access](#authentication-and-access)
- [Requests and Responses](#requests-and-responses)
- [Errors](#errors)
- [Versioning and Compatibility](#versioning-and-compatibility)
- [Local Development and Verification](#local-development-and-verification)
- [Support and Ownership](#support-and-ownership)

## Overview

### Who This API Is For

This API is for local macOS apps, Codex plugin integrations, MCP clients, developer tools, and maintainers that need to talk to a local SpeakSwiftly speech service.

The server exposes one shared localhost host process with HTTP routes, an optional MCP surface, an embeddable Swift library surface, and shared runtime state for retained requests, generated artifacts, playback, voice profiles, text profiles, and runtime configuration.

### Stability Status

The HTTP and MCP surfaces are active local-service APIs. They are intentionally localhost-first and are not designed as a remote multi-user service boundary.

The embedded Swift surface is the supported package-level integration point for apps that want to own a local server session in-process. Maintainer comparison against the resolved SpeakSwiftly package surface lives in `docs/maintainers/speakswiftly-api-coverage-matrix.md`.

## API Surface

### Entry Points

HTTP runtime and health routes:

- `GET /healthz`
- `GET /readyz`
- `GET /overview`
- `GET /status`
- `GET /configuration`
- `PUT /configuration`
- `POST /backend`
- `POST /models/reload`
- `POST /models/unload`

HTTP speech, request, generation, and artifact routes:

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

HTTP voice routes:

- `GET /voices`
- `POST /voices/from-description`
- `POST /voices/from-audio`
- `POST /voices/{profile_name}/reroll`
- `PUT /voices/{profile_name}/name`
- `DELETE /voices/{profile_name}`

HTTP text-profile routes:

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

HTTP playback routes:

- `GET /playback/state`
- `GET /playback/queue`
- `POST /playback/pause`
- `POST /playback/resume`
- `DELETE /playback/queue`

MCP tools:

- speech and artifacts: `generate_speech`, `generate_audio_file`, `generate_batch`, `expire_generation_job`
- voices: `create_voice_profile_from_description`, `create_voice_profile_from_audio`, `update_voice_profile_name`, `reroll_voice_profile`, `delete_voice_profile`
- text profiles: `set_text_profile_style`, `load_text_profiles`, `save_text_profiles`, `create_text_profile`, `rename_text_profile`, `set_active_text_profile`, `delete_text_profile`, `factory_reset_text_profiles`, `reset_text_profile`, `add_text_replacement`, `replace_text_replacement`, `remove_text_replacement`
- playback and runtime: `set_runtime_configuration`, `switch_speech_backend`, `reload_models`, `unload_models`, `pause_playback`, `resume_playback`, `clear_generation_queue`, `clear_playback_queue`, `cancel_request`

MCP resources:

- runtime: `speak-swiftly://overview`, `speak-swiftly://status`, `speak-swiftly://configuration`
- voices: `speak-swiftly://voices`, `speak-swiftly://voices/guide`, `speak-swiftly://voices/{profile_name}`
- text profiles: `speak-swiftly://text-profiles`, `speak-swiftly://text-profiles/style`, `speak-swiftly://text-profiles/base`, `speak-swiftly://text-profiles/active`, `speak-swiftly://text-profiles/effective`, `speak-swiftly://text-profiles/effective/{profile_id}`, `speak-swiftly://text-profiles/stored/{profile_id}`, `speak-swiftly://text-profiles/guide`
- requests, jobs, artifacts, and playback: `speak-swiftly://requests`, `speak-swiftly://requests/{request_id}`, `speak-swiftly://generation/jobs`, `speak-swiftly://generation/jobs/{job_id}`, `speak-swiftly://generation/artifacts`, `speak-swiftly://generation/artifacts/{artifact_id}`, `speak-swiftly://playback`, `speak-swiftly://playback/queue`, `speak-swiftly://playback/guide`

MCP prompts:

- `draft_profile_voice_description`
- `draft_profile_source_text`
- `draft_text_profile`
- `draft_text_replacement`
- `draft_voice_design_instruction`
- `draft_queue_playback_notice`
- `choose_surface_action`

Embedded Swift entry points:

- `EmbeddedServer`
- `EmbeddedServerSession`
- `ServerConfiguration`
- `RuntimeStartupConfiguration`
- `ServerState` and related snapshot models exposed by the library target

### Protocols and Transports

The HTTP surface runs on the shared Hummingbird process. Transport lifecycle snapshots report real listening state from the server-running boundary, not only configuration intent.

The MCP surface is optional and mounts on the same shared process when MCP is enabled. MCP resources are the preferred read path; MCP tools are reserved for queueing speech, changing runtime state, editing profiles, cancelling work, and clearing queues.

Embedded app hosts use the Swift package library surface. The embedded model runs HTTP and optional MCP inside an outer service-owned lifecycle group that also owns host startup, config-watch lifetime, readiness, and drain.

## Authentication and Access

### Credentials

The default local service API does not require bearer tokens, sessions, certificates, or remote credentials. It is designed for localhost use by trusted local apps, tools, and agents.

MCP clients identify themselves through the MCP initialize payload when available. That client information is used as request-context provenance, not as an authentication secret.

### Permissions

Callers need local network access to the configured bind address and port. Operators need filesystem access to the server state root, runtime profile state, generated artifacts, configuration file, and LaunchAgent-managed service files when installing or operating the standalone service.

Voice creation from audio requires the server process to read the referenced audio file. Generated file and batch requests require write access to the server-managed artifact storage.

## Requests and Responses

### Request Shape

Accepted request routes and tools return immediately with request-tracking metadata. Speech requests commonly include:

- `text`
- `profile_name`
- `cwd`
- `repo_root`
- `request_context`
- `text_profile_id`
- `qwen_pre_model_text_chunking`

`POST /speech/live` queues live playback. `POST /speech/files` and `POST /speech/batches` queue retained artifact generation. When `profile_name` is omitted, the server uses the configured app default voice when one exists, then falls back to the runtime default voice.

The server applies request purpose from the route or MCP tool. Callers do not send `reqPurpose`. Caller-provided `request_context` may include `source`, `topic`, `cwd`, `repo_root`, `attributes`, and optional `prefacePolicy`; omit `prefacePolicy` for the default behavior, set it to `always` to force the source/topic preface, or set it to `never` to suppress that preface.

Voice profile creation accepts either a description-backed payload or an audio-backed payload. Text-profile routes accept profile IDs, names, active-style values, and `TextForSpeech.Replacement` payloads. Runtime configuration routes use `speech_backend` for saved next-start backend selection and optional `duck_media_volume` for saved next-start media ducking. `POST /backend` requests a live backend switch.

### Response Shape

Accepted HTTP responses use:

- `request_id`
- `request_url`
- `events_url`

Accepted MCP tool results use:

- `request_id`
- `request_resource_uri`
- `status_resource_uri`

State-oriented routes and resources return JSON snapshots. Examples include host overview, runtime status, saved runtime configuration, voice profile lists, text-profile state, generation queues, retained requests, generation jobs, generation artifacts, playback state, and playback queue.

Playback milestones are normalized into snake_case event names such as `active_request_changed`, `queue_changed`, `first_chunk`, `preroll_ready`, `rebuffer_started`, `rebuffer_resumed`, `completed`, `output_device_changed`, and `interruption_changed`.

### Data Models

Important API models include:

- host snapshots: overview, status, transport status, recent errors, queue summaries, and cached profile state
- request records: request ID, kind, state, accepted time, last update, retained events, and terminal result
- generation records: generation queue, jobs, job items, artifacts, artifact IDs, retained file paths, and job failures
- playback records: playback state, active request, queued requests, buffer stability, and latest playback event
- voice profile records: profile names, summaries, detail payloads, system-authored metadata, and reroll/delete/rename request results
- text profile records: built-in style, base profile, active profile, stored profiles, effective profiles, and replacements
- runtime configuration records: saved next-start backend configuration, saved next-start media ducking, and live backend-switch transition summaries

## Errors

### Error Shape

HTTP errors use status codes plus JSON diagnostics from the route support layer. Long-running work reports operational failures through retained request state and request events so clients can follow the same request URL from acceptance to completion or failure.

MCP errors are returned through MCP tool or resource error responses. MCP resource subscription updates use `notifications/resources/updated` when shared host events change the underlying state.

### Common Failure Modes

- `/readyz` is not ready: inspect `/overview`, `/status`, and recent errors before queueing speech.
- A request is accepted but stalls: follow `events_url` or the matching MCP request resource and check generation, backend-switch, and playback queue state.
- A voice profile is missing: read `/voices` or `speak-swiftly://voices` and confirm the selected `profile_name`.
- A text profile or replacement is missing: read the relevant `/text-profiles/...` route or MCP text-profile resource before mutating it.
- A backend switch waits: read `/overview`, `/status`, or the retained backend-switch request to see the active backend, requested backend, and waiting reason.
- Configuration changes do not take effect: check whether the changed field is live-reloadable or startup-only.

## Versioning and Compatibility

### Supported Versions

This checkout builds as Swift language mode 6 with Swift tools version 6.3 and a macOS 15 platform floor.

The current package depends on `SpeakSwiftly` from `10.0.0`, `TextForSpeech` from `0.22.1`, Hummingbird from `2.21.1`, the Swift MCP SDK from `0.12.0`, Swift Configuration from `1.2.0`, Swift Async Algorithms from `1.1.3`, `mlx-audio-swift` from `0.100.0`, and `mlx-swift-lm` exact `3.31.3`.

### Breaking Changes

Breaking HTTP, MCP, embedded Swift, configuration, request-model, or resource-URI changes should be reflected in this file, release notes, README usage guidance, plugin metadata when applicable, and transport tests.

MCP read behavior should stay resources-first. If a read surface moves between tools and resources, update `MCPResources.swift`, `MCPToolCatalog.swift`, `MCPToolHandlers.swift`, prompts, tests, and this document together.

## Local Development and Verification

### Runtime Configuration

`APP_CONFIG_FILE` points the server at a YAML config file watched through the reloading configuration provider. `APP_CONFIG_RELOAD_INTERVAL_SECONDS` controls the polling interval and defaults to 2 seconds.

The live-reloadable subset currently includes app name, app environment, SSE heartbeat seconds, completed-job TTL seconds, completed-job max count, and job-prune interval seconds. Bind addresses, ports, HTTP enablement, MCP enablement, MCP path, MCP metadata, profile root, runtime backend startup settings, and runtime media ducking settings require a process restart.

`SPEAKSWIFTLY_PROFILE_ROOT` is startup-only and points at the server-owned profile-store root. `SPEAKSWIFTLY_SPEECH_BACKEND` overrides the persisted next-start backend while building the explicit `SpeakSwiftly.Configuration` for runtime startup.

Supported `speech_backend` values come from `SpeakSwiftly.SpeechBackend` and include Qwen, Chatterbox Turbo, and Marvis variants such as `qwen3_smol`, `qwen3_smol_4bit`, `qwen3_smol_5bit`, `qwen3_smol_6bit`, `qwen3_smol_8bit`, `qwen3_smol_bf16`, `qwen3_big`, `qwen3_big_4bit`, `qwen3_big_5bit`, `qwen3_big_6bit`, `qwen3_big_8bit`, `qwen3_big_bf16`, `chatterbox_turbo`, `marvis`, `marvis_4bit`, and `marvis_6bit`.

Supported `duck_media_volume` values come from `SpeakSwiftly.DuckMediaVolume`: `off`, `a_little`, `default`, and `a_lot`. Runtime configuration snapshots report `active_duck_media_volume`, `next_duck_media_volume`, and `persisted_duck_media_volume`; a duck-only change keeps `active_runtime_matches_next_runtime` false until the next runtime start. Any value except `off` may require macOS Automation permission because SpeakSwiftly lowers supported media app volumes while speech playback is active, then restores them afterward.

### Verification

Use the ordinary SwiftPM checks for package-level validation:

```bash
xcrun swift build
xcrun swift test
```

Use the repo-owned maintainer gate for complete local validation:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Use the local live end-to-end gate when validating HTTP and MCP transport behavior against a live helper:

```bash
sh scripts/repo-maintenance/validate-local-e2e.sh
```

Use the tool surface for manual foreground and health checks:

```bash
xcrun swift run SpeakSwiftlyServerTool serve
xcrun swift run SpeakSwiftlyServerTool healthcheck --base-url http://127.0.0.1:7338
```

## Support and Ownership

Gale owns this package and local service under `gaelic-ghost/SpeakSwiftlyServer`. Use the repository issue tracker and the repo-local maintainer guidance in `AGENTS.md`, `CONTRIBUTING.md`, `docs/maintainers/`, and `scripts/repo-maintenance/` when the API contract is unclear or broken.
