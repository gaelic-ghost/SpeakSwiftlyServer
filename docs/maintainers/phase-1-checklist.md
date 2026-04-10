# Phase 1 Checklist

## Objective

Complete the structural pivot to `ServerHost actor + @Observable ServerState class + composed AppConfig` while preserving the current HTTP route behavior.

## Scope

Phase 1 intentionally does not add the MCP route or `swift-configuration` dependency yet. It prepares the codebase for both.

## File Changes

### Host

- Create `Sources/SpeakSwiftlyServer/Host/ServerHost.swift`
  Move the existing actor implementation here.

- Replace `Sources/SpeakSwiftlyServer/Host/ServerState.swift`
  Repurpose it into an observable UI-facing state class.

- Keep `Sources/SpeakSwiftlyServer/Host/ServerRuntimeProtocol.swift` and `Sources/SpeakSwiftlyServer/Host/ServerRuntimeAdapter.swift`
  They remain the narrow runtime seam now that the protocol and concrete adapter are split by concern.

### Config

- Create `Sources/SpeakSwiftlyServer/Config/AppConfig.swift`
  Add `AppConfig`, `HTTPConfig`, and `MCPConfig`.

- Keep `Sources/SpeakSwiftlyServer/Host/ServerConfiguration.swift`
  It remains the current environment parser and shared host config source during the transition.

### HTTP

- Update `Sources/SpeakSwiftlyServer/HTTP/HTTPSurface.swift`
  Accept `ServerHost` instead of the old actor named `ServerState`.

### Entry Point

- Update `Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.swift`
  Load `AppConfig`, create `ServerState`, create `ServerHost`, start the host, then assemble the Hummingbird app.

## Acceptance Criteria

- The server still exposes the same HTTP routes and payload shapes.
- Only one runtime-owning host type exists in the package.
- `ServerState` is safe to use as an app-facing observable object.
- The new app configuration is composed even though it still derives from the existing environment parser.
- Tests still cover the current HTTP behavior after the rename from `ServerState` actor to `ServerHost` actor.

## Follow-On Work

- Phase 2 should move any remaining shared backend concerns that are still sitting in HTTP-specific naming or models into the host layer.
- Phase 3 should replace the temporary composed-config loader with `swift-configuration`.
- Phase 4 should add `/mcp` to the same app process.
