# Local Control Panel

SpeakSwiftlyServer bundles a local control panel under the HTTP route `/control-panel/`.

The checked-in frontend package is still named `WebUI/` because it is the build artifact source. The user-facing surface should be called the local control panel. Use `dashboard` only for read-only overview areas inside the control panel; the whole surface includes runtime controls.

The WebUI package is a Vite React TypeScript app in `WebUI/`. It uses shadcn/ui source components, Tailwind CSS, and lucide icons. The app is intentionally backed by the existing HTTP routes from `API.md`; do not add control-panel-specific mirror endpoints unless an operator workflow cannot be represented by the existing HTTP contract.

## Build Path

Build the frontend from the package root with:

```bash
pnpm --dir WebUI build
```

The Vite build writes the compiled static bundle into:

```text
Sources/SSSHTTP/Resources/WebUI
```

SwiftPM copies that directory as an `SSSHTTP` target resource. `Sources/SSSHTTP/HTTP/HTTPWebUIRoutes.swift` mounts the resource directory with Hummingbird `FileMiddleware` at `/control-panel`.

## Development Path

For frontend-only iteration, run:

```bash
pnpm --dir WebUI dev
```

The Vite dev server proxies SpeakSwiftlyServer HTTP routes to `http://127.0.0.1:7338` by default. The production bundle is same-origin when served by Hummingbird, so frontend code should keep using relative HTTP paths such as `/overview`, `/playback/state`, and `/requests`.

Agents helping users with the control panel should start with the service URL that matches the user's active runtime:

- Foreground tool default: `http://127.0.0.1:7338/control-panel/`
- Installed service: the configured local HTTP listener port plus `/control-panel/`

Use the control panel for visual inspection and guided operation. Use MCP resources or direct HTTP calls for precise state capture, automation, and destructive mutations.

## Test Path

Run the focused frontend lane with:

```bash
pnpm --dir WebUI test
```

This lane covers the control panel's HTTP snapshot fan-out, offline-state shaping, control route helpers, and loose JSON readout helpers. The Swift HTTP test suite separately verifies that Hummingbird serves the bundled `/control-panel/` page and built assets.

Run the rendered browser regression lane with:

```bash
pnpm --dir WebUI test:browser
```

The browser lane starts Vite, mocks each existing HTTP endpoint, confirms that tabs are the only primary navigation pattern, and checks every visible control sends the expected HTTP method and route. Swift tests remain responsible for proving that the production bundle is served by Hummingbird and the real HTTP routes behave correctly.

## Maintenance Rules

- Keep `WebUI/src/lib/api.ts` pointed at existing HTTP routes first.
- Keep Hummingbird static serving in `SSSHTTP`; do not move WebUI routing into `SSSCore`.
- Rebuild `Sources/SSSHTTP/Resources/WebUI` whenever frontend source, dependencies, or Vite config changes.
- Run `pnpm --dir WebUI lint`, `pnpm --dir WebUI test`, `pnpm --dir WebUI test:browser`, `pnpm --dir WebUI build`, `xcrun swift build`, and the relevant Swift test lane before handoff.
- Avoid adding frontend-only server state. If the UI reveals missing shared state or observability, prefer moving that state into `SpeakSwiftly` or `SSSCore` as a reusable API surface instead of creating a WebUI-only side channel.
