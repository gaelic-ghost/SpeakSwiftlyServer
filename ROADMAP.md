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
- [x] Switch the server to direct typed `SpeakSwiftlyCore` import instead of subprocess-backed integration.
- [x] Surface operator-facing startup, readiness, and worker failure details clearly.
- [x] Support profile cache refresh and reconciliation behavior after profile mutations.
- [ ] Compare downstream response payload expectations in adjacent consumers and close any remaining contract mismatches.

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
- [x] Align the runtime bridge with the public `SpeakSwiftly v0.8.1` helper surface instead of constructing raw worker requests across the library boundary.
- [ ] Re-verify that adjacent consumers still agree with the current public HTTP API surface.
- [ ] Remove any remaining server-local translation code that `SpeakSwiftlyCore` can now express directly without making the server harder to reason about.

## Milestone 6: App And LaunchAgent Handoff

- [ ] Document the server configuration contract the forthcoming macOS app will need.
- [ ] Add any server-side hooks needed for LaunchAgent-friendly lifecycle management.
- [ ] Decide how logs, profile roots, and cache paths should be configured for app-managed installs.
- [x] Prepare an initial tagged release once the service is meaningfully usable.
