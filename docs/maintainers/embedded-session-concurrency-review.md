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
- `SpeakSwiftlyRuntimeLauncher` is an actor and keeps the temporary startup-environment bridge
  serialized.
- the UI-facing `ServerState` publish hop is already narrow and explicit, using `MainActor.run`
  only for the final observable snapshot assignment.

That part matched the intended ownership model:

- host and runtime orchestration off-main
- UI snapshot projection on-main

### 2. The embedded bootstrap path was still too main-actor-owned

Before the correction, `EmbeddedServerSession` itself was `@MainActor`, which meant the embedded
startup path was also main-actor-isolated.

That pulled the following startup work through the app's UI executor:

- `ConfigStore` creation
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

This package already uses `ServiceLifecycle` in a reasonable, application-shaped way:

- `ServiceGroup` is used to run the Hummingbird application and any config-provider services
- the current embedded and standalone entrypoints already benefit from structured shutdown
  sequencing through that group

That matches the upstream `ServiceLifecycle` docs, which position:

- `Service` as the protocol reusable libraries should adopt for long-running work
- `ServiceGroup` as the application-side orchestration surface

### Why it does not solve the main actor issue directly

The main actor issue was not caused by missing `ServiceGroup` adoption.

It was caused by where the library's embedded bootstrap entrypoint itself was isolated.
Rewriting the embedded startup path around more `ServiceLifecycle` types would not, by itself,
move bootstrap work off the main actor.

### Could we broaden ServiceLifecycle usage later?

Yes, but it should be a separate design decision.

The most plausible future broadening would be to make some package-owned long-running components
more explicitly `Service`-shaped, such as:

- an MCP lifecycle wrapper
- a configuration-watch wrapper
- a higher-level library-owned embedded runtime bundle

That could make composition cleaner if the embedded library surface grows more long-running owned
subsystems.

That follow-on decision is now recorded in:

- `docs/maintainers/embedded-service-lifecycle-plan.md`

### Recommendation

For the release-facing concurrency pass, fixing `EmbeddedServerSession` isolation directly was the
right first move.

For the follow-on composition pass, the package now has a recorded plan to:

- keep one outer embedded-session `ServiceGroup`
- promote host lifecycle, config watching, and MCP readiness into explicit `Service`-shaped
  components
- keep `ServerState` as the app-facing `@MainActor` projection instead of treating it as a service

## Checklist

- [x] Record the concurrency findings in maintainer docs.
- [x] Move embedded bootstrap work off the main actor while keeping `ServerState` main-actor-owned.
- [x] Remove unnecessary `@MainActor` coupling from lifecycle hooks.
- [x] Narrow the action-plumbing isolation so host work is not modeled as UI-owned.
- [x] Record the follow-on `ServiceLifecycle` composition plan for host, config-watch, and MCP
      lifecycle cleanup in `docs/maintainers/embedded-service-lifecycle-plan.md`.
