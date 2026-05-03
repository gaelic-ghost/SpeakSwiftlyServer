#!/usr/bin/env sh
set -eu

COMMON_DIR="${REPO_MAINTENANCE_COMMON_DIR:-}"

if [ -z "$COMMON_DIR" ]; then
  COMMON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
fi

REPO_MAINTENANCE_ROOT=$(CDPATH= cd -- "$COMMON_DIR/.." && pwd)
REPO_ROOT=$(CDPATH= cd -- "$REPO_MAINTENANCE_ROOT/../.." && pwd)
REPO_MAINTENANCE_PROFILE="generic"
REPO_MAINTENANCE_PROFILE_DESCRIPTION="Generic repo-maintenance baseline with no Swift or Xcode specialization."

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

load_env_file() {
  env_file="$1"
  [ -f "$env_file" ] || return 0
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
}

load_profile_env() {
  load_env_file "$REPO_MAINTENANCE_ROOT/config/profile.env"
}

positive_integer_or_default() {
  value="$1"
  default_value="$2"

  case "$value" in
    ''|*[!0-9]*)
      printf '%s\n' "$default_value"
      ;;
    0)
      printf '%s\n' "$default_value"
      ;;
    *)
      printf '%s\n' "$value"
      ;;
  esac
}

github_wait_timeout() {
  value="$1"
  default_timeout="$(positive_integer_or_default "${REPO_MAINTENANCE_GH_WAIT_TIMEOUT_SECONDS:-120}" 120)"
  positive_integer_or_default "$value" "$default_timeout"
}

github_wait_poll_seconds() {
  value="$1"
  default_poll_seconds="$(positive_integer_or_default "${REPO_MAINTENANCE_GH_WAIT_POLL_SECONDS:-5}" 5)"
  positive_integer_or_default "$value" "$default_poll_seconds"
}

wait_for_remote_branch() {
  branch_name="$1"
  timeout_seconds="$(github_wait_timeout "${REPO_MAINTENANCE_REMOTE_BRANCH_TIMEOUT_SECONDS:-}")"
  poll_seconds="$(github_wait_poll_seconds "${REPO_MAINTENANCE_REMOTE_BRANCH_POLL_SECONDS:-}")"
  elapsed_seconds="0"

  log "Waiting up to ${timeout_seconds}s for remote branch origin/$branch_name to become visible."

  while :; do
    if git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$branch_name" >/dev/null 2>&1; then
      log "Remote branch origin/$branch_name is visible."
      return 0
    fi

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      die "Remote branch origin/$branch_name was not visible after ${timeout_seconds}s. Confirm the branch push succeeded and that the origin remote is reachable before rerunning release.sh."
    fi

    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
  done
}

wait_for_remote_tag() {
  tag_name="$1"
  timeout_seconds="$(github_wait_timeout "${REPO_MAINTENANCE_REMOTE_TAG_TIMEOUT_SECONDS:-}")"
  poll_seconds="$(github_wait_poll_seconds "${REPO_MAINTENANCE_REMOTE_TAG_POLL_SECONDS:-}")"
  elapsed_seconds="0"

  log "Waiting up to ${timeout_seconds}s for remote tag $tag_name to become visible."

  while :; do
    if git -C "$REPO_ROOT" ls-remote --exit-code --tags origin "refs/tags/$tag_name" >/dev/null 2>&1; then
      log "Remote tag $tag_name is visible."
      return 0
    fi

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      die "Remote tag $tag_name was not visible after ${timeout_seconds}s. Confirm the tag push succeeded and that GitHub has indexed the tag before rerunning release.sh."
    fi

    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
  done
}

wait_for_github_release() {
  tag_name="$1"
  timeout_seconds="$(github_wait_timeout "${REPO_MAINTENANCE_GH_RELEASE_TIMEOUT_SECONDS:-}")"
  poll_seconds="$(github_wait_poll_seconds "${REPO_MAINTENANCE_GH_RELEASE_POLL_SECONDS:-}")"
  elapsed_seconds="0"

  log "Waiting up to ${timeout_seconds}s for GitHub release $tag_name to become readable."

  while :; do
    if gh release view "$tag_name" >/dev/null 2>&1; then
      log "GitHub release $tag_name is readable."
      return 0
    fi

    if [ "$elapsed_seconds" -ge "$timeout_seconds" ]; then
      die "GitHub release $tag_name was not readable after ${timeout_seconds}s. Confirm release creation succeeded and GitHub has indexed the release before rerunning release.sh."
    fi

    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
  done
}

ensure_git_repo() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "maintain-project-repo must run inside a git worktree rooted at $REPO_ROOT."
}

run_dispatch_dir() {
  dir="$1"
  label="$2"
  ran_any="false"

  for script in "$dir"/*.sh; do
    [ -e "$script" ] || continue
    ran_any="true"
    log "Running $label step $(basename "$script")"
    sh "$script"
  done

  if [ "$ran_any" = "false" ]; then
    log "No $label steps are currently defined under $dir."
  fi
}
