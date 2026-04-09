#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
tag_sha="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$RELEASE_TAG" 2>/dev/null || true)"

if [ -n "$tag_sha" ]; then
  [ "$tag_sha" = "$head_sha" ] || die "Tag $RELEASE_TAG already exists and does not point at HEAD."
  log "Tag $RELEASE_TAG already points at HEAD."
  exit 0
fi

if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
  log "Would create annotated tag $RELEASE_TAG at HEAD."
  exit 0
fi

git -C "$REPO_ROOT" tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG"
log "Created annotated tag $RELEASE_TAG."
