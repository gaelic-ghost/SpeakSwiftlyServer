# Project Roadmap

Use this roadmap to track the remaining package, docs, plugin, and live-service follow-through work for `SpeakSwiftlyServer`.

## Table of Contents

- [Vision](#vision)
- [Product Principles](#product-principles)
- [Milestone Progress](#milestone-progress)
- [Milestone 8: Config Reload Policy](#milestone-8-config-reload-policy)
- [Milestone 10: Swift Package Index Readiness](#milestone-10-swift-package-index-readiness)
- [Milestone 11: Runtime Surface Follow-Through](#milestone-11-runtime-surface-follow-through)
- [Milestone 12: Standalone Read-Model Parity](#milestone-12-standalone-read-model-parity)
- [Milestone 13: Runtime Maintenance Surface Review](#milestone-13-runtime-maintenance-surface-review)
- [Milestone 14: Live Service Reliability And Testing Ergonomics](#milestone-14-live-service-reliability-and-testing-ergonomics)
- [Milestone 15: Toolchain Repro And Upstream Follow-Through](#milestone-15-toolchain-repro-and-upstream-follow-through)
- [Milestone 16: Package Hardening Follow-Through](#milestone-16-package-hardening-follow-through)
- [Milestone 17: Agent And Operator Workflows](#milestone-17-agent-and-operator-workflows)
- [Milestone 18: Codex Plugin Catalog Split](#milestone-18-codex-plugin-catalog-split)
- [Milestone 19: Default Voice Setup Simplification](#milestone-19-default-voice-setup-simplification)
- [Milestone 20: Public API Simplification](#milestone-20-public-api-simplification)
- [Milestone 21: Repo-Wide Security Audit Follow-Through](#milestone-21-repo-wide-security-audit-follow-through)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Vision

Make `SpeakSwiftlyServer` the small, dependable Apple-platform speech-service package that apps, operators, and agents can embed or run locally without rebuilding transport, LaunchAgent, profile, artifact, and MCP behavior themselves.

## Product Principles

- Keep the package boundary narrow: expose HTTP, MCP, LaunchAgent, and embedded APIs as clear adapters over the same host-owned state.
- Prefer runtime-owned concepts over server-local inference when `SpeakSwiftly` or `TextForSpeech` can express the behavior directly.
- Keep live-service operations explicit, health-checked, and safe for Gale's day-to-day speech workflow.
- Keep docs, skills, media, release notes, and maintainer maps updated with the code instead of treating them as cleanup after the fact.

## Milestone Progress

- Milestone 8: Config Reload Policy - In Progress
- Milestone 10: Swift Package Index Readiness - In Progress
- Milestone 11: Runtime Surface Follow-Through - In Progress
- Milestone 12: Standalone Read-Model Parity - Planned
- Milestone 13: Runtime Maintenance Surface Review - Planned
- Milestone 14: Live Service Reliability And Testing Ergonomics - In Progress
- Milestone 15: Toolchain Repro And Upstream Follow-Through - Planned
- Milestone 16: Package Hardening Follow-Through - In Progress
- Milestone 17: Agent And Operator Workflows - In Progress
- Milestone 18: Codex Plugin Catalog Split - In Progress
- Milestone 19: Default Voice Setup Simplification - Planned
- Milestone 20: Public API Simplification - In Progress
- Milestone 21: Repo-Wide Security Audit Follow-Through - Planned

## Milestone 8: Config Reload Policy

### Status

In Progress

### Scope

- [ ] Clarify the boundary between live-reloadable host configuration and settings that should stay restart-only because they change transport binding, process shape, or runtime ownership.

### Tickets

- [ ] Decide whether transport bind settings should remain restart-only permanently or earn a coordinated live-rebind model later.

### Exit Criteria

- [ ] README, API, and maintainer docs describe the final reload boundary without leaving two competing operator stories active.

## Milestone 10: Swift Package Index Readiness

### Status

In Progress

### Scope

- [ ] Finish public package-discovery work after the package metadata and DocC surface are ready to represent the current embedded and operator APIs.

### Tickets

- [ ] Submit the package to Swift Package Index once the package metadata and hosted DocC surface are ready for public indexing.

### Exit Criteria

- [ ] Swift Package Index accepts the package and the hosted docs surface points readers at the current `EmbeddedServer`, HTTP, MCP, and LaunchAgent entrypoints.

## Milestone 11: Runtime Surface Follow-Through

### Status

In Progress

### Scope

- [ ] Keep the server's retained request, artifact, generation-job, and immediate-control surfaces aligned with the current `SpeakSwiftly` runtime model.

### Tickets

- [ ] Revisit server-local job and snapshot shaping so immediate generation-control operations and persisted generation-job reads map directly to runtime concepts instead of keeping legacy server-only wrappers around them.

### Exit Criteria

- [ ] HTTP, MCP, embedded snapshots, tests, and docs use one current runtime vocabulary for retained generation work.

## Milestone 12: Standalone Read-Model Parity

### Status

Planned

### Scope

- [ ] Bring the standalone executable and tool-owned operator path up to the same shared-host state picture that embedded apps already receive through `EmbeddedServer`.

### Tickets

- [ ] Decide what the standalone parity surface actually is: structured stdout, a local file-backed snapshot surface, a first-class CLI inspection command family, or another typed repo-owned read-model lane.
- [ ] Expose the same core shared-host snapshot families the embedded path already projects, including host overview, queue state, playback state, runtime configuration, transport state, recent errors, jobs, and voice-profile cache state.
- [ ] Keep the standalone read model sourced from the same `ServerHost` snapshot and event machinery the embedded, HTTP, and MCP paths already use instead of adding a second inference path.
- [ ] Re-check whether any embedded-only naming or shaping in `ServerState` should move down into a more shared read-model primitive before the standalone parity surface lands.
- [ ] Document the final parity boundary clearly across embedded sessions, the foreground executable, HTTP, and MCP so operators know which surface to reach for when they need the current shared host picture.

### Exit Criteria

- [ ] Foreground operators and app-owned wrappers can inspect the same host state without learning a separate state model for each entrypoint.

## Milestone 13: Runtime Maintenance Surface Review

### Status

Planned

### Scope

- [ ] Review deferred runtime surfaces after the current release line settles, and expose only the maintenance behavior that has a concrete operator or downstream app use case.

### Tickets

- [ ] Decide whether the runtime's request-update and generation-event stream surfaces should gain first-class HTTP and MCP exposure, or whether the retained request snapshots remain the cleaner operator contract.
- [ ] Revisit whether text-profile persistence state, repair, and storage diagnostics need a more explicit operator-facing surface than the current snapshot plus load/save controls.
- [ ] Decide whether any newer voice-profile maintenance operations beyond create, clone, list, rename, reroll, and delete belong in the public server contract or should stay library-only until a downstream operator use case is concrete.

### Exit Criteria

- [ ] Each accepted maintenance surface has docs and tests, and each rejected or deferred surface has a short recorded reason.

## Milestone 14: Live Service Reliability And Testing Ergonomics

### Status

In Progress

### Scope

- [ ] Reduce live-service release risk by making LaunchAgent behavior, HTTP health, MCP initialization, retained requests, and release verification easier to prove in one foreground flow at a time.

### Tickets

- [ ] Add an app-managed LaunchAgent smoke test that starts from a canonical config path with spaces and verifies both `GET /overview` and MCP `initialize`.
- [ ] Add explicit startup logging for canonical config paths, LaunchAgent alias staging, and the exact config file path the runtime loader opened.
- [ ] Decide whether LaunchAgent-owned startup config should keep using a reloading provider or move to a simpler startup-open path with reload support layered on intentionally later.
- [ ] Promote the existing MCP E2E client utilities into a reusable repo-owned smoke helper for local checks, CI, and release verification.
- [ ] Add a maintainer-facing release verification path that confirms the staged release artifact, LaunchAgent install, runtime host overview, and MCP initialize flow all agree.
- [ ] Add a Mac mini to MacBook LAN audio smoke path that installs or refreshes the mini LaunchAgent, confirms the MacBook receiver is advertised and listening, sends a small generated-audio stream with the shared token, and verifies local receiver playback without running the full real-model E2E matrix.
- [ ] Update server release automation so SemVer prerelease tags create GitHub prerelease objects and existing prerelease release objects are verified before the flow proceeds; keep the broader reusable repo-tooling followup tied to Socket issue [#61](https://github.com/gaelic-ghost/socket/issues/61).

### Exit Criteria

- [ ] A maintainer can refresh the live LaunchAgent and prove HTTP plus MCP readiness without ad hoc curl or one-off JSON-RPC scripts.

## Milestone 15: Toolchain Repro And Upstream Follow-Through

### Status

Planned

### Scope

- [ ] Turn the standalone Swiftly-selected Swift 6.3 `_NumericsShims` failure into a small, reportable reproduction that distinguishes toolchain behavior from this package's source layout.

### Tickets

- [ ] Build a minimal reproduction that distinguishes the standalone Swiftly-selected Swift 6.3 toolchain failure from the matching Xcode toolchain success.
- [ ] Capture the exact module-loading boundary that turns the wider package graph into a `_NumericsShims` failure so the issue report is concrete instead of anecdotal.
- [ ] Decide whether to file the repro upstream against the standalone Swift 6.3 toolchain, SwiftPM module loading, or a specific dependency once the minimal failing graph is proven.

### Exit Criteria

- [ ] The repo either has an upstream issue link with a minimal repro or a documented reason the local guidance should keep using Xcode's selected Swift toolchain.

## Milestone 16: Package Hardening Follow-Through

### Status

In Progress

### Scope

- [ ] Finish the remaining hardening work after the install, lifecycle, configuration, transport, and documentation passes that made the staged LaunchAgent release path deterministic.

### Tickets

- [ ] Audit the playback and device-observation surface that still logs `freed pointer was not the last allocation`, confirm whether the warning comes from runtime-owned audio observation or server-owned integration behavior, and either fix the root cause or narrow the server boundary so the remaining ownership is explicit.

### Exit Criteria

- [ ] The playback/device warning has a verified owner, and either the fix or the documented boundary is reflected in maintainer notes.

## Milestone 17: Agent And Operator Workflows

### Status

In Progress

### Scope

- [ ] Make the repo's agent-facing workflows intentional enough that Codex and other coding agents can use the service, hooks, and package APIs without reverse-engineering local prototypes.

### Tickets

- [ ] Add a maintained repo-local "use this with Codex hooks" guide or skill so operators can enable, understand, and validate the speech-hook workflow without reverse-engineering the prototype files.
- [ ] Improve Codex Hooks setup filtering so hook guidance, doctor output, and repair plans separate actionable Speak Swiftly hook entries from unrelated Codex hooks, structured metadata skips, continuation skips, and stale development-harness noise.
- [ ] Reproduce Codex Desktop plugin-bundled `Stop` hook dispatch from Gale's personal scope by uninstalling and reinstalling `speak-swiftly@socket`, confirming whether plugin-managed hooks fire without a user-level `Stop` hook, and documenting the exact refresh boundary and Codex behavior.
- [ ] Investigate a ChatGPT Apps SDK connector path for Speak Swiftly that exposes the server's MCP surface over HTTPS for explicit "speak this text/reply" actions, with a self-hosted Cloudflare Tunnel or equivalent setup path documented for users who want ChatGPT access to their local Mac speech service.
- [ ] Document the current boundary between Codex hook-driven automatic spoken replies, ChatGPT MCP-tool-driven spoken replies, and native app-managed install/update flows so users and their agents know which surface can actually install, update, or speak automatically.
- [ ] Add package-building skills that help people's agents embed `SpeakSwiftlyServer`, choose HTTP versus MCP versus `EmbeddedServer`, configure profile roots safely, and validate the resulting app or tool against the repo's public contract.
- [ ] Add operator-facing LAN receiver guidance and commands for generating a local shared token, enabling or disabling receiver mode, validating Bonjour advertisement, and explaining that receiver changes require a service reload.
- [ ] Add sender-side LAN output workflow guidance so operators can list discovered receivers, choose a receiver for remote playback, and understand when generated speech is played locally versus streamed to another Mac.

### Exit Criteria

- [ ] Agent guidance covers both operating this local service and building with the Swift package from another project.

## Milestone 18: Codex Plugin Catalog Split

### Status

In Progress

### Scope

- [ ] Finish the standalone-versus-Socket marketplace split so this repository remains the canonical plugin payload while Socket can catalog it without copying an active subtree.

### Tickets

- [ ] Decide whether the current `socket/plugins/SpeakSwiftlyServer` subtree should remain as a pull-only source mirror after Socket lists the remote plugin payload, or whether future `socket` releases can rely on this standalone repository plus the remote marketplace entry.

### Exit Criteria

- [ ] Standalone and Socket install docs agree on one source-of-truth payload model, with any remaining mirror role named explicitly.

## Milestone 19: Default Voice Setup Simplification

### Status

Planned

### Scope

- [ ] Simplify the default voice configuration and setup story now that `swift-signal` and `swift-anchor` install automatically from package-owned seeds.

### Tickets

- [ ] Review the relationship between `APP_DEFAULT_VOICE_PROFILE_NAME`, startup-installed built-ins, user-owned saved profiles, and fallback `-builtin` names.
- [ ] Re-evaluate the current built-in voice quality, especially the slightly wonky `swift-signal` default, and decide whether the bundled seed prompts, source text, or sample-selection workflow need another tuning pass.
- [ ] Decide whether the server should expose a clearer operator command, config default, or MCP guidance for choosing one of the built-ins after startup seeding.
- [x] Use upstream `SpeakSwiftly` system-authored profile metadata for startup-installed built-ins instead of creating them through the ordinary user-profile design path.
- [x] Keep ordinary profile reads list-and-select for system built-ins by redacting seed source text and voice-design prompts from normal encoded profile JSON.
- [x] Add an explicit maintainer/development MCP tool for inspecting built-in voice seed internals.
- [ ] Update README, API, LaunchAgent docs, plugin skills, and tests so the default voice setup path is easy to explain and does not require users to understand seed-install internals first.

### Exit Criteria

- [ ] A fresh install has one documented, low-friction path from first launch to choosing and verifying a default voice.

## Milestone 20: Public API Simplification

### Status

In Progress

### Scope

- [ ] Reduce public API confusion across Swift, HTTP, MCP, and docs by deduplicating shared state models first, then making the MCP surface resources-first for read-only inspection while preserving compatibility for existing callers.

### Tickets

- [x] Deduplicate playback and queue snapshot shaping so `EmbeddedServer`, HTTP responses, and MCP resources encode shared host state from one set of primitives instead of parallel app-facing and transport-facing models.
- [x] Add focused tests that prove playback state, queue state, and active request fields stay equivalent across Swift app state, HTTP responses, and MCP resources after the snapshot cleanup.
- [x] Update `docs/maintainers/source-layout.md` and the public API simplification plan when model ownership moves.
- [x] Make MCP guidance resources-first immediately after the snapshot cleanup: prefer `speak-swiftly://overview` and specific `speak-swiftly://...` resources for read-only status, and reserve tools as the preferred path for queueing, mutation, and destructive actions.
- [x] Update `API.md`, README guidance, MCP guide resources, and `choose_surface_action` prompt text so agents do not have to choose blindly between read-only tools and matching resources.
- [x] Rename MCP resource URIs from the generic `speak://` scheme to `speak-swiftly://`, and flatten runtime reads to `speak-swiftly://overview`, `speak-swiftly://status`, and `speak-swiftly://configuration`.
- [x] Add target-model HTTP text-profile replacement routes so HTTP can follow MCP's optional `profile_id` targeting model.
- [x] Add one preferred cancellation path across HTTP and MCP: `DELETE /requests/{request_id}` and `cancel_request`, each with optional generation/playback scope.
- [x] Add preferred runtime-configuration MCP tools (`get_runtime_configuration`, `set_runtime_configuration`).
- [x] Decide the next-major generated-artifact target shape: replace generated file/batch read families with one artifact read family (`GET /generation/artifacts`, `GET /generation/artifacts/{artifact_id}`, and matching `speak-swiftly://generation/artifacts` resources) without compatibility aliases.
- [x] Implement generated artifact unification as a breaking major-version change by replacing generated file/batch read routes, tools, and resources with one artifact read family.
- [x] Remove remaining next-major compatibility aliases: older active/stored text-profile replacement routes, scoped HTTP cancel routes, scoped MCP cancel tools, staged runtime-configuration MCP tools, and nested `/runtime/...` HTTP routes.
- [x] Adopt the `SpeakSwiftly 5.0.0-rc.1` / `TextForSpeech 0.19.0` request and text-profile model directly: remove server-local speech normalization context shaping, keep `source_format` as the one explicit request format field, merge `cwd` and `repo_root` into shared `SpeakSwiftly.RequestContext`, and delete the text-profile JSON bridge adapter.
- [x] Add the `generation_location` request shape across HTTP, MCP, and host APIs with local generation as the default.
- [x] Add first-pass remote generation routing so a local server can call another `SpeakSwiftlyServer` for `/speech/stream`, decode HTTP-framed canonical chunks, and feed them to local playback or the selected LAN receiver.
- [ ] Keep any `EmbeddedServer` surface widening separate and explicit; no `EmbeddedServer` widening until a concrete embedded consumer needs it.
- [ ] Add client compatibility-gated MCP progress updates so newer clients can subscribe to direct request/playback progress notifications without breaking existing MCP clients that only expect resource-updated notifications and retained request resources.
- [x] Add first-pass remote generation hardening by gating `/speech/stream` behind `app.remoteGeneration.allowRemoteStreamRequests` and a shared token header that is separate from LAN receiver playback tokens.
- [x] Propagate remote generation cancellation from the caller server to the generator server when a host-owned remote request is cancelled.
- [x] Add token-safe `remote_generation` overview status with stream enablement, token-presence, token-header, and active outbound request count.
- [ ] Add remaining remote generation hardening: LAN receiver token/operator UX for non-local playback and deeper in-flight stream details when the next smoke tests show which fields operators actually need.
- [ ] Expand transport snapshots for `network_audio_receiver` and future LAN sender state with receiver service names, selected endpoint metadata, active stream counts, and recent failure messages that are useful to operators without exposing shared tokens.

### Exit Criteria

- [ ] The first public read path is clear for agents and operators, duplicate shared-state models are removed or explicitly justified, and deferred compatibility-sensitive cleanup is documented without leaving hidden transitional behavior behind.

## Milestone 21: Repo-Wide Security Audit Follow-Through

### Status

Planned

### Scope

- [ ] Close the addressable findings from the 2026-05-12 repo-wide security audit while preserving the package's intentional trusted-local HTTP, MCP, embedded, LaunchAgent, and Codex hook model.

### Tickets

- [ ] Constrain transport-facing voice-profile file inputs so `reference_audio_path` and `output_path` cannot read from or write to arbitrary service-account filesystem paths unless the caller is using an explicit operator-only surface.
- [ ] Replace manual YAML rendering for persisted runtime configuration with structured scalar-safe output, or centralize escaping and validation for every interpolated persisted value.
- [ ] Add MCP session and subscription budgets, including active-session caps, idle cleanup, per-session subscription caps, URI length limits, and dynamic-resource existence checks where appropriate.
- [ ] Redact or gate Codex stop-hook diagnostic previews so message text, transcript paths, and full payloads are not persisted by default without an explicit diagnostic opt-in.
- [ ] Decide and document whether retained request history is intentionally shared across trusted local clients; if not, attach client/session ownership to retained jobs and filter list/detail/SSE reads.
- [ ] Review transport-facing runtime snapshots for path and error disclosure, then redact, compact, or move full path diagnostics behind an explicit operator diagnostics surface.
- [ ] Add a startup guard or explicit unsafe-mode warning for unauthenticated HTTP or MCP bindings on non-loopback interfaces.

### Exit Criteria

- [ ] The audit report's validated findings are either fixed, explicitly accepted as trusted-local behavior, or moved to a documented diagnostics-only surface with tests and API/MCP guidance updated.

## Backlog Candidates

- [ ] Revisit the near-future Apple-platform reuse path after the macOS package and embedded server surface have more downstream app mileage.
- [ ] Turn upstream `SpeakSwiftly` into a clearer product-level package surface so `SpeakSwiftlyServer` can depend on stable, ergonomic runtime concepts instead of carrying extra server-side explanation, translation, or compatibility planning for package-owned behavior.
- [ ] Revisit whether `EmbeddedServer` should stay a narrow app-facing live-control model or grow retained artifact, text-profile editing, generation-job, and request-detail APIs.
- [ ] Add a focused Codex Hooks setup skill for `SpeakSwiftlyServer` after stop-hook text filtering is improved, likely in `TextForSpeech`, so hook-triggered TTS can be set up safely without teaching agents to speak tables, metadata, or stale stop-hook payloads.
- [ ] Explore whether SayBar should become the native Mac install/update center for Speak Swiftly, including App Store distribution, ServiceManagement-managed helpers, Codex hook/plugin repair flows, and a guided ChatGPT connector/self-host setup.

## History

- Completed the bootstrap, HTTP server, direct `SpeakSwiftly` integration, core testing, library integration, app/LaunchAgent handoff, live-update convergence, formatting/linting, initial DocC, and plugin-catalog split setup milestones.
- Completed the config reload foundation: YAML reload providers, malformed-reload survival, live host-safe subset application, and restart-required diagnostics.
- Completed the `SpeakSwiftly` runtime adoption passes for explicit `vibe`, runtime configuration exposure, Marvis/Qwen E2E realignment, source/test splitting, voice rename and reroll, retained generation artifacts, generation jobs, batch generation, and README/API/E2E coverage.
- Completed the embedded lifecycle refactor around explicit service ownership.
- Completed the first live-service hardening passes: staged-artifact promotion diagnostics, signature refresh, operator healthcheck, transport smoke split, lifecycle shutdown accounting, persisted runtime-state hardening, and package-wide cleanup.
- Completed the Codex plugin identity migration from `speak-swiftly-server` to `speak-swiftly`, Git-backed standalone and Socket marketplace docs, legacy duplicate detection, doctor dry-run repair planning, and isolated plugin install-testing guidance.
- Added public built-in voice samples for `swift-signal` and `swift-anchor` under `docs/media/default-voices/` after the package-owned seed voices shipped.
- Moved system-authored built-in voice handling into the upstream `SpeakSwiftly` authorship model and kept deep seed inspection behind an explicit maintainer/tool surface.
- Recorded the public API simplification audit and ordered the cleanup plan around snapshot dedupe first, MCP resources-first guidance second, and compatibility-sensitive route/tool cleanup later.
- Added a future ChatGPT Apps SDK and SayBar productization investigation so spoken ChatGPT replies, self-hosted MCP access, and native install/update ownership can be evaluated explicitly.
