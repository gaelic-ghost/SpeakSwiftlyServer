# ROADMAP

## Milestone 1: Bootstrap And Repo Hygiene

- [x] Scaffold the Swift executable package.
- [x] Add project-level guidance in `AGENTS.md`.
- [x] Write an initial `README.md` that reflects the real current state.
- [ ] Add a project license.
- [x] Replace the placeholder executable body with the first real server startup path.
- [ ] Add package formatting and linting tooling such as SwiftFormat and/or SwiftLint.

## Milestone 2: Hummingbird HTTP Server

- [x] Add Hummingbird as the HTTP server dependency.
- [x] Implement a localhost server configuration model for host, port, and runtime settings.
- [x] Implement `GET /healthz`.
- [x] Implement `GET /readyz`.
- [x] Implement `GET /status`.
- [x] Implement `GET /profiles`.
- [x] Implement `POST /profiles`.
- [x] Implement `DELETE /profiles/{profile_name}`.
- [x] Implement `POST /speak`.
- [x] Implement `GET /queue/generation`.
- [x] Implement `GET /queue/playback`.
- [x] Implement `GET /playback`.
- [x] Implement `POST /playback/pause`.
- [x] Implement `POST /playback/resume`.
- [x] Implement `DELETE /queue`.
- [x] Implement `DELETE /queue/{request_id}`.
- [x] Implement `GET /jobs/{job_id}`.
- [x] Implement `GET /jobs/{job_id}/events`.
- [x] Implement SSE heartbeats and replay behavior for the app-facing job stream.

## Milestone 3: SpeakSwiftly Integration

- [x] Decide and implement the first integration path to `SpeakSwiftly`.
- [x] Switch the server to direct typed `SpeakSwiftly` import instead of subprocess-backed integration.
- [x] Surface operator-facing startup, readiness, and worker failure details clearly.
- [x] Support profile cache refresh and reconciliation behavior after profile mutations.
- [x] Keep the standalone HTTP and MCP contracts aligned with the current in-repo host model even when no downstream consumer repository exists yet.

## Milestone 4: Testing And Verification

- [x] Replace the generated placeholder test with real package coverage.
- [x] Add unit tests for configuration and settings loading.
- [x] Add unit tests for in-memory job retention and pruning.
- [x] Add route tests for health, readiness, profile, and job endpoints.
- [x] Add SSE tests for initial worker status replay, progress history, and keep-alive behavior.
- [x] Add end-to-end verification against a real `SpeakSwiftly` runtime.
- [x] Add an opt-in end-to-end verification path that exercises real playback instead of silent playback.
- [x] Add failure-path tests for worker startup failure before the runtime ever becomes ready.
- [x] Add failure-path tests for runtime degradation while queued live speech is still in flight.

## Milestone 5: Library Integration Follow-Through

- [x] Split `../SpeakSwiftly` so it vends a reusable library product alongside its executable product.
- [x] Switch this package from subprocess-style integration to direct `SpeakSwiftly` package import when that library product exists.
- [x] Collapse temporary integration-only scaffolding that became unnecessary after direct import.
- [x] Align the runtime bridge with the public `SpeakSwiftly` library surface instead of constructing raw worker requests across the library boundary.
- [x] Re-align this package with the repackaged `SpeakSwiftly` plus direct `TextForSpeech` dependency surface so `swift build` and `swift test` work against the current sibling checkout again.
- [x] Adopt the updated `SpeakSwiftly.Runtime.speak(..., textProfileName:textContext:id:)` signature and remove assumptions about older normalization-only entrypoints.
- [x] Add the new voice-clone creation flow across host, HTTP, MCP, and tests.
- [x] Expose the new text-profile inspection and editing helpers across HTTP and MCP with a transport model that stays distinct from stored voice-profile jobs.
- [x] Keep the public speech submission surface aligned with the evolving `SpeakSwiftly` library API, including stored text-profile selection on one-shot speech requests.
- [x] Expand MCP prompts and resources so downstream apps and agents get first-class guidance for authoring and using SpeakSwiftly text profiles and replacements.
- [x] Remove any remaining server-local transport translation that `SpeakSwiftly` can now express directly without making the server harder to reason about.
- [x] Re-check the host bridge and docs against the current sibling `SpeakSwiftly` public library surface.

## Milestone 6: App And LaunchAgent Handoff

- [ ] Document the server configuration contract the forthcoming macOS app will need.
- [ ] Add any server-side hooks needed for LaunchAgent-friendly lifecycle management.
- [ ] Decide how logs, profile roots, and cache paths should be configured for app-managed installs.
- [x] Prepare an initial tagged release once the service is meaningfully usable.

## Milestone 7: Live Update Convergence

- [x] Decide how much of the existing `GET /jobs/{job_id}/events` SSE route should stay job-specific versus begin consuming the shared host event surface.
- [x] Converge HTTP SSE onto the host event model selectively, only where it removes bespoke stream plumbing without losing clear per-job semantics.
- [x] Revisit whether playback-job MCP resources have become natural shared-host concepts after the adjacent `SpeakSwiftly` API layer stabilizes.
- [x] Re-evaluate whether any standalone MCP prompt-catalog concepts still earn migration once the shared host update model is more mature.
- [x] Define explicit live config reload boundaries only after the transport and event surfaces stop shifting.

## Milestone 8: Config Reload Policy

- [x] Adopt `swift-configuration` reloading providers for YAML-backed server config.
- [x] Keep malformed reloads non-fatal so the watcher survives bad file edits.
- [x] Apply the safe host-level subset live through `ServerHost`.
- [x] Surface restart-required config changes through the shared recent-error model.
- [ ] Decide whether transport bind settings should remain restart-only permanently or earn a coordinated live-rebind model later.
