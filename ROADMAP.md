# ROADMAP

## Current Roadmap Baseline

- [x] Document the app-managed install and configuration contract the macOS app will rely on.
- [x] Decide and document how app-managed installs own logs, profile roots, and cache paths.
- [x] Trim the roadmap so the remaining unchecked items are clearly split between shipped work and active follow-up work.
- [x] Default Codex plugin install and update docs to the Git-backed marketplace add/upgrade path, with manual local clone marketplaces kept as development and fallback guidance.
- [x] Point default plugin install docs at the release-aligned branch without an explicit ref, document the optional `socket` marketplace path, and add Codex GUI follow-through guidance.

## Milestone 1: Bootstrap And Repo Hygiene

- [x] Scaffold the Swift executable package.
- [x] Add project-level guidance in `AGENTS.md`.
- [x] Write an initial `README.md` that reflects the real current state.
- [x] Add a project license.
- [x] Replace the placeholder executable body with the first real server startup path.

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

- [x] Split the SpeakSwiftly package so it vends a reusable library product alongside its executable product.
- [x] Switch this package from subprocess-style integration to direct `SpeakSwiftly` package import when that library product exists.
- [x] Collapse temporary integration-only scaffolding that became unnecessary after direct import.
- [x] Align the runtime bridge with the public `SpeakSwiftly` library surface instead of constructing raw worker requests across the library boundary.
- [x] Re-align this package with the repackaged `SpeakSwiftly` plus direct `TextForSpeech` dependency surface so `xcrun swift build` and `xcrun swift test` work against the current package graph again.
- [x] Adopt the updated `SpeakSwiftly.Runtime.speak(..., textProfileName:textContext:id:)` signature and remove assumptions about older normalization-only entrypoints.
- [x] Add the new voice-clone creation flow across host, HTTP, MCP, and tests.
- [x] Expose the new text-profile inspection and editing helpers across HTTP and MCP with a transport model that stays distinct from stored voice-profile jobs.
- [x] Keep the public speech submission surface aligned with the evolving `SpeakSwiftly` library API, including stored text-profile selection on one-shot speech requests.
- [x] Expand MCP prompts and resources so downstream apps and agents get first-class guidance for authoring and using SpeakSwiftly text profiles and replacements.
- [x] Remove any remaining server-local transport translation that `SpeakSwiftly` can now express directly without making the server harder to reason about.
- [x] Re-check the host bridge and docs against the current sibling `SpeakSwiftly` public library surface.

## Milestone 6: App And LaunchAgent Handoff

- [x] Document the app-managed install and configuration contract the forthcoming macOS app will need.
- [x] Add any server-side hooks needed for LaunchAgent-friendly lifecycle management.
- [x] Decide how logs, profile roots, and cache paths should be configured and owned for app-managed installs.
- [x] Add one explicit runtime profile-root override model across embedded sessions, direct `serve` runs, and LaunchAgent installs, and thread that override through to `SpeakSwiftly` startup.
- [x] Prepare an initial tagged release once the service is meaningfully usable.

## Milestone 7: Live Update Convergence

- [x] Decide how much of the existing `GET /jobs/{job_id}/events` SSE route should stay job-specific versus begin consuming the shared host event surface.
- [x] Converge HTTP SSE onto the host event model selectively, only where it removes bespoke stream plumbing without losing clear per-job semantics.
- [x] Revisit whether playback-job MCP resources have become natural shared-host concepts after the adjacent `SpeakSwiftly` API layer stabilizes.
- [x] Re-evaluate whether any standalone MCP prompt-catalog concepts still earn migration once the shared host update model is more mature.
- [x] Define explicit live config reload boundaries only after the transport and event surfaces stop shifting.

## Milestone 8: Config Reload Policy

Current note: these are important transport-policy decisions, but they are not blocking the current package state.

