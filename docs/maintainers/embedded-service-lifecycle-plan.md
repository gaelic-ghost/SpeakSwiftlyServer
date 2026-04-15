# Embedded ServiceLifecycle Refactor Plan

## Purpose

This note records the follow-on composition plan for the embedded-session runtime bundle after the
main-actor cleanup landed.

The goal is not just to "use more `ServiceLifecycle`". The real goal is to make lifecycle
ownership flatter, more explicit, and easier to reason about by moving package-owned long-running
work out of a retained orchestration task and into `Service`-shaped components.

## Documentation Basis

This plan is grounded in three upstream documentation surfaces:

### 1. Hummingbird `Application` docs from Dash

The local Dash `Hummingbird` docset says:

- `Application` conforms to `ServiceLifecycle.Service`
- `Application` accepts `services: [any Service]` for its internal `ServiceGroup`
- `Application.beforeServerStarts(...)` exists for work that must finish before the server begins
  accepting traffic

That confirms Hummingbird is already designed to live inside a service-lifecycle model rather than
beside one.

### 2. `swift-server/swift-service-lifecycle`

The local source checkout and the canonical package docs describe:

- `Service` as the reusable long-running task protocol
- `ServiceGroup` as the orchestration surface that runs child tasks per service and coordinates
  graceful shutdown

The source checkout is available in:

- `.build/checkouts/swift-service-lifecycle/Sources/ServiceLifecycle/Service.swift`
- `.build/checkouts/swift-service-lifecycle/Sources/ServiceLifecycle/ServiceGroup.swift`

Canonical package docs:

- <https://swiftpackageindex.com/swift-server/swift-service-lifecycle/2.11.0/documentation/servicelifecycle>

Note: in this session, the Dash API did not return a dedicated `swift-service-lifecycle` page by
name, so this plan cites the local source checkout plus the canonical published docs instead of
claiming a Dash symbol page that was not actually retrievable.

### 3. `swift-service-context` docs from Dash

The local Dash `ServiceContextModule` docset says `ServiceContext` is a typed, task-local context
propagation container. That makes it relevant for tracing, logging metadata, and request
correlation, but not for dependency injection or lifecycle ownership.

Canonical package page:

- <https://swiftpackageregistry.com/apple/swift-service-context>

## Current Problem

The current embedded-session startup path has improved concurrency isolation, but lifecycle
ownership is still split across too many places:

1. `EmbeddedServerSession.liveBootstrap(...)` constructs the package-owned graph.
2. A retained `Task` starts MCP, runs the outer `ServiceGroup`, cancels the config watcher, stops
   MCP, and shuts down the host.
3. The outer `ServiceGroup` currently knows only about the Hummingbird `Application`.
4. Hummingbird itself creates another internal `ServiceGroup`.

That shape works, but it is harder to reason about than it needs to be because package-owned
long-running components are not all represented as lifecycle-managed services.

The main conceptual smell is this:

- `ServerHost`, the config watch loop, and MCP readiness are package-owned runtime concerns
- but some of that lifecycle is currently hidden inside one retained task instead of being visible
  at the service boundary

## Design Decision

### Recommendation

Keep one library-owned outer `ServiceGroup` as the embedded session's top-level lifecycle owner,
and promote package-owned long-running work into explicit `Service` types that are siblings of the
Hummingbird `Application`.

Concretely, that means:

- `EmbeddedServerSession` still owns one outer `ServiceGroup`
- the outer group runs:
  - `HostLifecycleService`
  - `ConfigWatchService`
  - `MCPLifecycleService` when MCP is enabled
  - the Hummingbird `Application`
- Hummingbird's `beforeServerStarts(...)` is used only as a readiness barrier, not as the primary
  owner of package-owned lifecycle

### Why this is the preferred shape

This makes the lifecycle graph flatter in the way that actually matters:

- package-owned services are visible as siblings in one group instead of being hidden behind the
  Hummingbird transport
- the transport no longer looks like the owner of the host, MCP, or config watch
- startup and shutdown sequencing live in one explicit orchestration model

It also makes the code simpler to reason about:

- one top-level lifecycle owner: the embedded session's outer `ServiceGroup`
- one shared state owner: `ServerHost`
- one transport service: Hummingbird `Application`
- one retained run handle whose only job is to await the outer group so `start()` can return

### Rejected alternative: put package-owned services inside Hummingbird's internal `ServiceGroup`

This is technically possible because Hummingbird `Application` accepts `services`.

I am not recommending it as the primary shape for package-owned lifecycle because it makes the
ownership story more nested than necessary:

- `EmbeddedServerSession`
- outer `ServiceGroup`
- Hummingbird `Application`
- Hummingbird internal `ServiceGroup`
- package-owned services hidden inside the transport layer

That is less flat and harder to reason about because MCP, config watching, and host lifecycle are
not subordinate to HTTP in the product model. They are shared-host concerns that happen to support
the HTTP transport.

### Rejected alternative: keep the retained orchestration task as-is

This keeps the fewest types, but it keeps the most hidden lifecycle.

The cost is not just aesthetics. It means:

- package-owned long-running work is less visible to `ServiceLifecycle`
- startup ordering is partly encoded in one retained task body instead of in service relationships
- shutdown policy is harder to inspect and reuse

That is workable, but not the cleaner long-term model.

## Proposed Service Types

### 1. `HostLifecycleService`

Responsibility:

- start `ServerHost`
- signal host readiness once startup completes
- keep the host alive until shutdown
- call `host.shutdown()` during service teardown

