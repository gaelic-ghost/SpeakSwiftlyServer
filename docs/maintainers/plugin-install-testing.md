# Plugin Install Testing

Use this guide when testing the standalone SpeakSwiftlyServer Codex marketplace
and plugin payload without touching personal production Codex installs.

## Safety Model

Gale's personal Codex scope should stay reserved for stable production installs.
Marketplace add, remove, and upgrade tests should use an isolated temporary
`CODEX_HOME` so test marketplaces, caches, and config do not rewrite
`~/.codex/config.toml` or the production plugin cache.

This repository owns the canonical `speak-swiftly` plugin payload:

- `.codex-plugin/plugin.json`
- `.agents/plugins/marketplace.json`
- `.mcp.json`
- `hooks/`
- `skills/`
- `scripts/codex-hooks-doctor.mjs`

Run payload install tests from this checkout. The `socket` repository should
only prove that its marketplace lists this same repository by Git-backed
reference.

## Local Checkout Test

Run this from the `SpeakSwiftlyServer` checkout when validating branch-local
plugin payload or marketplace changes:

```bash
SPEAK_SWIFTLY_SERVER_REPO="$(pwd)"
TEST_CODEX_HOME="$(mktemp -d /private/tmp/speak-swiftly-codex-home.XXXXXX)"

CODEX_HOME="$TEST_CODEX_HOME" codex plugin marketplace add "$SPEAK_SWIFTLY_SERVER_REPO"

jq '.plugins[] | select(.name == "speak-swiftly")' \
  "$SPEAK_SWIFTLY_SERVER_REPO/.agents/plugins/marketplace.json"

jq '{name, version, displayName: .interface.displayName, mcpServers, hooks, skills}' \
  "$SPEAK_SWIFTLY_SERVER_REPO/.codex-plugin/plugin.json"

CODEX_HOME="$TEST_CODEX_HOME" codex plugin marketplace remove speak-swiftly-server-local
test ! -s "$TEST_CODEX_HOME/config.toml"
rm -rf "$TEST_CODEX_HOME"
```

Expected result:

- Codex reports an added marketplace named `speak-swiftly-server-local` from
  the local checkout.
- The repo-local marketplace entry contains `name: speak-swiftly` and
  `source.path: ./`.
- The plugin manifest declares `name: speak-swiftly`, display name
  `Speak Swiftly`, `mcpServers: ./.mcp.json`, `hooks: ./hooks/hooks.json`, and
  `skills: ./skills/`.
- Removing `speak-swiftly-server-local` leaves no configured marketplace in the
  temporary Codex home.

## Git-Backed Test

Run this after the branch has landed in GitHub state that users can fetch:

```bash
TEST_CODEX_HOME="$(mktemp -d /private/tmp/speak-swiftly-codex-home.XXXXXX)"

CODEX_HOME="$TEST_CODEX_HOME" codex plugin marketplace add gaelic-ghost/SpeakSwiftlyServer
CODEX_HOME="$TEST_CODEX_HOME" codex plugin marketplace upgrade speak-swiftly-server-local

jq '.plugins[] | select(.name == "speak-swiftly")' \
  "$TEST_CODEX_HOME/.tmp/marketplaces/speak-swiftly-server-local/.agents/plugins/marketplace.json"

jq '{name, version, displayName: .interface.displayName, mcpServers, hooks, skills}' \
  "$TEST_CODEX_HOME/.tmp/marketplaces/speak-swiftly-server-local/.codex-plugin/plugin.json"

CODEX_HOME="$TEST_CODEX_HOME" codex plugin marketplace remove speak-swiftly-server-local
test ! -s "$TEST_CODEX_HOME/config.toml"
rm -rf "$TEST_CODEX_HOME"
```

Expected result:

- Codex reports `source_type = "git"` for
  `marketplaces.speak-swiftly-server-local`.
- `upgrade speak-swiftly-server-local` succeeds.
- The cached marketplace entry contains `name: speak-swiftly` and
  `source.path: ./`.
- The cached plugin manifest declares the expected `Speak Swiftly` payload
  paths.
- Removing `speak-swiftly-server-local` leaves no configured marketplace in the
  temporary Codex home.

The current Codex CLI registers both local and Git-backed
`gaelic-ghost/SpeakSwiftlyServer` marketplaces as
`speak-swiftly-server-local`. Use the marketplace name Codex reports instead of
guessing from the repository name.

## Socket Catalog Test

Socket owns the catalog test for its broader marketplace. Run Socket-side tests
from the `socket` checkout, not here. The Socket test should prove that its
marketplace entry named `speak-swiftly` points at
`https://github.com/gaelic-ghost/SpeakSwiftlyServer.git` with `ref: main`.

Do not copy this plugin payload into Socket for testing. The whole point of the
catalog split is that this repository remains the one payload source of truth.

## Session Availability

These commands prove the marketplace and cached plugin files. They do not prove
that an already-running Codex session has refreshed its visible plugin tools and
skills. For that final check, start a fresh Codex session after the add or
upgrade and inspect the Plugin Directory or the model-visible tool list.