- [x] Adopt `swift-configuration` reloading providers for YAML-backed server config.
- [x] Keep malformed reloads non-fatal so the watcher survives bad file edits.
- [x] Apply the safe host-level subset live through `ServerHost`.
- [x] Surface restart-required config changes through the shared recent-error model.
- [ ] Decide whether transport bind settings should remain restart-only permanently or earn a coordinated live-rebind model later.

## Milestone 9: Formatting And Linting

Current note: repo-discipline and CI-hardening work, not a current product-correctness blocker.

- [x] Add SwiftFormat configuration and a maintainer-facing formatting command.
- [x] Decide whether SwiftLint should join SwiftFormat as a required local and CI check.
- [x] Wire the chosen formatting and linting checks into repo-maintenance validation and GitHub Actions.

## Milestone 10: Swift Package Index Readiness

Current note: distribution polish for discovery and packaging, not a current release blocker.

- [x] Add a project `.spi.yml` file with an intentionally minimal initial configuration.
- [x] Re-check README, package metadata, and release guidance against Swift Package Index expectations after `.spi.yml` lands.
- [x] Add a first DocC catalog and the initial package-level article set described in `docs/maintainers/docc-spi-hosting-plan.md`.
- [x] Add a deliberately small executable-oriented companion article set for `SpeakSwiftlyServerTool` without duplicating the full repository operator docs.
- [x] Add the short tutorial-style walkthrough described in `docs/maintainers/docc-spi-hosting-plan.md` so the hosted docs have a concrete embedded-session first-use path.
- [x] Add a DocC build check both locally through `scripts/repo-maintenance/validate-all.sh` and in GitHub Actions before the package is submitted to Swift Package Index.
- [ ] Submit the package to Swift Package Index once the package metadata and hosted DocC surface are ready for public indexing.

## Milestone 11: SpeakSwiftly 3.x Surface Adoption

Current note: this milestone tracks the server-side adoption work for the newer `SpeakSwiftly` runtime surface. The older 3.x migration is complete; remaining items are follow-on parity and shaping work on top of the current 4.x package line.

- [x] Carry explicit `vibe` through the existing profile and clone creation surfaces instead of preserving the older implicit-profile behavior as the server moved onto the newer `SpeakSwiftly` runtime surface.
- [x] Expose the persisted `SpeakSwiftly.Configuration` surface across host state, HTTP, and MCP so operators can inspect and change the active speech backend without reaching into the runtime process manually.
- [x] Debug the queued-Marvis live playback E2E stall in `httpMarvisQueuedLivePlaybackDrainsInOrder`, including the stuck first request terminal state and the generation-versus-playback ordering mismatch captured in `docs/maintainers/e2e-marvis-queued-live-investigation.md`.
- [x] Re-check the server against Gale's `SpeakSwiftly` simplification work and delete the remaining local queue, playback, and host-state inference that upstream now exposes directly through the atomic runtime overview.
- [x] Split the oversized host, model, and mixed route-test sources into concern-focused files and refresh the maintainer docs around that layout so future cleanup does not regrow monoliths.
- [x] Finish the operator-control E2E realignment so it uses the renamed HTTP surface consistently and validates long live playback with varied text instead of repeated-sentence filler.
- [x] Re-run the full live E2E suite after the resource-bundling and transport-surface realignment updates and verify the renamed MCP surface and operator-control flows end to end.
- [x] Bump the resolved `SpeakSwiftly` dependency through the newer 4.x package state, including the matching `TextForSpeech` compatibility updates that follow from that runtime surface.
- [x] Expose `runtime.voices.rename(_:to:)` and `runtime.voices.reroll(_:)` across host, HTTP, MCP, docs, and controlled-runtime tests.
- [x] Add generated-file reads across host, HTTP, MCP, and shared resources so saved artifacts can be listed and fetched through the server instead of only inside the sibling library.
- [x] Add generation-job reads and expiry controls across host, HTTP, MCP, and shared resources so persisted file and batch jobs can be inspected and managed directly.
- [x] Add batch-generation submission plus batch-read surfaces across host, HTTP, MCP, and shared resources, including artifact-id shaping and the existing text-format / source-format context support for each batch item.
- [ ] Revisit server-local job and snapshot shaping so the new immediate generation-control operations and persisted generation-job reads map directly to runtime concepts instead of keeping legacy server-only wrappers around them.
- [x] Expand README, MCP tool docs, shared resources, and opt-in live E2E coverage so `marvis` vs `qwen3`, explicit `vibe`, generated files, generation jobs, and batch generation are all documented and verified end to end.

