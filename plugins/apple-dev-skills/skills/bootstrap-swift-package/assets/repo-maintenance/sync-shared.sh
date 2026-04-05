#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

ensure_git_repo
log "Running repo-maintenance shared sync from $REPO_ROOT"
run_dispatch_dir "$SELF_DIR/syncing" "sync"
log "Repo-maintenance shared sync completed successfully."
