# Plugin Install Testing

Use this guide when checking the Speak Swiftly Codex plugin payload from this
repository without touching Gale's personal production Codex install.

## Safety Model

This repository owns the canonical `speak-swiftly` plugin payload, but it no
longer ships a repo-local marketplace file. Socket is the supported end-user
marketplace entrypoint.

Do not run marketplace add, upgrade, or remove tests from this checkout. Run
those from the `socket` checkout, where the catalog entry points back to this
repository by Git-backed reference.

This repository should only validate the payload files that Socket installs:

- `.codex-plugin/plugin.json`
- `.mcp.json`
- `hooks/`
- `skills/`
- `scripts/codex-hooks-doctor.mjs`

## Local Payload Check

Run this from the `SpeakSwiftlyServer` checkout when validating branch-local
plugin payload changes:

```bash
jq '{name, version, displayName: .interface.displayName, mcpServers, hooks, skills}' \
  .codex-plugin/plugin.json

node scripts/codex-hooks-doctor.mjs --repair-plan
```

Expected result:

- The plugin manifest declares `name: speak-swiftly`, display name
  `Speak Swiftly`, `mcpServers: ./.mcp.json`, `hooks: ./hooks/hooks.json`, and
  `skills: ./skills/`.
- The hook doctor reports both `features.hooks = true` and
  `features.plugin_hooks = true`. `plugin_hooks` is required before Codex runs
  lifecycle hooks loaded from installed plugins.
- The hook doctor reports one installed-cache dispatcher command for `Stop` and
  one for `PermissionRequest`.
- The hook doctor keeps `speak-swiftly@socket` as the preferred enabled entry
  when duplicate or legacy plugin entries are present.

## Socket Catalog Test

Socket owns the catalog test for the broader marketplace. Run Socket-side tests
from the `socket` checkout, not here. The Socket test should prove that its
marketplace entry named `speak-swiftly` points at
`https://github.com/gaelic-ghost/SpeakSwiftlyServer.git` with the intended ref.

Do not copy this plugin payload into Socket for testing. This repository remains
the payload source of truth; Socket owns marketplace publication.

## Session Availability

Marketplace updates do not prove that an already-running Codex session has
refreshed visible plugin tools, skills, or hooks. Start a fresh Codex session
after the Socket marketplace update before judging the installed plugin surface.

If a fresh session sees the installed plugin but the `Stop` hook still does not
write to `~/.codex/speak-swiftly-server/hooks/logs/stop-tts.jsonl`, check
`features.plugin_hooks` before changing plugin hook commands or adding any
user-level hook file.

## End-User First Run And Updates

Marketplace installation and native service installation are separate by design.
The Socket marketplace gives Codex the `speak-swiftly` plugin payload: skills,
MCP registration for `http://127.0.0.1:7337/mcp`, and lifecycle hooks. It does
not silently install, restart, or update the per-user LaunchAgent-backed Swift
service.

The expected first-run path is:

1. Add or upgrade the broader Socket marketplace and enable `Speak Swiftly`.
2. Start a fresh Codex session so the managed plugin payload is visible.
3. Ask Codex to "set up Speak Swiftly on this machine" or run the LaunchAgent
   install command from the installed plugin checkout:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

The expected update path is:

1. Upgrade Socket:

```bash
codex plugin marketplace upgrade socket
```

2. Start a fresh Codex session so agents see the upgraded skills, hooks, and MCP
   registration.
3. Ask Codex to "refresh the Speak Swiftly live service" or run the LaunchAgent
   install command from the upgraded plugin checkout:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

Hook scripts must log unreachable-service failures instead of silently mutating
launchd from a final-reply hook. If auto-install or auto-update support becomes
available in the Codex plugin platform later, revisit this section before using
that behavior.
