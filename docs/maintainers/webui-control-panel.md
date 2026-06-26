# WebUI Control Panel

SpeakSwiftlyServer bundles a local WebUI control panel under the HTTP route `/control-panel/`.

The WebUI is a Vite React TypeScript app in `WebUI/`. It uses shadcn/ui source components, Tailwind CSS, and lucide icons. The app is intentionally backed by the existing HTTP routes from `API.md`; do not add dashboard-specific mirror endpoints unless an operator workflow cannot be represented by the existing HTTP contract.

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

## Maintenance Rules

- Keep `WebUI/src/lib/api.ts` pointed at existing HTTP routes first.
- Keep Hummingbird static serving in `SSSHTTP`; do not move WebUI routing into `SSSCore`.
- Rebuild `Sources/SSSHTTP/Resources/WebUI` whenever frontend source, dependencies, or Vite config changes.
- Run `pnpm --dir WebUI lint`, `pnpm --dir WebUI build`, `xcrun swift build`, and the relevant Swift test lane before handoff.
- Avoid adding frontend-only server state. If the UI reveals missing shared state or observability, prefer moving that state into `SpeakSwiftly` or `SSSCore` as a reusable API surface instead of creating a WebUI-only side channel.