## Milestone 12: Standalone Read-Model Parity

Current note: the embedded-session path now has the clearest app-facing read model through `ServerState`. This milestone tracks bringing the standalone executable and tool-owned path up to parity so foreground operators and app-owned wrappers do not have to reason about two different state stories.

- [ ] Decide what the standalone parity surface actually is: structured stdout, a local file-backed snapshot surface, a first-class CLI inspection command family, or another typed repo-owned read-model lane.
- [ ] Expose the same core shared-host snapshot families the embedded path already projects, including host overview, queue state, playback state, runtime configuration, transport state, recent errors, jobs, and voice-profile cache state.
- [ ] Keep the standalone read model sourced from the same `ServerHost` snapshot and event machinery the embedded, HTTP, and MCP paths already use instead of adding a second inference path.
- [ ] Re-check whether any embedded-only naming or shaping in `ServerState` should move down into a more shared read-model primitive before the standalone parity surface lands.
- [ ] Document the final parity boundary clearly across embedded sessions, the foreground executable, HTTP, and MCP so operators know which surface to reach for when they need the current shared host picture.

## Milestone 13: SpeakSwiftly 3.x Follow-On Consideration

Current note: these are intentionally deferred adoption candidates from the broader `SpeakSwiftly 3.x` runtime surface. They are worth revisiting after the current release ships, but they are not required to make the present server release coherent.

- [x] Refactor the embedded-session lifecycle around explicit `Service`-shaped host, config-watch, and MCP services owned by one outer `ServiceGroup`, as outlined in `docs/maintainers/embedded-service-lifecycle-plan.md`.
- [ ] Decide whether the runtime's request-update and generation-event stream surfaces should gain first-class HTTP and MCP exposure, or whether the retained request snapshots remain the cleaner operator contract.
- [ ] Revisit whether text-profile persistence state, repair, and storage diagnostics need a more explicit operator-facing surface than the current snapshot plus load/save controls.
- [ ] Decide whether any newer voice-profile maintenance operations beyond create, clone, list, rename, reroll, and delete belong in the public server contract or should stay library-only until a downstream operator use case is concrete.

## Milestone 14: Live Service Reliability And Testing Ergonomics

Post-`v2.0.4` note: these items capture the next hardening pass after the LaunchAgent config-path repair. Detailed maintainer guidance lives in `docs/maintainers/live-service-reliability-follow-ups.md`.

- [ ] Add an app-managed LaunchAgent smoke test that starts from a canonical config path with spaces and verifies both `GET /runtime/host` and MCP `initialize`.
- [ ] Add explicit startup logging for canonical config paths, LaunchAgent alias staging, and the exact config file path the runtime loader opened.
- [x] Add a first-class operator health-check command that verifies HTTP and MCP transport health without ad hoc curl or one-off JSON-RPC scripts.
- [ ] Decide whether LaunchAgent-owned startup config should keep using a reloading provider or move to a simpler startup-open path with reload support layered on intentionally later.
- [ ] Promote the existing MCP E2E client utilities into a reusable repo-owned smoke helper for local checks, CI, and release verification.
- [ ] Add a maintainer-facing release verification path that confirms the staged release artifact, LaunchAgent install, runtime host overview, and MCP initialize flow all agree.
- [x] Split transport smoke coverage more clearly from long audible-playback E2E coverage so failures localize faster.

