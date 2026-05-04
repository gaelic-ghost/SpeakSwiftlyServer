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

The MCP surface still exposes read-only tools such as `get_runtime_overview`, `get_runtime_status`, `get_runtime_configuration`, `list_voice_profiles`, `get_text_normalizer_snapshot`, `get_text_profile_style`, `list_generation_queue`, `list_playback_queue`, `get_playback_state`, `list_active_requests`, `list_generation_jobs`, and `get_generation_job`.

Most of those tools mirror resources with the same read job:

- `speak-swiftly://overview`
- `speak-swiftly://status`
- `speak-swiftly://configuration`
- `speak-swiftly://voices`
- `speak-swiftly://text-profiles`
- `speak-swiftly://text-profiles/style`
- `speak-swiftly://requests`
- `speak-swiftly://requests/{request_id}`
- `speak-swiftly://generation/jobs`
- `speak-swiftly://generation/jobs/{job_id}`
- `speak-swiftly://generation/artifacts`
- `speak-swiftly://generation/artifacts/{artifact_id}`

The MCP resource scheme is now `speak-swiftly://`. Because that scheme already names the product surface, the older `speak://runtime/...` route prefix added cognitive load without adding useful selection power. The next-major MCP read surface therefore keeps the runtime concepts but flattens their resource paths to `speak-swiftly://overview`, `speak-swiftly://status`, and `speak-swiftly://configuration`.

This creates a choice burden for agents. For inspection, an agent should usually read a resource first because resources are discoverable, subscribable, and stable orientation surfaces. Tools should remain the primary path for queueing speech, changing runtime state, editing profiles, and deleting or cancelling work.

For the next major generated-artifact cleanup, the file and batch resource families should not be carried forward as compatibility aliases. Replace them with one artifact family:

- `speak-swiftly://generation/artifacts`
- `speak-swiftly://generation/artifacts/{artifact_id}`

Batch membership should be artifact metadata or request/job metadata, not a peer read family that agents must choose before they know what kind of retained output they are looking for.

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

The next major target is one generated-artifact family:

- HTTP: `GET /generation/artifacts` and `GET /generation/artifacts/{artifact_id}`
- MCP resources: `speak-swiftly://generation/artifacts` and `speak-swiftly://generation/artifacts/{artifact_id}`
- MCP tools: one generated-artifact read pair, if compatibility read tools are still kept at all

This should be a breaking major-version cleanup, not an alias-heavy transition. Remove the older HTTP `files` and `batches` read routes, the matching MCP resources/templates, and the matching read-only MCP tools instead of keeping duplicate aliases. `POST /speech/files` and `POST /speech/batches` can remain distinct submission commands if they still represent different generation jobs; the cleanup is about the retained artifact read model.

### Cancellation Used To Have Too Many Public Choices

The MCP surface now exposes one cancellation tool, `cancel_request`, keyed by `request_id` with optional `scope`. HTTP exposes the same model:

- `DELETE /requests/{request_id}` with optional `?scope=generation|playback`

Scope is only present as an optional field on the primary request cancellation path, which keeps the common "stop this request id" operation obvious while still allowing queue-specific protection when the caller needs it.

### Built-In Voices Need A User/Developer Boundary

`SpeakSwiftly` now owns system voice-profile authorship, seed metadata, system-profile immutability, and reroll-as-user-copy behavior. That moves the built-in voice policy out of server-local inference and into the runtime model that persists profiles.

The server should use that upstream model directly:

- startup-installed defaults are created as system-authored profiles with `ProfileSeed` metadata
- ordinary users can list system profiles and choose one as the default or request voice
- system profile source text, voice-design prompt, and seed provenance are exposed only through explicit maintainer/tool surfaces
- ordinary create, rename, delete, and in-place reroll flows stay framed as user-owned profile operations

This keeps `swift-signal` and `swift-anchor` consistent out of the box while still giving maintainers a deliberate path to inspect seed internals during package development and repair work.

