# Hummingbird CLI Template Alignment

Last checked: 2026-06-24

This note records the Hummingbird CLI and template baseline used when aligning
`SpeakSwiftlyServer` with current Hummingbird project practice.

## Sources Checked

- Hummingbird framework repository: <https://github.com/hummingbird-project/hummingbird>
- Hummingbird documentation: <https://docs.hummingbird.codes/>
- `hb` CLI repository: <https://github.com/hummingbird-project/hb>
- Hummingbird template repository: <https://github.com/hummingbird-project/template>

Observed versions:

- Hummingbird latest GitHub release: `v2.25.0`, published 2026-05-29.
- `hb` latest GitHub release: `0.3.1`, published 2026-06-17.
- `hb init --default` downloaded template release `2.6.0`, published 2026-06-13.

## Generated Template Shape

The released `hb` default server template generates:

- Swift tools version `6.3`.
- A single executable target at `Sources/App`.
- `swift-configuration` with `.defaults` and `CommandLineArguments`.
- A `ConfigReader` built from command-line arguments, environment variables, `.env`, and in-memory defaults.
- `buildApplication(reader:) -> some ApplicationProtocol`.
- `Application(configuration: ApplicationConfiguration(reader: reader.scoped(to: "http")))`.
- A typed `Router<BasicRequestContext>`.
- `LogRequestsMiddleware(.info)`.
- Tests using `HummingbirdTesting` and `app.test(.router)`.

The template's released manifest still declares Hummingbird from `2.0.0`, while
the Hummingbird repository's current install guidance and template `main` point
at the current `2.25.0` release line. For this package, the practical alignment
baseline is the current Hummingbird release resolved in `Package.resolved`, not
the broad lower-bound used by new-project scaffolding.

## SpeakSwiftlyServer Alignment

Aligned:

- Swift tools version is `6.3`.
- Hummingbird is resolved at `2.25.0`.
- HTTP tests already use `HummingbirdTesting`.
- The package uses `swift-configuration` as the configuration foundation.
- HTTP assembly is centralized in `assembleHBApp`.
- Request handling uses `BasicRequestContext`, matching the default template's context model.

Intentionally different:

- `SpeakSwiftlyServer` is both a library product and an executable tool, not a single generated `App` executable.
- `SSSCore`, `SSSHTTP`, and `SSSMCP` preserve transport boundaries; Hummingbird remains isolated to the HTTP/MCP edge modules.
- The executable has a repo-owned command parser because it also manages LaunchAgent install, healthcheck, and foreground serve workflows.
- HTTP configuration is read into `AppConfig` and `HTTPConfig` before app assembly so embedded sessions, LaunchAgent mode, config reloads, and runtime listener toggles share one typed server state model.
- `assembleHBApp` accepts lifecycle services and `beforeServerStarts` hooks because the server coordinates runtime readiness, HTTP listener state, LAN audio, MCP readiness, and embedded app observation.

## Alignment Candidates

Good next candidates:

- Consider a public/internal `buildApplication`-style wrapper around `assembleHBApp` if it makes tests, docs, or operator entrypoints clearer without hiding the `ServerHost` dependency.
- Evaluate whether `ApplicationConfiguration(reader:)` can replace direct `ApplicationConfiguration(address:)` inside `assembleHBApp` without weakening the existing typed `HTTPConfig` validation and live reload model.
- Keep `LogRequestsMiddleware` under review. Add it only if it produces useful operator logs without duplicating existing request/error logging or making speech payloads noisy.
- Keep `swift-configuration` traits aligned with repo guidance: `.defaults`, `CommandLineArguments`, `YAML`, and `Reloading`.

Avoid:

- Do not collapse the package into the generated single-target `Sources/App` shape; it would erase the public library, HTTP/MCP edge, and core-runtime boundaries this repo depends on.
- Do not move Hummingbird dependencies into `SSSCore`; `SSSCore` should remain transport-independent.
- Do not replace the tool command parser with the generated `@main App` entrypoint unless LaunchAgent and operator workflows are redesigned first.