## Milestone 15: Toolchain Repro And Upstream Follow-Through

Current note: repo-local guidance and automation now prefer `xcrun swift ...` because the standalone Swiftly-selected Swift 6.3 toolchain currently reproduces a transitive `_NumericsShims` module-loading failure during full-package SwiftPM builds that does not reproduce under Xcode's selected toolchain.

- [ ] Build a minimal reproduction that distinguishes the standalone Swiftly-selected Swift 6.3 toolchain failure from the matching Xcode toolchain success.
- [ ] Capture the exact module-loading boundary that turns the wider package graph into a `_NumericsShims` failure so the issue report is concrete instead of anecdotal.
- [ ] Decide whether to file the repro upstream against the standalone Swift 6.3 toolchain, SwiftPM module loading, or a specific dependency once the minimal failing graph is proven.

## Milestone 16: Package Hardening Passes

Current note: this milestone turns the live-service reliability work into a package-wide hardening program. The first confirmed live fixes were promoting commit `7e651f8` into the LaunchAgent-backed service, removing the old prune-maintenance crash loop from the live runtime, and discovering that in-place staged-artifact refreshes can still trip a launchd code-signing failure unless the staged executable's ad-hoc signature is refreshed intentionally.

- [x] Harden the install and release surface so staged-artifact refreshes are deterministic, the required signature or provenance handling is explicit, the live-service promotion path is first-class, and operator-facing diagnostics make LaunchAgent boot failures obvious.
- [ ] Audit the playback and device-observation surface that still logs `freed pointer was not the last allocation`, confirm whether the warning comes from runtime-owned audio observation or server-owned integration behavior, and either fix the root cause or narrow the server boundary so the remaining ownership is explicit.
- [x] Continue the lifecycle hardening pass by moving any remaining long-lived maintenance loops, watchers, or retained background tasks under explicit service ownership and shutdown accounting instead of freestanding task bodies.
- [x] Harden configuration and persisted runtime state handling, including precedence rules, atomic writes, corruption or repair behavior, runtime-configuration persistence, and test isolation for profile-root-sensitive state.
- [x] Harden the HTTP and MCP transport surface with clearer readiness policy, stronger request validation and operator-facing errors, reusable smoke coverage, and release verification that proves the staged live service can answer both transport health checks.
- [x] Finish the full hardening program with a package-wide review, quick fixes discovered during the passes, and a cleanup sweep across docs, tests, and maintainer tooling.

## Milestone 17: Codex Hooks And Operator Workflow

Current note: the repo already has a working local Codex hooks prototype for
Stop-hook speech and notify payload inspection. This milestone tracks turning
that into a more intentional operator-facing workflow instead of a one-off
prototype.

- [x] Re-check the repo-local Codex hook scripts against the current official Codex hooks event shapes and stable-path guidance.
- [ ] Add a maintained repo-local "use this with Codex hooks" guide or skill so Gale can enable, understand, and validate the speech-hook workflow without reverse-engineering the prototype files.

## Milestone 18: Codex Plugin Catalog Split

Current note: this repository now ships a working plugin-managed Codex hook
surface. Long-term plugin distribution should keep one canonical plugin payload
instead of copying the same manifest, hooks, skills, guidance, and doctor into
both this repository and `socket`. Codex users should be able to install
`Speak Swiftly` from either the standalone `SpeakSwiftlyServer` marketplace or
the broader `socket` marketplace, while app embedders use this repository as the
Swift package directly.

