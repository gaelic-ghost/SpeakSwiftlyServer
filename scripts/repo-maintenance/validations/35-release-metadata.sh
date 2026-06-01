#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

expect_prerelease() {
  tag_name="$1"

  if ! is_semver_prerelease_tag "$tag_name"; then
    die "Expected $tag_name to be detected as a SemVer prerelease tag."
  fi

  prerelease_args="$(github_release_prerelease_args "$tag_name")"
  [ "$prerelease_args" = "--prerelease" ] || die "Expected $tag_name to add --prerelease to GitHub release creation."
}

expect_final_release() {
  tag_name="$1"

  if is_semver_prerelease_tag "$tag_name"; then
    die "Expected $tag_name to be detected as a final SemVer release tag."
  fi

  prerelease_args="$(github_release_prerelease_args "$tag_name")"
  [ -z "$prerelease_args" ] || die "Expected $tag_name to avoid GitHub prerelease metadata."
}

expect_prerelease "v11.0.0-alpha.1"
expect_prerelease "v11.0.0-beta.1"
expect_prerelease "v11.0.0-rc.1"
expect_prerelease "v11.0.0-preview.20260601"
expect_final_release "v11.0.0"

log "Verified SemVer prerelease tags map to GitHub prerelease metadata."