### Runtime Configuration Uses Too Many Labels

The runtime configuration surface currently uses overlapping words: staged, persisted, next-start, active, and runtime configuration. The response shape is already helpful because it distinguishes active values, next-start values, persisted values, and environment overrides. The confusing part is naming the same surface `staged` in MCP while docs describe persisted next-start runtime configuration.

The preferred public wording is `runtime configuration`, with field names carrying the specific state:

- `active_*` for the currently running runtime.
- `next_*` for the value that will apply on the next runtime start.
- `persisted_*` for the saved value on disk.
- `environment_*_override` for process environment overrides.

The public MCP tools are now `get_runtime_configuration` and `set_runtime_configuration`. The older staged-config tool names were removed in the next-major cleanup.

### Text Profiles Are Powerful But Heavy

The HTTP surface used to expose separate active and stored text-profile mutation paths:

- `POST /text-profiles/active/replacements`
- `POST /text-profiles/stored/{profile_id}/replacements`
- `PUT /text-profiles/active/replacements/{replacement_id}`
- `PUT /text-profiles/stored/{profile_id}/replacements/{replacement_id}`
- `DELETE /text-profiles/active/replacements/{replacement_id}`
- `DELETE /text-profiles/stored/{profile_id}/replacements/{replacement_id}`

The MCP tools already use a simpler shape: replacement tools target the active profile by default and target a stored profile when `profile_id` is provided. HTTP now has matching target-model routes:

- `POST /text-profiles/replacements`
- `PUT /text-profiles/replacements/{replacement_id}`
- `DELETE /text-profiles/replacements/{replacement_id}`

The older active/stored route families were removed in the next-major cleanup so HTTP has the same targeting model as MCP.

For add and replace, `profile_id` lives in the JSON body beside `replacement`. For delete, optional `profile_id` is passed as a query parameter because the route otherwise needs no request body. The older active/stored replacement route families remain as compatibility aliases until a breaking cleanup removes or formally deprecates them.

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

- Do not rename HTTP routes in the resource-guidance slice.
- Do not rename MCP tools.
- Do not collapse requests, jobs, files, or batches yet.
- Do not widen `EmbeddedServer` yet.

### Phase 2: MCP Resources-First Guidance Immediately After

This phase changes guidance and catalog wording before it changes compatibility-sensitive tool availability. Agents should learn to inspect resources first and use tools for mutations, queueing, and destructive operations.

Status: implemented for the first guidance pass. README and API wording now describe MCP resources as the preferred read path. MCP tool descriptions call read-only tools compatibility paths. Guide resources and `choose_surface_action` tell agents to inspect `speak-swiftly://...` resources first and reserve tools for actions. The MCP URI scheme is now `speak-swiftly://`, and the redundant MCP `runtime` path segment has been removed from overview, status, and configuration resources.

Tasks:

- [x] Update `API.md`, `README.md`, and MCP guide resources so first-read guidance says: read `speak-swiftly://overview` for orientation, read specific resources for state, call tools for actions.
- [x] Rename the MCP resource URI scheme from `speak://` to `speak-swiftly://` and flatten runtime reads from older `speak://runtime/...` resources to top-level `speak-swiftly://overview`, `speak-swiftly://status`, and `speak-swiftly://configuration`.
- [x] Update MCP tool descriptions for read-only tools to point at their matching resources when the resource is the preferred inspection path.
- [x] Update `choose_surface_action` prompt guidance so agents prefer resources for read-only status checks.
- [x] Confirm resource subscription wording explains that resources are the live-status path, including the current limitation that playback freshness depends on host events until upstream runtime-level playback event streams land.
- [x] Add tests for guide text or catalog descriptions when the existing catalog tests can cover the wording without becoming brittle.
- Run MCP catalog tests and the API/roadmap/documentation checks.

HTTP runtime routes were flattened in the next-major cleanup: `GET /overview`, `GET /status`, `GET`/`PUT /configuration`, `POST /backend`, and `POST /models/reload` or `/models/unload`. The old `/runtime/...` route family is not carried forward.

