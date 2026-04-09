#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

if [ "${REPO_MAINTENANCE_SKIP_GH_RELEASE:-false}" = "true" ]; then
  log "Skipping GitHub release creation because --skip-gh-release was requested."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  warn "gh is unavailable, so the release tag was pushed without creating a GitHub release object."
  exit 0
fi

if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
  log "Would create a GitHub release for $RELEASE_TAG with gh release create --verify-tag."
  exit 0
fi

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  log "GitHub release $RELEASE_TAG already exists."
  exit 0
fi

gh release create "$RELEASE_TAG" --verify-tag --generate-notes
log "Created GitHub release $RELEASE_TAG."
