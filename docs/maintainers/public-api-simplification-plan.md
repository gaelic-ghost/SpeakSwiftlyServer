# Public API Simplification Plan

Use this document to track the public API cleanup work across the Swift library, HTTP surface, MCP surface, and public docs. The goal is to reduce consumer confusion without hiding the real runtime model or leaving duplicate names and response shapes behind.

## Current Surface Map

`SpeakSwiftlyServer` currently exposes four public API families:

- Swift package API through the `SpeakSwiftlyServer` library product, centered on `EmbeddedServer`, `HostStateSnapshot`, queue snapshots, playback snapshots, runtime configuration snapshots, install-layout helpers, and voice-profile summaries.
- HTTP API through the localhost Hummingbird host, including runtime, voice, text-profile, speech, request, generation, playback, and health routes.
- MCP API through tools, resources, resource templates, prompts, and resource subscriptions mounted on the same shared host.
- Operator docs and plugin guidance that explain which API family an app, agent, hook, or maintainer should reach for first.

The surfaces are intentionally adapters over the same `ServerHost` state, but several public names and shapes still make consumers learn internal history before they can choose the right entrypoint.

## Simplification Principles

- Prefer one public name for one public job.
- Keep reads and mutations visibly different: resources and snapshots are for inspection; tools and routes that mutate state should be obvious commands.
- Keep request tracking, retained generation metadata, and retained audio artifacts distinct only where that distinction helps a consumer do real work.
- Keep Swift app-facing models and transport-facing models shaped from shared primitives so code changes do not need two parallel response types for the same state.
- Keep compatibility shims intentional, documented, and time-bound when a cleanup cannot be immediate.

## Detailed Findings

### Read-Only MCP Tools Duplicate Resources

The MCP surface exposes read-only tools such as `get_runtime_overview`, `get_runtime_status`, `get_staged_runtime_config`, `list_voice_profiles`, `get_text_normalizer_snapshot`, `get_text_profile_style`, `list_generation_queue`, `list_playback_queue`, `get_playback_state`, `list_active_requests`, `list_generation_jobs`, `get_generation_job`, `list_generated_files`, `get_generated_file`, `list_generated_batches`, and `get_generated_batch`.

Most of those tools mirror resources with the same read job:

- `speak://runtime/overview`
- `speak://runtime/status`
- `speak://runtime/configuration`
- `speak://voices`
- `speak://text-profiles`
- `speak://text-profiles/style`
- `speak://requests`
- `speak://requests/{request_id}`
- `speak://generation/jobs`
- `speak://generation/jobs/{job_id}`
- `speak://generation/files`
- `speak://generation/files/{artifact_id}`
- `speak://generation/batches`
- `speak://generation/batches/{batch_id}`

This creates a choice burden for agents. For inspection, an agent should usually read a resource first because resources are discoverable, subscribable, and stable orientation surfaces. Tools should remain the primary path for queueing speech, changing runtime state, editing profiles, and deleting or cancelling work.

### Requests, Jobs, Files, And Batches Need A Clearer Mental Model

The public surface currently asks consumers to understand these related concepts:

- A tracked request is a server-host operation with progress and terminal state.
- A generation job is retained generation metadata from the `SpeakSwiftly` runtime.
- A generated file is one retained audio artifact.
- A generated batch is a retained group of generated artifacts.

Those distinctions are real, but the first-read docs should not make them feel like four unrelated product areas. The durable model should be:

- Request: the operation to follow while work is active or recently completed.
- Job: runtime generation metadata retained for diagnosis and artifact lookup.
- Artifact: the generated output, whether produced as one file or as part of a batch.

Longer term, generated files and generated batches may deserve one artifact-family route or resource set. That is compatibility-sensitive and should happen after the lower-risk cleanup below.

### Cancellation Has Too Many Public Choices

The MCP surface exposes `cancel_request`, `cancel_generation`, and `cancel_playback`, all keyed by `request_id`. HTTP also exposes scoped cancellation routes:

- `DELETE /generation/requests/{request_id}`
- `DELETE /playback/requests/{request_id}`

The scoped operations are useful when the caller knows which queue owns the work, but they create hesitation when an operator simply wants to stop one known request. The clearest durable API is one general cancel operation with optional scope only when scope materially protects the caller from cancelling the wrong kind of work.

### Runtime Configuration Uses Too Many Labels

The runtime configuration surface currently uses overlapping words: staged, persisted, next-start, active, and runtime configuration. The response shape is already helpful because it distinguishes active values, next-start values, persisted values, and environment overrides. The confusing part is naming the same surface `staged` in MCP while docs describe persisted next-start runtime configuration.

The preferred public wording is `runtime configuration`, with field names carrying the specific state:

- `active_*` for the currently running runtime.
- `next_*` for the value that will apply on the next runtime start.
- `persisted_*` for the saved value on disk.
- `environment_*_override` for process environment overrides.

`get_staged_runtime_config` and `set_staged_config` should eventually move to runtime-configuration wording. Because MCP tool names are user-visible, that rename should be planned as a compatibility cleanup rather than changed casually.

### Text Profiles Are Powerful But Heavy

The HTTP surface exposes separate active and stored text-profile mutation paths:

