#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
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
  prerelease_flag="$(github_release_create_prerelease_flag "$RELEASE_TAG")"
  log "Would create a GitHub release for $RELEASE_TAG with gh release create --verify-tag${prerelease_flag:+ $prerelease_flag}."
  exit 0
fi

if gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  verify_github_release_prerelease_metadata "$RELEASE_TAG"
  log "GitHub release $RELEASE_TAG already exists."
  exit 0
fi

prerelease_flag="$(github_release_create_prerelease_flag "$RELEASE_TAG")"
# shellcheck disable=SC2086
gh release create "$RELEASE_TAG" --verify-tag --generate-notes $prerelease_flag
log "Created GitHub release $RELEASE_TAG."
wait_for_github_release "$RELEASE_TAG"
verify_github_release_prerelease_metadata "$RELEASE_TAG"
