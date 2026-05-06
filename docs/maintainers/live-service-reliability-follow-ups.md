# Live Service Reliability Follow-Ups

## Context

- Date captured: `2026-04-10`
- Trigger: the live LaunchAgent-backed service exposed healthy HTTP on `127.0.0.1:7337`, but the MCP transport stayed disabled until the service was reinstalled with a real config file.
- Immediate repair status: fixed in `v2.0.4`.
- `2026-04-15` follow-on note: promoting the lifecycle fix from commit `7e651f8` into the live LaunchAgent-backed service also exposed a second promotion fragility. Reinstalling the LaunchAgent against a freshly overwritten staged executable failed with `OS_REASON_CODESIGNING` until the staged tool's ad-hoc signature was refreshed explicitly, even though the binary itself still verified on disk.

## Root Cause Summary

The live service had two separate issues that combined into one confusing operator symptom:

1. The LaunchAgent had previously been installed without an explicit config handoff, so the service fell back to built-in defaults and kept the MCP transport disabled.
2. Once a real config file was supplied, the older config-loading path failed when the path pointed at `~/Library/Application Support/SpeakSwiftlyServer/server.yaml`, because that path contains spaces.

The `v2.0.4` fix kept the canonical config file in Application Support, but staged a copied LaunchAgent-owned alias config under `~/Library/Caches/SpeakSwiftlyServer/launch-agent-server.yaml` whenever the canonical path contained spaces. The LaunchAgent environment pointed at that cache copy instead of the spaced canonical path.

The `v4.3.4` follow-up moves that alias to `~/Library/SpeakSwiftlyServer/launch-agent-server.yaml`. The alias still avoids the `Application Support` space that exposed the original config-provider bug, but it no longer depends on a cache directory that macOS or maintenance tooling can remove independently of the installed LaunchAgent plist.

The Application Support cleanup is implemented on the `runtime/application-support-config` branch. It treats the alias as a temporary compatibility shim and moves the target design back to direct `~/Library/Application Support/SpeakSwiftlyServer/server.yaml` loading, with install/refresh seeding the canonical file from a bundled default when needed.

## Reliability Follow-Ups

### 1. Add a full LaunchAgent smoke test for the real per-user install layout

The current unit coverage now proves that LaunchAgent installs pass `serve --config-file ... --profile-root ...` directly, even when the canonical Application Support config path contains spaces. That should be extended into an end-to-end smoke test that verifies the whole tool-managed install contract, not only the argument shaping.

The intended flow is:

- create a temporary per-user style install layout whose canonical config file lives under an `Application Support` path with spaces
- run the LaunchAgent install path against the staged release artifact
- confirm that the installed property list uses the canonical Application Support config path
- confirm that install/refresh seeds the canonical config when it is missing
- boot the service
- probe `GET /overview`
- probe MCP `initialize` over `POST /mcp`
- confirm that both HTTP and MCP are actually live before the test exits

That test should fail for any future regression where:

- the canonical config is not seeded during install/refresh
- the property list stops pointing at the spaced canonical path
- the service starts but the MCP transport silently falls back to disabled

### 2. Make config-path staging and config-open behavior visible in operator logs

The current fix is operationally correct, but it still asks a maintainer to infer too much from side effects. Startup logs should say exactly which config path the service intended to use and whether a default config was seeded.

Add explicit log lines for:

- canonical config path requested for LaunchAgent install
- canonical config path selected for LaunchAgent use
- whether the canonical config was seeded or already present
- the exact config path the runtime config loader is opening at startup
- whether config reload watching is enabled for that path

If the config file cannot be opened, the error should name:

- the path that failed
- whether it was the canonical path or an explicit custom path
- whether the file existed
- one likely cause, such as a missing file, permissions problem, or provider/path handling bug

### 3. Add a first-class health-check command for the live service

The current operator workflow still requires ad hoc curl and one-off JSON-RPC commands to answer the basic question, "is the live service fully up?".

Add a supported command such as:

- `swift run SpeakSwiftlyServerTool healthcheck`

That command should:

- probe the HTTP surface
- read the runtime host overview
- verify whether HTTP is listening
- verify whether MCP is listening
- optionally run an MCP `initialize` request against the live `/mcp` endpoint
- print one concise success or failure summary

The output should be short enough for operators to use interactively, but specific enough to disambiguate:

