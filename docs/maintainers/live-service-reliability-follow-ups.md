# Live Service Reliability Follow-Ups

## Context

- Date captured: `2026-04-10`
- Trigger: the live LaunchAgent-backed service exposed healthy HTTP on `127.0.0.1:7337`, but the MCP transport stayed disabled until the service was reinstalled with a real config file.
- Immediate repair status: fixed in `v2.0.4`.

## Root Cause Summary

The live service had two separate issues that combined into one confusing operator symptom:

1. The LaunchAgent had been installed without `APP_CONFIG_FILE`, so the service fell back to built-in defaults and kept the MCP transport disabled.
2. Once a real config file was supplied, the current config-loading path failed when `APP_CONFIG_FILE` pointed at `~/Library/Application Support/SpeakSwiftlyServer/server.yaml`, because that path contains spaces.

The `v2.0.4` fix keeps the canonical config file in Application Support, but stages a copied LaunchAgent-owned alias config under `~/Library/Caches/SpeakSwiftlyServer/launch-agent-server.yaml` whenever the canonical path contains spaces. The LaunchAgent environment now points at that cache copy instead of the spaced canonical path.

## Reliability Follow-Ups

### 1. Add a full LaunchAgent smoke test for the real per-user install layout

The existing unit coverage now proves that LaunchAgent installs rewrite `APP_CONFIG_FILE` to the cache alias when the canonical config path contains spaces. That should be extended into an end-to-end smoke test that verifies the whole app-managed install contract, not only the environment shaping.

The intended flow is:

- create a temporary per-user style install layout whose canonical config file lives under an `Application Support` path with spaces
- run the LaunchAgent install path against the staged release artifact
- confirm that the installed property list uses the alias config path instead of the canonical path
- boot the service
- probe `GET /runtime/host`
- probe MCP `initialize` over `POST /mcp`
- confirm that both HTTP and MCP are actually live before the test exits

That test should fail for any future regression where:

- the alias copy is not staged
- the property list keeps pointing at the spaced canonical path
- the service starts but the MCP transport silently falls back to disabled

### 2. Make config-path staging and config-open behavior visible in operator logs

The current fix is operationally correct, but it still asks a maintainer to infer too much from side effects. Startup logs should say exactly which config path the service intended to use and whether an alias copy was staged.

Add explicit log lines for:

- canonical config path requested for LaunchAgent install
- alias config path selected for LaunchAgent use
- whether the alias path was copied or left untouched
- the exact config path the runtime config loader is opening at startup
- whether config reload watching is enabled for that path

If the config file cannot be opened, the error should name:

- the path that failed
- whether it was the canonical path or the LaunchAgent alias path
- whether the file existed
- one likely cause, such as a missing file, a stale alias copy, or a provider/path handling bug

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

### 4. Revisit whether LaunchAgent-owned config needs a reloading provider

The current server config path uses `swift-configuration` reloading providers for YAML-backed config, which is the right long-term default for operator-edited config files. It is less clear that the LaunchAgent-owned startup config path needs the same behavior when the practical requirement is "start reliably from a known file under the app-managed layout".

The project should make an explicit decision here instead of inheriting that behavior accidentally:

- keep the reloading provider for LaunchAgent config and harden the file-path behavior further
- or split startup config loading from live reload watching so LaunchAgent startup uses a simpler file-open path and optional later reload support is layered on top

Before changing architecture, verify the documented `swift-configuration` behavior being relied on and confirm whether the path-with-spaces failure came from the provider stack itself or from the way this package integrates with it.

### 5. Add explicit self-reporting for transport policy at startup

The runtime host overview already reports whether HTTP and MCP are listening, but a maintainer currently has to poll the running service to learn that. The service should also emit a startup summary that makes the transport policy obvious in logs.

That startup summary should include:

- whether HTTP is enabled
- whether MCP is enabled
- the advertised bind address for HTTP
- the advertised bind address for MCP
- whether any requested transport change was rejected as restart-required

This should make "MCP disabled because config never loaded" visible within the first seconds of startup, without asking the operator to discover it indirectly.

## Testing And Tooling Follow-Ups

### 1. Promote the embedded MCP test harness into a reusable smoke client

The repository already has good MCP testing primitives in:

- `Tests/SpeakSwiftlyServerE2ETests/E2EMCPClient.swift`
- `Tests/SpeakSwiftlyServerE2ETests/E2EMCPEventStream.swift`
- `Tests/SpeakSwiftlyServerE2ETests/E2EServerProcess.swift`

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

### 3. Extend the release-owned live-service refresh into transport health verification

The release script now validates the repo, fails fast if the requested tag does not already match `HEAD`, builds the release artifact, stages `.release-artifacts/current`, tags, pushes, creates the GitHub release object, and refreshes the live LaunchAgent-backed service from that staged artifact by default. It still does not verify that the refreshed live service can actually boot from the staged artifact with both transports healthy.

Add a maintainer-facing release checklist or release helper step that covers:

- LaunchAgent install using the staged release artifact
- runtime host overview probe
- MCP initialize probe
- verification that the staged release artifact and live LaunchAgent agree on the intended config path

This does not have to block every local release immediately, but it should become the standard post-tag validation path for the live accessibility service.

### 4. Tighten E2E separation between transport coverage and playback-heavy runtime coverage

The existing E2E suite already does valuable live runtime coverage, but some failures mix transport correctness and long-running speech-runtime behavior together. That makes it harder to tell whether a broken run is an MCP bug, an HTTP bug, a playback-drain bug, or a general runtime stall.

Future cleanup should split those concerns more deliberately:

- transport smoke coverage that proves HTTP and MCP surfaces can start, initialize, and serve basic reads
- operator-control coverage that validates queue and playback mutations
- heavy audible playback coverage that focuses on runtime behavior without doubling as a transport smoke test

That split should reduce debugging time when live tests fail and make release health easier to assess quickly.

## Suggested Tracking Order

If these follow-ups are tackled incrementally, the highest-value order is:

1. LaunchAgent smoke test with spaced config path plus HTTP and MCP probes.
2. First-class live service health-check command.
3. Better startup and config-open logging.
4. Reusable repo-owned MCP smoke helper.
5. Config reload architecture decision for LaunchAgent-owned startup files.
