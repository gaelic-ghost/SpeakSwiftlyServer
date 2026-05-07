# First Embedded Session

## Overview

This is the shortest realistic path through the library-first surface:

1. create an ``EmbeddedServer``
2. call `liftoff()` with the same environment-driven config model the standalone host uses
3. read the server object itself as the app-facing snapshot model
4. decide when to switch to the executable and transport docs instead

Use this walkthrough when you want to understand the package as an app-embedded host first, not as a LaunchAgent-managed service.

## Start The Session

Create the embedded server model and start it from app-owned code:

```swift
import SpeakSwiftlyServer

let server = EmbeddedServer(
    options: .init(
        port: 7811,
        runtimeProfileRootURL: FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("ExampleApp/SpeakSwiftlyRuntime", isDirectory: true)
    )
)
try await server.liftoff()
```

`EmbeddedServer` owns the host lifecycle. Internally it now coordinates host startup, optional config watching, optional MCP readiness, and HTTP serving through one service-owned lifecycle group, but app code should still treat the server object itself as the lifecycle boundary. Keep that object alive for as long as you want the shared server running in-process. If you do not pass `Options(port:)`, the embedded host defaults to `127.0.0.1:7339`.

If the app decides to stop the embedded session while startup is still in flight, `land()` now
cancels that startup attempt and proceeds through the same orderly teardown path. If the underlying
runtime startup stalls completely, the embedded lifecycle also times out that startup attempt and
surfaces a clear failure instead of staying stuck in startup indefinitely.

If you pass `runtimeProfileRootURL`, the embedded host uses that explicit profile-store root for its own persisted runtime configuration bookkeeping, resolves it to the containing runtime state root, and passes that URL directly into `SpeakSwiftly.liftoff(configuration:stateRootURL:)`. Use that when the app wants an explicit app-owned or App Group-owned runtime root instead of relying on the default Application Support lookup.

## Read The App-Facing State

Once the server is running, bind UI and app logic to the server object directly:

```swift
import SpeakSwiftlyServer

let server = EmbeddedServer()
try await server.liftoff()

let hostOverview = server.overview
let playbackStatus = server.playback
let availableVoices = server.voiceProfiles
```

Treat ``EmbeddedServer`` as the app-facing read model. It is the place to inspect readiness, queue state, transport state, runtime configuration, recent errors, and the cached voice-profile list without reaching into host internals directly.

When you need one aggregated picture instead of several observable fields, follow the snapshot families described in <doc:Embedding-The-Server>.

## Know When To Leave DocC

Stay in the library-first docs when you are answering questions like:

- how does an app start the shared host
- which state type should SwiftUI observe
- when should an app switch from embedded hosting to a bundled helper executable

Jump to the operator docs when the question becomes:

- how do I install or refresh the LaunchAgent
- what filesystem layout should the bundled tool helper own
- which HTTP or MCP route exposes this runtime operation
- what does the command-line tool print or accept

For those surfaces, continue with <doc:Operator-Surfaces> and then use the repository docs linked there.
