#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

log "Checking Codex plugin doctor syntax and focused migration fixtures."
node --check "$REPO_ROOT/scripts/codex-hooks-doctor.mjs"
node --check "$REPO_ROOT/hooks/stop-tts.mjs"
node --check "$REPO_ROOT/hooks/stop-log.mjs"
node --test "$REPO_ROOT/scripts/codex-hooks-doctor.test.mjs"
node --test "$REPO_ROOT/hooks/stop-tts.test.mjs"
