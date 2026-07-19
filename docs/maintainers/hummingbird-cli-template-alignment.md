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
- HTTP assembly is centralized in `buildHTTPApplication`.
- Request handling uses `BasicRequestContext`, matching the default template's context model.
- HTTP application construction maps the typed `HTTPConfig` into Hummingbird's
  `ApplicationConfiguration(reader:)` initializer.
- HTTP applications use `LogRequestsMiddleware(.info)`, which logs request method and
  path without request bodies or headers.

Intentionally different:

- `SpeakSwiftlyServer` is both a library product and an executable tool, not a single generated `App` executable.
- `SSSCore`, `SSSHTTP`, and `SSSMCP` preserve transport boundaries; Hummingbird remains isolated to the HTTP/MCP edge modules.
- The executable has a repo-owned command parser because it also manages LaunchAgent install, healthcheck, and foreground serve workflows.
- HTTP configuration is read into `AppConfig` and `HTTPConfig` before app assembly so embedded sessions, LaunchAgent mode, config reloads, and runtime listener toggles share one typed server state model.
- `buildHTTPApplication` accepts lifecycle services and `beforeServerStarts` hooks because the server coordinates runtime readiness, HTTP listener state, LAN audio, MCP readiness, and embedded app observation.

## Evaluated Alignment Decisions

- Keep the package split into `SSSCore`, `SSSHTTP`, `SSSMCP`, `SpeakSwiftlyServer`,
  and `SpeakSwiftlyServerTool`. This is a durable building-block boundary, not a
  template mismatch: it keeps Hummingbird out of core runtime state and preserves
  the public library plus executable shape.
- Use Hummingbird's `ApplicationConfiguration(reader:)` at the HTTP edge, but feed it
  from already-validated `HTTPConfig`. This avoids a duplicate source of truth while
  matching the framework's configuration construction path.
- Use Hummingbird's `LogRequestsMiddleware(.info)` with default body/header-free
  logging. Route-specific logs still own operation metadata such as accepted speech
  request IDs and replay events.
- Prefer `buildHTTPApplication` over the generated template's plain
  `buildApplication(reader:)` name because this repository has non-HTTP lifecycle
  entrypoints too. The name keeps the transport boundary visible.
- Keep `swift-configuration` traits aligned with repo guidance: `.defaults`,
  `CommandLineArguments`, `YAML`, and `Reloading`.

## Streamlining Candidates

Good next candidates:

- Move shared transport snapshot and queue response DTOs toward upstream
  `SpeakSwiftly` library APIs when those types describe runtime state rather than
  server transport state.
- Keep looking for server-local inference that can disappear once the public `SpeakSwiftly`
  runtime or normalization API can express the concept directly. This is especially relevant for
  playback, request observation, and text-profile normalization state.
- Consider a small `HTTPApplicationOptions` value only if more builder inputs become
  coupled. Do not add it while the current parameter list remains the clearer shape.
- Review config key naming after the Hummingbird alignment settles. The current
  `app.*` root is intentional because it includes runtime, MCP, LAN audio, and
  LaunchAgent state, but `app.http` and `app.listeners.localhost` should stay clearly
  documented as legacy-compatible versus current listener configuration.

Avoid:

- Do not collapse the package into the generated single-target `Sources/App` shape; it would erase the public library, HTTP/MCP edge, and core-runtime boundaries this repo depends on.
- Do not move Hummingbird dependencies into `SSSCore`; `SSSCore` should remain transport-independent.
- Do not replace the tool command parser with the generated `@main App` entrypoint unless LaunchAgent and operator workflows are redesigned first.