- `POST /text-profiles/active/replacements`
- `POST /text-profiles/stored/{profile_id}/replacements`
- `PUT /text-profiles/active/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `DELETE /text-profiles/active/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}/replacements/{replacement_id}`

The MCP tools already use a simpler shape: replacement tools target the active profile by default and target a stored profile when `profile_id` is provided. HTTP can eventually follow that target model, but doing so touches route compatibility and should wait until after the shared model cleanup and resources-first guidance.

### Snapshot Models Are Duplicated

The Swift library exposes public app-facing snapshots such as `PlaybackStatusSnapshot` and `QueueStatusSnapshot`, while the HTTP/MCP transport layer also has transport-facing shapes such as `PlaybackStateSnapshot`, `PlaybackStateResponse`, and `QueueSnapshotResponse`.

Some of that wrapping is useful because HTTP response envelopes differ from app state, but the inner playback shape is duplicated. This is the best first implementation slice because it can reduce internal duplication without changing public route names or MCP tool names.

The target shape is:

- One shared playback snapshot model used by app state and transport response envelopes.
- One shared queue snapshot model or one explicit conversion boundary from `QueueStatusSnapshot` to a route envelope, without duplicate field definitions for active and queued requests.
- Tests that prove HTTP, MCP, and `EmbeddedServer` still encode the same field names.

### EmbeddedServer Is Narrower Than HTTP And MCP

`EmbeddedServer` exposes live speech queueing, voice-profile cache refresh, default voice selection, runtime backend/model controls, and playback controls. It does not expose retained file generation, batch generation, text-profile editing, generated artifacts, generation jobs, or direct request detail APIs.

That may be the right product choice: `EmbeddedServer` is a small app-facing control model, while HTTP and MCP expose the broader operator surface. The docs should say that intentionally. If downstream apps need artifact generation or text-profile authoring in-process, add those deliberately instead of assuming the Swift library should mirror every transport route.

## Implementation Plan

### Phase 1: Snapshot Dedupe First

This phase is a durable building-block cleanup. It reduces duplicate state models and makes later public cleanup safer because every surface will encode playback and queue state from the same primitives.

Status: implemented for the first cleanup pass. `PlaybackStatusSnapshot` is now the shared playback model used by `EmbeddedServer`, HTTP playback responses, and request-event payloads. Queue route responses now shape from `QueueStatusSnapshot` through a narrow response initializer, preserving the existing HTTP `queue` field while keeping queue ownership in the shared host snapshot.

Tasks:

- [x] Replace the private transport-only playback snapshot with the public shared playback snapshot where possible.
- [x] Keep HTTP response envelopes where they help route clarity, but stop duplicating the inner playback fields.
- [x] Review queue response shaping and either reuse `QueueStatusSnapshot` directly or keep a single narrow conversion helper with no duplicate active-request field definitions.
- [x] Add or tighten tests that compare HTTP playback/queue responses, MCP runtime overview resources, and `EmbeddedServer` snapshots for matching field names and equivalent state.
- [x] Update `docs/maintainers/source-layout.md` if model ownership moves.
- Run `xcrun swift build`, focused snapshot/model tests, and the repo validation gate when the code change is ready.

Non-goals:

- Do not rename HTTP routes.
- Do not rename MCP tools.
- Do not collapse requests, jobs, files, or batches yet.
- Do not widen `EmbeddedServer` yet.

### Phase 2: MCP Resources-First Guidance Immediately After

This phase changes guidance and catalog wording before it changes compatibility-sensitive tool availability. Agents should learn to inspect resources first and use tools for mutations, queueing, and destructive operations.

Status: implemented for the first guidance pass. README and API wording now describe MCP resources as the preferred read path. MCP tool descriptions call read-only tools compatibility paths. Guide resources and `choose_surface_action` tell agents to inspect `speak://...` resources first and reserve tools for actions.

Tasks:

- [x] Update `API.md`, `README.md`, and MCP guide resources so first-read guidance says: read `speak://runtime/overview` for orientation, read specific resources for state, call tools for actions.
- [x] Update MCP tool descriptions for read-only tools to point at their matching resources when the resource is the preferred inspection path.
- [x] Update `choose_surface_action` prompt guidance so agents prefer resources for read-only status checks.
- [x] Confirm resource subscription wording explains that resources are the live-status path, including the current limitation that playback freshness depends on host events until upstream runtime-level playback event streams land.
- [x] Add tests for guide text or catalog descriptions when the existing catalog tests can cover the wording without becoming brittle.
- Run MCP catalog tests and the API/roadmap/documentation checks.

Non-goals:

- Do not remove read-only tools yet.
- Do not break existing MCP callers.
- Do not hide the read-only tools from clients until a compatibility plan is written.

### Phase 3: Compatibility-Sensitive Cleanup Later

These items should be revisited after the first two phases are reviewed and landed:

- Rename staged runtime configuration MCP tools to runtime-configuration wording, with any compatibility alias or breaking-change note decided explicitly.
- Collapse or simplify cancellation around one general cancel operation plus optional scope.
- Rework generated files and generated batches into a clearer artifact-family model.
- Consider HTTP text-profile replacement routes that use the same optional-target model as MCP.
- Decide whether `EmbeddedServer` intentionally stays narrow or grows artifact and text-profile APIs.

## Review Checklist

- Public docs name one preferred path for each common job.
- Any duplicate API surface that remains has a stated compatibility or ergonomics reason.
- Swift app-facing snapshots, HTTP responses, and MCP resources agree on field names for shared state.
- MCP catalog guidance does not make agents choose between tools and resources for the same read-only task without guidance.
- The roadmap captures the current ordering: snapshot dedupe first, resources-first MCP guidance second, compatibility-sensitive cleanup later.