Why this earns its own type:

- `ServerHost` is the real owner of the runtime and shared read model
- host startup and shutdown are long-running lifecycle concerns, not just assembly side effects

How it affects reasoning:

- flatter lifecycle: host ownership is visible at the service boundary
- simpler assembly: constructing a host no longer also implies starting it

### 2. `ConfigWatchService`

Responsibility:

- consume `configStore.updates()`
- forward accepted updates into `ServerHost`
- record config watch failures through the host

Why this earns its own type:

- it is already a long-running loop
- it naturally maps to `Service.run()`

How it affects reasoning:

- simpler shutdown: cancellation stops the service instead of manually cancelling a side task
- clearer failures: config-watch lifetime is no longer hidden inside another task body

### 3. `MCPLifecycleService`

Responsibility:

- call `mcpSurface.start()`
- signal MCP readiness once startup completes
- keep MCP available until shutdown
- call `mcpSurface.stop()` during service teardown

Why this earns its own type:

- MCP readiness is currently coordinated manually
- MCP session acceptance depends on explicit startup state

How it affects reasoning:

- flatter lifecycle: MCP becomes a visible sibling service instead of a side operation
- clearer startup ordering: readiness can be awaited explicitly before Hummingbird starts serving

## Startup Ordering

The startup path should split into two phases.

### Phase 1: assembly

`EmbeddedServerSession.start(...)` should:

1. create `ServerState` on the main actor
2. create `ConfigStore`
3. load `AppConfig`
4. construct an **unstarted** `ServerHost`
5. construct an optional **unstarted** `MCPSurface`
6. create readiness gates for the host and MCP
7. assemble the Hummingbird `Application`
8. create the outer `ServiceGroup`
9. create one retained run task that awaits `serviceGroup.run()`

This phase should not manually run long-lived loops or transport readiness work itself.

### Phase 2: service-owned startup

The outer `ServiceGroup` should run sibling services:

- `HostLifecycleService`
- `ConfigWatchService`
- `MCPLifecycleService` when enabled
- the Hummingbird `Application`

Hummingbird `beforeServerStarts(...)` should wait for:

- host readiness
- MCP readiness when MCP is enabled

Only after those readiness conditions are satisfied should the HTTP server begin listening.

### Why this ordering is better

This makes startup simpler to reason about because:

- object graph assembly is finished before lifecycle begins
- long-running work starts only through the service model
- the HTTP listener cannot outrun host or MCP readiness

## Shutdown Ordering

`EmbeddedServerSession.stop()` should:

1. call `outerServiceGroup.triggerGracefulShutdown()`
2. await the retained run task

Service teardown should then happen through the service model:

- Hummingbird stops listening
- config watch stops
- MCP stops accepting and drains active sessions
- host shuts down the live runtime

### Why this is better

This is simpler than the current tail-cleanup task body because:

- the embedded session no longer manually sequences every shutdown step
- shutdown policy is centralized in `ServiceLifecycle`
- the retained task becomes just a join handle, not a hidden lifecycle coordinator

## Role Of Hummingbird After The Refactor

Hummingbird should remain the HTTP transport service, not the owner of package-owned runtime
subsystems.

That means:

- continue using Hummingbird `Application` as a `Service`
- use `beforeServerStarts(...)` for readiness barriers
- reserve Hummingbird internal `services` for transport-local dependencies only when they are
  truly subordinate to the HTTP server

This keeps the host model straighter:

- `ServerHost` owns runtime state
- MCP and config watch are host-adjacent services
- HTTP is one transport service over that host

## Role Of `swift-service-context`

Do **not** use `ServiceContext` for dependency injection or lifecycle ownership in this refactor.

Use it later only if we need task-local context propagation for things such as:

- request identifiers
- trace and correlation metadata
- logger metadata
- MCP session-scoped diagnostic context

That keeps DI explicit and unidirectional instead of hiding real dependencies in task-local state.

## Concrete Refactor Checklist

- [ ] Split `ServerHost.live(...)` into pure construction plus explicit lifecycle start.
- [ ] Add `HostLifecycleService`.
- [ ] Add `ConfigWatchService`.
- [ ] Add `MCPLifecycleService`.
- [ ] Add readiness gates for host and MCP startup.
- [ ] Register a Hummingbird `beforeServerStarts(...)` barrier that waits for host readiness and,
      when enabled, MCP readiness.
- [ ] Change the outer embedded-session `ServiceGroup` so package-owned long-running services are
      siblings of the Hummingbird `Application`.
- [ ] Reduce the retained embedded run task to a single top-level join handle for the outer group.
- [ ] Remove manual MCP/config-watch/host cleanup from the retained task body once service-owned
      lifecycle replaces it.
- [ ] Update docs so the ownership model explicitly says the outer service group owns host
      lifecycle, config watching, MCP lifecycle, and HTTP serving.

## Expected Outcome

If this lands cleanly, the embedded-session ownership model becomes easier to describe in one
sentence:

`EmbeddedServerSession` assembles the graph, one outer `ServiceGroup` owns package lifecycle,
`ServerHost` owns shared runtime state, and Hummingbird is just the HTTP transport service over
that host.

That is flatter than the current model because package lifecycle stops being split between:

- assembly helpers
- a retained orchestration task
- an outer `ServiceGroup`
- Hummingbird's internal `ServiceGroup`

It is also simpler to reason about because startup, readiness, shutdown, and cancellation all have
one obvious home.