- service unreachable
- HTTP up but MCP disabled by config
- HTTP up and MCP advertised, but MCP initialize failing
- service healthy on both transports

Status update on `2026-04-15`: this is now shipped as `xcrun swift run SpeakSwiftlyServerTool healthcheck`. The command probes `GET /healthz`, reads `GET /overview`, sends a real MCP `initialize` request to `/mcp`, and handles the current streaming-style MCP initialize response instead of assuming a plain JSON body.

### 4. Revisit whether LaunchAgent-owned config needs a reloading provider

Status update: the package now keeps reload behavior, but uses `swift-configuration`'s `FileProvider<YAMLSnapshot>` for YAML loading and a small Foundation URL-backed monitor for file-change detection. `swift-configuration` still owns the reader, precedence behavior, YAML snapshot parsing, and value lookup shape; only path-sensitive file monitoring stays server-local because `ReloadingFileProvider<YAMLSnapshot>` currently treats Application Support paths with spaces as missing after symlink resolution.

### 5. Add explicit self-reporting for transport policy at startup

The runtime host overview already reports whether HTTP and MCP are listening, but a maintainer currently has to poll the running service to learn that. The service should also emit a startup summary that makes the transport policy obvious in logs.

That startup summary should include:

- whether HTTP is enabled
- whether MCP is enabled
- the advertised bind address for HTTP
- the advertised bind address for MCP
- whether any requested transport change was rejected as restart-required

This should make "MCP disabled because config never loaded" visible within the first seconds of startup, without asking the operator to discover it indirectly.

### 6. Make staged-artifact promotion and signature handling explicit

Today's live promotion showed that `launch-agent install` is not the same operation as "promote the currently checked-out code into the live service". Older `launch-agent install` rewrote or refreshed the property list and bootstrapped launchd, but still ran whichever binary already lived at `.release-artifacts/current/SpeakSwiftlyServerTool`.

Status update: the default `launch-agent install` path now builds and stages the current checkout before writing and bootstrapping the LaunchAgent. Explicit `--tool-executable-path` installs still use the caller-provided executable without overwriting it.

That leaves one easy operator trap:

- a source-level fix can be merged and validated locally
- an explicit `--tool-executable-path` install can be rerun successfully
- the live service can still come back on an older custom executable unless that explicit executable is refreshed first

The package should make that boundary explicit and first-class:

- keep the default `install` path as the supported all-in-one refresh path instead of relying on manual file copies
- document whether staged artifacts must be re-signed after in-place refreshes and encode that behavior in the supported path instead of making it a tribal-knowledge repair
- emit operator-facing output that names the exact staged executable path and modification time that the LaunchAgent install is about to activate
- add verification that the live running process, the staged artifact, and the intended source build all agree on the same executable revision

If the right long-term answer is "never mutate `.release-artifacts/current` in place", then the package should say that clearly and steer operators toward a safer staged-directory swap model instead.

## Testing And Tooling Follow-Ups

### 1. Promote the embedded MCP test harness into a reusable smoke client

The repository already has good MCP testing primitives in:

- `Tests/SpeakSwiftlyServerTransportE2ETests/E2EMCPClient.swift`
- `Tests/SpeakSwiftlyServerTransportE2ETests/E2EMCPEventStream.swift`
- `Tests/SpeakSwiftlyServerTransportE2ETests/E2EServerProcess.swift`

Those should be promoted into a small shared maintainer utility or executable test helper so the same code path can be reused for:

- local smoke checks
- CI smoke checks
- release verification
- future LaunchAgent validation

That is better than rebuilding the same `initialize`, session-id, and event-stream logic in multiple shell or Python probes.

### 2. Keep MCP Inspector as the manual-debug surface, not the automation surface