Non-goals:

- Do not remove read-only tools yet.
- Do not remove remaining read-only MCP tools without a separate review.
- Do not hide the read-only tools from clients until a compatibility plan is written.

### Phase 3: Upstream-Aligned Voice Authorship

This phase adopts the `SpeakSwiftly` system-authored voice-profile model instead of continuing to infer built-in identity from profile names, source text, and voice descriptions alone.

Status: in progress. Startup default voice creation now routes through the system-design runtime API with `ProfileSeed` metadata. Public profile encoding includes narrow authorship fields while redacting system seed source text and voice-design prompts from ordinary profile resources. The MCP surface has an explicit developer-only seed inspection tool for maintainer work.

Tasks:

- [x] Thread upstream `author`, `seed_id`, and `seed_version` metadata into cached voice-profile snapshots.
- [x] Create bundled default voices through the upstream system-design API instead of ordinary user-profile creation.
- [x] Redact system-authored source text and voice-design prompts from ordinary encoded profile JSON.
- [x] Add an explicit `inspect_builtin_voice_seed` tool for maintainer/development inspection of package seed internals.
- [x] Update README, API reference, and plugin-facing guidance so normal users understand built-ins as list-and-select default voices, not editable user profile designs.
- [ ] Decide whether future built-in seed refresh/removal should be one maintainer tool or remain internal startup maintenance.

Non-goals:

- Do not add ordinary user tools for creating arbitrary system-authored profiles.
- Do not widen `EmbeddedServer` with seed-management APIs.
- Do not remove user-owned profile creation, clone, rename, reroll, or delete flows.

### Phase 4: Compatibility-Sensitive Cleanup Later

These items should be revisited after the first two phases are reviewed and landed:

- [x] Add target-model HTTP text-profile replacement routes that match MCP's optional `profile_id` behavior.
- [x] Collapse preferred cancellation around `DELETE /requests/{request_id}` and MCP `cancel_request`, with optional `generation`/`playback` scope.
- [x] Add preferred runtime-configuration MCP tool names.
- [x] Decide the generated-artifact target shape for the next major version: one artifact read family with no files/batches compatibility aliases.
- [x] Remove duplicated active/stored HTTP replacement route families as breaking removals in the next-major cleanup.
- [x] Remove duplicated scoped cancellation HTTP routes and MCP tools as breaking removals in the next-major cleanup.
- [x] Remove duplicated staged runtime-configuration MCP tools as breaking removals in the next-major cleanup.
- [x] Rework older generated-file and generated-batch reads into the next-major retained artifact-family model: `GET /generation/artifacts`, `GET /generation/artifacts/{artifact_id}`, `speak-swiftly://generation/artifacts`, and `speak-swiftly://generation/artifacts/{artifact_id}`, removing the older files/batches read surfaces instead of aliasing them.
- [x] Flatten HTTP runtime routes from `/runtime/...` to top-level `/overview`, `/status`, `/configuration`, `/backend`, and `/models/...` paths.
- [x] Adopt the `SpeakSwiftly 5.0.0-rc.1` / `TextForSpeech 0.19.0` request model directly by deleting server-local speech normalization context shaping, forwarding `source_format` directly, merging `cwd` and `repo_root` into shared `SpeakSwiftly.RequestContext`, and using upstream text-profile transport details without JSON bridge adapters.
- [ ] Decide whether `EmbeddedServer` intentionally stays narrow or grows artifact and text-profile APIs.

## Review Checklist

- Public docs name one preferred path for each common job.
- Any duplicate API surface that remains has a stated compatibility or ergonomics reason.
- Swift app-facing snapshots, HTTP responses, and MCP resources agree on field names for shared state.
- MCP catalog guidance does not make agents choose between tools and resources for the same read-only task without guidance.
- The roadmap captures the current ordering: snapshot dedupe first, resources-first MCP guidance second, compatibility-sensitive cleanup later.
