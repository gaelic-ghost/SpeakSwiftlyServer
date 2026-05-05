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
socket_cache_path_pattern='~/.codex/plugins/cache/socket/speak-swiftly/[0-9]+\.[0-9]+\.[0-9]+/hooks'

[ -f "$plugin_manifest" ] || {
  printf '%s\n' "version-bump: missing Codex plugin manifest at $plugin_manifest." >&2
  exit 1
}

PLUGIN_MANIFEST="$plugin_manifest" \
RELEASE_VERSION="$release_version" \
REPO_ROOT="$repo_root" \
SOCKET_CACHE_PATH_PATTERN="$socket_cache_path_pattern" \
node <<'NODE'
const fs = require("fs");
const path = require("path");

const manifestPath = process.env.PLUGIN_MANIFEST;
const releaseVersion = process.env.RELEASE_VERSION;
const repoRoot = process.env.REPO_ROOT;
const socketCachePathPattern = process.env.SOCKET_CACHE_PATH_PATTERN;
const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));

manifest.version = releaseVersion;

fs.writeFileSync(`${manifestPath}\n`.trim(), `${JSON.stringify(manifest, null, 2)}\n`);

const versionedFiles = [
  "hooks/hooks.json",
  "scripts/codex-hooks-doctor.mjs",
  "README.md",
  "docs/codex-hooks-tts.md",
  "skills/speak-swiftly-codex-hooks/SKILL.md",
];

const socketCachePathExpression = new RegExp(socketCachePathPattern, "g");

for (const relativePath of versionedFiles) {
  const filePath = path.join(repoRoot, relativePath);
  const original = fs.readFileSync(filePath, "utf8");
  const matched = socketCachePathExpression.test(original);
  socketCachePathExpression.lastIndex = 0;
  const updated = original.replace(socketCachePathExpression, `~/.codex/plugins/cache/socket/speak-swiftly/${releaseVersion}/hooks`);

  if (!matched) {
    throw new Error(
      `version-bump: expected to update Socket cache hook path in ${relativePath}, but no versioned path matched.`,
    );
  }

  fs.writeFileSync(filePath, updated);
}
NODE

printf '%s\n' "version-bump: set plugin manifest and Socket hook cache paths to $release_version."
