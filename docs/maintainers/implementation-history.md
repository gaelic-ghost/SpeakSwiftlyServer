# Implementation History

This note consolidates completed implementation plans that no longer need to live as separate active roadmap files. Keep it short and evidence-oriented: the current source of truth is the code, `API.md`, [`source-layout.md`](source-layout.md), and [`speakswiftly-api-coverage-matrix.md`](speakswiftly-api-coverage-matrix.md).

## Host And Transport Consolidation

The server moved from a mostly HTTP-shaped host toward one shared host model that can serve embedded apps, HTTP, MCP, and operator state without duplicating backend ownership.

Completed phases:

- Phase 1 split the runtime-owning backend into `ServerHost` and kept `ServerState` as the app-facing observable projection.
- Phase 2 introduced shared host-native snapshots for overview, transports, queues, playback, current jobs, and recent errors.
- Phase 3 adopted typed configuration loading and coalesced host-side runtime refresh behavior.
- Phase 5 added compact host events beside stable snapshots so HTTP, MCP, and app consumers could observe meaningful changes without treating `ServerState` as a server event bus.
- Phase 6 moved job-specific HTTP SSE replay and follow behavior onto the shared host event backbone.
- Phase 7 added YAML reload support, safe live config application, and restart-required reporting for values that cannot be changed in place.

The lasting architecture rule from those phases is simple: `ServerHost` owns runtime and transport truth, `ServerState` mirrors app-facing state, and HTTP or MCP surfaces should shape transport responses without becoming separate sources of truth.

## Public API Simplification

The public API simplification work reduced duplicate route, tool, resource, and response choices while preserving useful compatibility surfaces.

Completed decisions:

- Prefer MCP resources for read-only inspection and tools for commands or mutations.
- Keep top-level MCP runtime resources under `speak-swiftly://overview`, `speak-swiftly://status`, and `speak-swiftly://configuration`.
- Keep read-only MCP tools such as `get_runtime_overview` and `get_runtime_status` as compatibility read tools, with descriptions pointing clients toward resources first.
- Collapse cancellation around `DELETE /requests/{request_id}` and `cancel_request`, with optional queue scope only when the caller needs protection.
- Prefer `runtime configuration` wording, with `active_*`, `next_*`, `persisted_*`, and `environment_*_override` fields carrying the precise state.
- Move retained generated output reads toward one generation artifact family instead of separate file and batch read families.
- Use shared playback and queue snapshot primitives across embedded state and transport envelopes where possible.
- Keep `EmbeddedServer` intentionally narrower than HTTP and MCP unless app consumers need broader artifact or text-profile editing APIs.

The current API comparison lives in [`speakswiftly-api-coverage-matrix.md`](speakswiftly-api-coverage-matrix.md). The current transport contract lives in [`../../API.md`](../../API.md).

## Built-In Voices And Media

The default voice work moved built-in voice policy toward upstream-owned `SpeakSwiftly` semantics:

- default voices are package resources and installed as system-authored profiles
- ordinary users list and select built-ins like other profiles
- maintainer-only seed internals stay behind explicit development or repair surfaces
- generated media and seed documentation live under `docs/media`

The current maintainer note is [`default-voices-and-media-options.md`](default-voices-and-media-options.md).

## Application Support Config

The LaunchAgent-backed service now uses the canonical Application Support config path directly:

- active server config: `~/Library/Application Support/SpeakSwiftlyServer/server.yaml`
- runtime config and text profile state: under the durable runtime Application Support tree
- package defaults: copied only when operator-owned config is missing

The old copied config alias was a compatibility repair for paths containing spaces. The current model treats `Application Support` as the normal durable config root.

## Runtime Profile Root Threading

The runtime profile root override was made explicit across embedded sessions, foreground serve runs, and LaunchAgent installs:

- embedded apps use `EmbeddedServerSession.Options.runtimeProfileRootURL`
- foreground operator runs can use `serve --profile-root`
- LaunchAgent installs can use `launch-agent install --profile-root`
- all surfaces continue to bridge through the shared `SPEAKSWIFTLY_PROFILE_ROOT` override understood by `SpeakSwiftly`

This kept startup ownership policy out of live-reload YAML config.

## Embedded Lifecycle Composition

The embedded service lifecycle cleanup made package-owned long-running work visible at the service boundary:

- host startup and shutdown
- config watch lifetime
- optional MCP lifecycle and readiness
- Hummingbird application runtime

The key result is a flatter embedded runtime model: package services are lifecycle-managed services instead of hidden work inside one retained orchestration task.

## DocC And Hosted Docs

The package now includes a DocC catalog for the `SpeakSwiftlyServer` library product plus narrative articles for embedding, app-managed install layout, operator surfaces, first embedded session usage, and the command-line or LaunchAgent workflows.

SPI-hosted docs remain centered on the library target because that is the surface Swift Package Index can document naturally. Operator and transport detail stays in `README.md`, `API.md`, and maintainer docs.
