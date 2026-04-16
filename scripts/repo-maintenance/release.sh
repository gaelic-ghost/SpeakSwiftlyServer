#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/release.env"

usage() {
  cat <<'USAGE'
Usage:
  release.sh [publish] --version <vX.Y.Z> [publish flags...]
  release.sh prepare --version <vX.Y.Z> [prepare flags...]

Compatibility behavior:
  - no subcommand defaults to publish
  - prepare dispatches to release-prepare.sh
  - publish dispatches to release-publish.sh
USAGE
}

subcommand="publish"
case "${1:-}" in
  prepare|publish)
    subcommand="$1"
    shift
    ;;
  -h|--help)
    usage
    exit 0
    ;;
esac

case "$subcommand" in
  prepare)
    exec sh "$SELF_DIR/release-prepare.sh" "$@"
    ;;
  publish)
    current="$(current_branch)"
    release_branch_name="$(release_branch)"
    if [ -n "$current" ] && [ "$current" != "$release_branch_name" ]; then
      die "release.sh now defaults to the publish flow and must run from $release_branch_name. Current branch is $current. Use release.sh prepare ... from feature branches or worktrees."
    fi
    exec sh "$SELF_DIR/release-publish.sh" "$@"
    ;;
  *)
    usage
    die "Unknown release subcommand: $subcommand"
    ;;
esac
