# Speak Swiftly Local Control Panel

This package-local Vite app builds the static control panel served by SpeakSwiftlyServer at `/control-panel/`.

## Commands

```bash
pnpm install
pnpm lint
pnpm test
pnpm build
pnpm dev
```

`pnpm build` writes the compiled bundle into `../Sources/SSSHTTP/Resources/WebUI` so SwiftPM can include it as an `SSSHTTP` resource.

## API Boundary

The WebUI consumes the existing HTTP routes with relative paths. Keep new operator workflows on the existing HTTP contract first; add new server endpoints only when the underlying server capability is genuinely missing.

During `pnpm dev`, Vite proxies those relative HTTP routes to `http://127.0.0.1:7338`.
