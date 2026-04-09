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
