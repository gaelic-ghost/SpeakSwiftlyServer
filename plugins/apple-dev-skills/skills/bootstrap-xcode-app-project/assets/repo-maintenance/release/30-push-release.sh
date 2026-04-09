#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

branch_name="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD)"

if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
  log "Would push branch $branch_name and tag $RELEASE_TAG to origin."
  exit 0
fi

git -C "$REPO_ROOT" push -u origin "$branch_name"
git -C "$REPO_ROOT" push origin "$RELEASE_TAG"
log "Pushed branch $branch_name and tag $RELEASE_TAG."