- [x] Keep this repository as the canonical source of truth for the `speak-swiftly` Codex plugin payload: `.codex-plugin/plugin.json`, `.mcp.json`, `hooks/`, `skills/`, user guidance, migration notes, and the doctor or install-check scripts.
- [x] Rename the plugin id from `speak-swiftly-server` to `speak-swiftly` while keeping the display name `Speak Swiftly`.
- [x] Keep this repository as the Swift package, executable, LaunchAgent, embedded API, HTTP/MCP implementation, and authoritative API documentation source.
- [x] Keep the repo-local marketplace functional so users can run `codex plugin marketplace add gaelic-ghost/SpeakSwiftlyServer` and enable `Speak Swiftly` from this standalone catalog.
- [x] Update `socket` marketplace docs and validation so the Socket catalog lists `speak-swiftly` by Git-backed reference to `gaelic-ghost/SpeakSwiftlyServer` instead of installing from the full local `socket/plugins/SpeakSwiftlyServer` subtree mirror.
- [x] Keep repo-local `.codex/` files clearly scoped to development and hook-payload testing rather than the end-user install path.
- [x] Add migration notes for old `speak-swiftly-server` installs from either marketplace, including how to enable `speak-swiftly` and when the old entry is safe to disable or remove.
- [x] Update `scripts/codex-hooks-doctor.mjs` so it detects legacy `speak-swiftly-server` installs, duplicate installs or enablement from both marketplaces, plugin-managed hook state, live service reachability, and expected voice-profile availability.
- [x] Add a doctor dry-run repair plan that prefers the Socket marketplace when both catalogs are configured: keep `speak-swiftly@socket` enabled, then report duplicate standalone-marketplace or legacy enablement before any future config mutation.
- [ ] Decide whether the current `socket/plugins/SpeakSwiftlyServer` subtree should remain as a pull-only source mirror after Socket lists the remote plugin payload, or whether future `socket` releases can rely on this standalone repository plus the remote marketplace entry.

Current Socket-side state:

- [x] `socket/.agents/plugins/marketplace.json` lists `speak-swiftly` as a Git-backed root plugin source using `source: "url"`, `url: "https://github.com/gaelic-ghost/SpeakSwiftlyServer.git"`, and `ref: "main"`.
- [x] `socket/scripts/validate_socket_metadata.py` accepts `local`, `url`, and `git-subdir` marketplace source kinds. Local entries still get filesystem and manifest checks; Git-backed entries get source-shape checks.
- [x] Socket docs now describe this repository as the canonical Speak Swiftly plugin payload owner.

Implementation notes for this repository:

- [x] Update `.codex-plugin/plugin.json` from `name: "speak-swiftly-server"` to `name: "speak-swiftly"`. Keep `interface.displayName` as `Speak Swiftly`, and update description text only where it still implies the plugin identity is server-specific rather than user-facing.
- [x] Update `.agents/plugins/marketplace.json` so the standalone marketplace entry is `speak-swiftly`, still pointing at `./` because this repository root is the plugin root.
- [x] Update README, AGENTS, maintainer docs, and skills guidance where user-facing install instructions say to enable `speak-swiftly-server`. Keep migration wording for existing users who still see the old id.
- [x] Update `scripts/codex-hooks-doctor.mjs` constants and checks that currently assume `pluginName = "speak-swiftly-server"` or config table `[plugins."speak-swiftly-server@socket"]`.
- [x] Teach the doctor to inventory both old and new plugin ids across installed cache manifests and `~/.codex/config.toml`, including `speak-swiftly@socket`, `speak-swiftly@SpeakSwiftlyServer`, `speak-swiftly-server@socket`, and `speak-swiftly-server@SpeakSwiftlyServer`.
- [x] Add a dry-run repair mode before any config mutation. The repair plan should report the active entries, prefer `speak-swiftly@socket` when present, and only then offer to disable duplicate standalone or legacy entries.
- [x] Keep HTTP and MCP endpoint behavior unchanged during the plugin identity migration. The Socket-side entry targets this repository's root plugin payload; it does not change the local service URL, `.mcp.json`, hook command path, or LaunchAgent behavior.
- [ ] Validate the identity migration with `node scripts/codex-hooks-doctor.mjs`, a focused doctor test if added, and the repo's normal docs or maintainer validation path. Do not run live LaunchAgent or E2E service operations unless the implementation actually changes live-service behavior.
