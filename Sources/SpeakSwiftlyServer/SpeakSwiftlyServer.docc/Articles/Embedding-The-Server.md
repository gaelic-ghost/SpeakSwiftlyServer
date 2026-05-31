# Embedding The Server

## Overview

Use ``EmbeddedServer`` when an app wants to host the shared SpeakSwiftly server runtime inside its own process instead of starting the standalone executable separately.

`EmbeddedServer` gives app code one durable object to own directly. That object carries the
observable properties SwiftUI reads, and it owns the embedded host lifecycle through
``EmbeddedServer/liftoff(environment:)`` and ``EmbeddedServer/land()``.

The session keeps transport ownership, config loading, and host shutdown logic internal. Behind that wrapper, the embedded path now composes the host lifecycle, optional config watching, optional MCP lifecycle, and HTTP serving as service-owned siblings under one outer lifecycle group. App code should still treat that as an internal implementation detail: hold onto the session object, bind UI to `session.state`, and use the state snapshots as the public read model for the embedded host.

## Core Types

### ``EmbeddedServer``

Create the shared host through ``EmbeddedServer/init(options:)`` and start it through
``EmbeddedServer/liftoff(environment:)``. The embedded path still uses the same environment-driven
config model as the standalone runtime, but it now carries its own embedded-session default port
and lets app code provide explicit `Options(port:runtimeProfileRootURL:)` values when another
localhost port or another runtime-owned persistence root is a better fit.

Call ``EmbeddedServer/land()`` when the app wants a graceful shutdown. If the server has already
been asked to land, a second request simply waits for the same shutdown to finish. If shutdown is
requested while the embedded runtime is still starting, that same `land()` call now cancels the
in-flight startup attempt instead of waiting forever for startup to finish first. Embedded startup
is also time-bounded: if the underlying runtime does not finish startup within the package-owned
startup timeout, the session reports a clear startup failure and tears itself down instead of
remaining stuck in a permanent starting state.

## Consumer Ownership Model

For an app consumer, the intended pattern is one long-lived session owner, not ad hoc calls scattered across views.

The clean mental model is:

1. one app-owned controller or model creates the `EmbeddedServer`
2. that owner calls `liftoff()`
3. UI reads and reacts to properties on that same object
4. control actions that the app truly owns go through that same object
5. the same owner calls `land()` during app teardown or when the feature is explicitly turned off

Treat the `EmbeddedServer` instance as both the lifecycle handle and the read-and-control facade.
Do not try to reconstruct host ownership from the snapshot fields, and do not create a fresh
server object every time a view appears or a control is tapped.

In practice, the embedded consumer should need exactly one reference to `EmbeddedServer` and one
observation path rooted directly at that object.

`EmbeddedServer` is meant for three kinds of app work:

- reading current host state for UI and diagnostics
- issuing a small set of embedded-host control actions such as profile refresh or playback control
- reacting to readiness and error changes without talking to transport internals directly

It is not meant to be a second runtime owner, a transport client, or a public escape hatch into every HTTP or MCP payload shape.

### Snapshot Families

The library keeps the observable state in small transport-neutral snapshot types:

- `HostOverviewSnapshot` for host identity and readiness
- `QueueStatusSnapshot` and `PlaybackStatusSnapshot` for active and queued work
- `RuntimeConfigurationSnapshot` for persisted and active runtime configuration
- `TransportStatusSnapshot` and `RecentErrorSnapshot` for operator-facing health signals

When you need the whole current picture at once, use `HostStateSnapshot` as the aggregate read model.

## When To Use The Executable Instead

Use the embedded session when an app owns the process and wants direct observable state. Use the standalone executable and the HTTP or MCP surfaces when another process, a LaunchAgent, or an external operator should own runtime startup and shutdown.

If the app needs explicit ownership of where the runtime persists profiles, generated artifacts, and staged runtime configuration, pass `runtimeProfileRootURL` on the embedded session options. `SpeakSwiftlyServer` keeps that value as the profile-store root on its side, resolves it to the containing state root, and passes that URL directly into `SpeakSwiftly.liftoff(configuration:stateRootURL:)` so the embedded app does not have to manage those two persistence paths separately.

For the transport inventory and command-line surface, see <doc:Operator-Surfaces>.
