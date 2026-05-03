#!/usr/bin/env sh
set -eu

release_version="${1:-}"

case "$release_version" in
  [0-9]*.[0-9]*.[0-9]*|[0-9]*.[0-9]*.[0-9]*-*)
    ;;
  *)
    printf '%s\n' "version-bump: expected release version without leading v, got '${release_version:-<empty>}'." >&2
    exit 1
    ;;
esac

repo_root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
plugin_manifest="$repo_root/.codex-plugin/plugin.json"

[ -f "$plugin_manifest" ] || {
  printf '%s\n' "version-bump: missing Codex plugin manifest at $plugin_manifest." >&2
  exit 1
}

PLUGIN_MANIFEST="$plugin_manifest" RELEASE_VERSION="$release_version" node <<'NODE'
const fs = require("fs");

const manifestPath = process.env.PLUGIN_MANIFEST;
const releaseVersion = process.env.RELEASE_VERSION;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

manifest.version = releaseVersion;

fs.writeFileSync(`${manifestPath}\n`.trim(), `${JSON.stringify(manifest, null, 2)}\n`);
NODE

printf '%s\n' "version-bump: set .codex-plugin/plugin.json version to $release_version."
