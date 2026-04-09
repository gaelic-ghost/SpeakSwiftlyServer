#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

ensure_git_repo

case "${REPO_MAINTENANCE_RELEASE_MODE:-}" in
  standard|submodule)
    ;;
  *)
    die "Release mode must be standard or submodule."
    ;;
esac

case "${RELEASE_TAG:-}" in
  v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*.[0-9]*-*)
    ;;
  *)
    die "Release tag must use vX.Y.Z SemVer syntax."
    ;;
esac

branch_name="$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true)"
[ -n "$branch_name" ] || die "Release workflow requires a named branch instead of detached HEAD."

status_output="$(git -C "$REPO_ROOT" status --porcelain)"
[ -z "$status_output" ] || die "Release workflow requires a clean worktree before tagging."

if [ "${REPO_MAINTENANCE_RELEASE_MODE:-}" = "submodule" ]; then
  superproject_root="$(git -C "$REPO_ROOT" rev-parse --show-superproject-working-tree || true)"
  [ -n "$superproject_root" ] || die "Submodule release mode requires this repository to be checked out as a git submodule."
fi

artifact_root="$(release_artifacts_root)"
tag_dir="$(release_artifact_tag_dir)"
current_link="$(release_artifact_current_dir)"

if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
  log "Would build SpeakSwiftlyServerTool in release mode and stage it under $tag_dir."
  log "Would refresh $current_link to point at $RELEASE_TAG."
  exit 0
fi

log "Building SpeakSwiftlyServerTool in release mode."
swift build -c release --product SpeakSwiftlyServerTool

bin_path="$(swift build -c release --show-bin-path)"
source_tool="$bin_path/SpeakSwiftlyServerTool"
[ -f "$source_tool" ] || die "Release build completed, but the expected tool executable was not found at $source_tool."
[ -x "$source_tool" ] || die "Release build completed, but $source_tool is not executable."

mkdir -p "$tag_dir"
cp "$source_tool" "$tag_dir/SpeakSwiftlyServerTool"
chmod 755 "$tag_dir/SpeakSwiftlyServerTool"

mkdir -p "$artifact_root"
rm -f "$current_link"
ln -s "$RELEASE_TAG" "$current_link"

log "Staged release artifact at $tag_dir/SpeakSwiftlyServerTool."
log "Updated current release artifact link at $current_link."
