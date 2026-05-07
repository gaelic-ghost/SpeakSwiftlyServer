# Embedded Session Concurrency Review

## Purpose

This note records the embedded-session concurrency review that happened before the next minor
release cut, with a specific focus on app-owned startup and shutdown behavior.

The review question was:

- when a sandboxed macOS app embeds `SpeakSwiftlyServer`, are we accidentally doing startup work on
  the main actor that should stay concurrent and off the UI executor?

It also records the follow-on evaluation of `swift-server/swift-service-lifecycle` for this
library surface.

## Findings

### 1. The real host and runtime ownership were already mostly healthy

The core runtime layers were already off-main:

- `ServerHost` is an actor and owns transport, runtime, and state publication.
- runtime startup passes the resolved state root directly into `SpeakSwiftly.liftoff(...)`.
- the UI-facing `ServerState` publish hop is already narrow and explicit, using `MainActor.run`
  only for the final observable snapshot assignment.

That part matched the intended ownership model:

- host and runtime orchestration off-main
- UI snapshot projection on-main

### 2. The embedded bootstrap path was still too main-actor-owned

Before the correction, `EmbeddedServerSession` itself was `@MainActor`, which meant the embedded
startup path was also main-actor-isolated.

That pulled the following startup work through the app's UI executor:

- `ServerConfigStore` creation
- config loading
- `ServerHost.live(...)`
- `SpeakSwiftly.liftoff(...)`
- `MCPSurface.build(...)`
- Hummingbird `Application` assembly
- initial transport-start state marking

This was the highest-priority concurrency issue for embedded app owners.

### 3. Shutdown and action plumbing also carried unnecessary main-actor coupling

The old `LifecycleHooks` model stored stop and wait closures as `@MainActor`, and the
`ServerState.Actions` closures also carried `@MainActor`.

That did not mean the underlying host work was wrong, but it did make the API surface imply that
transport and runtime control were UI-owned when the real ownership boundary is `ServerHost`.

## Documentation Basis

The concurrency review was grounded in:

- Apple Swift documentation for `MainActor`, which states that the main actor's executor is
  equivalent to the main dispatch queue.
- Apple Swift documentation for actors and serial executors, which states that ordinary actors run
  on the shared global concurrency pool by default.
- `swift-server/swift-service-lifecycle` upstream docs:
  - `Adopting ServiceLifecycle in libraries`
  - `Adopting ServiceLifecycle in applications`
  - the package README and `ServiceGroup` source

## Correction Implemented In This Pass

### EmbeddedSession ownership split

The embedded session wrapper now keeps only the app-facing observable state on the main actor.

The heavy bootstrap path is no longer main-actor-isolated:

- `EmbeddedServerSession` itself is no longer `@MainActor`
- `EmbeddedServerSession.start(...)` now creates `ServerState` with an explicit `MainActor.run`
  hop, then performs bootstrap work off-main
- the session instance uses a small internal `StopCoordinator` actor so shutdown can stay
  concurrency-safe without re-isolating the whole wrapper to the main actor

### Lifecycle hook cleanup

`LifecycleHooks.requestStop` and `LifecycleHooks.waitUntilStopped` are now plain `@Sendable`
closures instead of `@MainActor` closures.

That keeps shutdown orchestration aligned with the real owner of the work rather than forcing the
UI executor to be the lifecycle owner.

### Action isolation cleanup

`ServerState.Actions` no longer marks its closures as `@MainActor`.

`ServerState` itself remains `@MainActor`, because it is the UI-facing observable projection, but
the action closures now more accurately reflect that the underlying work belongs to `ServerHost`.

## ServiceLifecycle Evaluation

### What we are already using well

This package now uses `ServiceLifecycle` in the more explicit shape we wanted for the embedded
path:

- one outer embedded-session `ServiceGroup` owns package-level host lifecycle, optional config
  watching, optional MCP lifecycle, and the wrapped Hummingbird application as sibling services
- Hummingbird still uses its own internal `ServiceGroup` for application-local services
- the standalone and embedded entrypoints now both benefit from structured shutdown sequencing
  through explicit service ownership instead of hidden task bodies

That matches the upstream `ServiceLifecycle` docs, which position:

- `Service` as the protocol reusable libraries should adopt for long-running work
- `ServiceGroup` as the application-side orchestration surface

### Why it does not solve the main actor issue directly

The main actor issue was not caused by missing `ServiceGroup` adoption.

It was caused by where the library's embedded bootstrap entrypoint itself was isolated.
Rewriting the embedded startup path around more `ServiceLifecycle` types would not, by itself,
move bootstrap work off the main actor.

### What the follow-on refactor changed

That follow-on service-lifecycle pass is now landed:

- host startup and shutdown run through `HostLifecycleService`
- config watching runs through `ConfigWatchService`
- MCP readiness and drain run through `MCPLifecycleService`
- Hummingbird startup is gated by `beforeServerStarts(...)`
- the retained embedded run task is now mostly just the top-level join handle for the outer group

That keeps the main actor fix and the service-lifecycle cleanup as separate decisions:

- the main actor issue was solved by moving embedded bootstrap off `MainActor`
- the later composition cleanup made package-owned long-running work flatter and easier to reason
  about without turning `ServerState` into a service or hiding ownership inside the HTTP layer

## Checklist

- [x] Record the concurrency findings in maintainer docs.
- [x] Move embedded bootstrap work off the main actor while keeping `ServerState` main-actor-owned.
- [x] Remove unnecessary `@MainActor` coupling from lifecycle hooks.
- [x] Narrow the action-plumbing isolation so host work is not modeled as UI-owned.
- [x] Land the follow-on `ServiceLifecycle` composition pass for host, config-watch, and MCP
      lifecycle cleanup. The completed design summary now lives in
      `docs/maintainers/implementation-history.md`.
