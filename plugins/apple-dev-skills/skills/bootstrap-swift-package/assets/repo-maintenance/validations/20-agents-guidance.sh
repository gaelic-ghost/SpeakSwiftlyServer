#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

if [ "${REPO_MAINTENANCE_REQUIRE_AGENTS:-true}" != "true" ]; then
  log "Skipping AGENTS.md validation because REPO_MAINTENANCE_REQUIRE_AGENTS is disabled."
  exit 0
fi

agents_path="$REPO_ROOT/AGENTS.md"
[ -f "$agents_path" ] || die "Expected $agents_path to exist so the repo-maintenance toolkit has repo guidance to complement."
[ -s "$agents_path" ] || die "Expected $agents_path to be non-empty."