The project should keep [MCP Inspector](https://modelcontextprotocol.io/docs/tools/inspector) documented as the preferred manual interactive debugging tool for the live HTTP MCP surface.

Recommended live command:

```bash
npx -y @modelcontextprotocol/inspector --transport http --server-url http://127.0.0.1:7337/mcp
```

But Inspector should stay in the "operator investigation" lane, not become the only regression tool. Automated coverage should continue to live in Swift tests and repo-owned smoke helpers so releases do not depend on browser-driven tooling.

### 3. Keep release-owned live-service refresh tied to transport health verification

Status: implemented in the standard release path. The release script now validates the repo, opens and merges the release PR, fast-forwards local `main`, creates and publishes the versioned tag, creates the GitHub release object, updates the LaunchAgent-backed live service from the synced local `main` checkout, and runs `SpeakSwiftlyServerTool healthcheck`.

Keep this release-owned check covering:

- LaunchAgent install using the staged release artifact
- HTTP runtime overview probe
- MCP initialize probe
- verification that the staged release artifact and live LaunchAgent agree on the intended config path

Use `--skip-live-service-update` only when the current machine should not be updated by that release or when another checkout will perform the live promotion.

### 4. Tighten E2E separation between transport coverage and playback-heavy runtime coverage

This cleanup is now done in the package-owned live suite. The standalone server target no longer tries to duplicate SpeakSwiftly's broader worker-owned audible, queue-drain, clone, and Marvis workflow coverage.

The current repo-owned live E2E contract is intentionally small:

- one HTTP smoke test that proves the server can boot the published runtime, answer readiness, accept one real request, and retain the completed request snapshot
- one MCP smoke test that proves the MCP bridge can initialize, emit at least one resource update, accept one real request, and retain the completed request snapshot

That leaves playback-heavy runtime behavior, queue semantics, clone specifics, and model-routing behavior owned by `SpeakSwiftly` itself, where failures are easier to interpret and cheaper to iterate on.

The remaining follow-through here is mostly discipline:

- keep the server package live suite transport-owned
- avoid regrowing playback-heavy or model-specific assertions in this repo unless the server itself adds a new transport contract
- keep the smoke cases pointed at the actual shipped HTTP and MCP names so release verification still proves the operator surface we publish
- keep E2E preflight focused on live-service memory headroom by unloading resident models before tests and reloading them afterward; do not remove the installed LaunchAgent service for test setup

## Suggested Tracking Order

If these follow-ups are tackled incrementally, the highest-value order is:

1. LaunchAgent smoke test with spaced config path plus HTTP and MCP probes.
2. Keep the resident-model unload/reload E2E preflight aligned with the current live-service helper.
3. Staged-artifact promotion hardening, including the all-in-one install path and any required re-sign behavior.
4. First-class live service health-check command.
5. Better startup and config-open logging.
6. Reusable repo-owned MCP smoke helper.
7. Config reload architecture decision for LaunchAgent-owned startup files.

## Package-Wide Hardening Pass Order

The broader package hardening program should now follow this order:

1. Install and release surface hardening.
   This includes staged-artifact refresh, LaunchAgent promotion semantics, signature handling, release verification, and operator-facing install diagnostics.
2. Playback and device-observation hardening.
   The recurring `freed pointer was not the last allocation` warning still needs a focused ownership audit even though the prune-maintenance crash loop is now fixed in the live service. The current audit result is that this package did own one startup-ordering issue: `SpeakSwiftlyRuntimeAdapter.start()` used an untracked fire-and-forget task, so `ServerHost.start()` did not actually wait for runtime startup. That race is now fixed here by making the runtime start path truly awaitable. The remaining `playback_output_device_observed` event and eager playback-engine preparation still originate upstream from `SpeakSwiftly.Runtime.start()` -> `startResidentPreload()` -> `playbackController.prepare(...)` with no active request, so any deeper audio-hardware or preload policy change belongs in `SpeakSwiftly` unless this server later chooses a different readiness model intentionally.
3. Host lifecycle and background-work hardening.
   This local pass is now complete. The package-owned shutdown gap was the accepted-request monitor path in `ServerHost`, which was still spawning retained request-consumer tasks without explicit lifecycle accounting. That is now fixed locally: request-monitor tasks are tracked as host-owned state, cancelled during shutdown, and drained before the host finishes tearing the runtime down. Keep any future retained maintenance or watch behavior under the same explicit service ownership model instead of reintroducing long-lived freestanding task loops.
4. Configuration and persisted runtime-state hardening.
   Re-check precedence, reload boundaries, corruption handling, atomic writes, persisted runtime configuration, and test isolation around profile-root-sensitive state.
5. HTTP and MCP transport hardening.
   Tighten readiness semantics, validation, reusable smoke coverage, and release-owned transport verification once the lower-level host and install surfaces are stable enough to trust.
6. Package-wide review, quick fixes, and cleanup.
   Close the loop with an explicit final review, small fixes surfaced during the passes, and the usual documentation, test, and maintainer-tool cleanup sweep.
