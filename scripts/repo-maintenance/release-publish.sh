#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/lib/common.sh"

load_env_file "$SELF_DIR/config/release.env"

mode="${REPO_MAINTENANCE_DEFAULT_RELEASE_MODE:-standard}"
release_tag=""
skip_validate="false"
skip_gh_release="false"
refresh_live_service="${REPO_MAINTENANCE_DEFAULT_REFRESH_LIVE_SERVICE:-true}"
live_service_config_file="${REPO_MAINTENANCE_DEFAULT_LIVE_SERVICE_CONFIG_FILE:-$HOME/Library/Application Support/SpeakSwiftlyServer/server.yaml}"
dry_run="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --version)
      release_tag="${2:-}"
      shift 2
      ;;
    --skip-validate)
      skip_validate="true"
      shift
      ;;
    --skip-gh-release)
      skip_gh_release="true"
      shift
      ;;
    --refresh-live-service)
      refresh_live_service="true"
      shift
      ;;
    --skip-live-service-refresh)
      refresh_live_service="false"
      shift
      ;;
    --live-service-config-file)
      live_service_config_file="${2:-}"
      shift 2
      ;;
    --dry-run)
      dry_run="true"
      shift
      ;;
    -h|--help)
      cat <<'USAGE'
Usage:
  release-publish.sh --mode <standard|submodule> --version <vX.Y.Z> [--skip-validate] [--skip-gh-release] [--refresh-live-service|--skip-live-service-refresh] [--live-service-config-file <path>] [--dry-run]

This workflow is for the release branch only. It syncs local main with origin, validates the checkout, stages the tagged release artifact, creates the annotated tag, pushes the tag, creates the GitHub release object, and optionally refreshes the live service.
USAGE
      exit 0
      ;;
    *)
      die "Unknown release-publish argument: $1"
      ;;
  esac
done

[ -n "$release_tag" ] || die "Pass --version vX.Y.Z when running the release-publish workflow."

export REPO_MAINTENANCE_RELEASE_MODE="$mode"
export RELEASE_TAG="$release_tag"
export REPO_MAINTENANCE_SKIP_GH_RELEASE="$skip_gh_release"
export REPO_MAINTENANCE_REFRESH_LIVE_SERVICE="$refresh_live_service"
export REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE="$live_service_config_file"
export REPO_MAINTENANCE_DRY_RUN="$dry_run"

ensure_git_repo
ensure_release_tag_format
ensure_on_release_branch
ensure_clean_worktree

case "${REPO_MAINTENANCE_RELEASE_MODE:-}" in
  standard|submodule)
    ;;
  *)
    die "Release mode must be standard or submodule."
    ;;
esac

if [ "${REPO_MAINTENANCE_RELEASE_MODE:-}" = "submodule" ]; then
  superproject_root="$(git -C "$REPO_ROOT" rev-parse --show-superproject-working-tree || true)"
  [ -n "$superproject_root" ] || die "Submodule release mode requires this repository to be checked out as a git submodule."
fi

sync_local_release_branch
ensure_clean_worktree

head_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
tag_sha="$(git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$RELEASE_TAG" 2>/dev/null || true)"
if [ -n "$tag_sha" ] && [ "$tag_sha" != "$head_sha" ]; then
  die "Tag $RELEASE_TAG already exists and does not point at HEAD."
fi

if [ "$skip_validate" != "true" ]; then
  sh "$SELF_DIR/validate-all.sh"
fi

log "Running release-publish in $REPO_MAINTENANCE_RELEASE_MODE mode for $RELEASE_TAG from $(release_branch)."
stage_release_artifact

if [ -n "$tag_sha" ]; then
  log "Tag $RELEASE_TAG already points at HEAD."
elif [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
  log "Would create annotated tag $RELEASE_TAG at HEAD."
else
  git -C "$REPO_ROOT" tag -a "$RELEASE_TAG" -m "Release $RELEASE_TAG"
  log "Created annotated tag $RELEASE_TAG."
fi

branch_name="$(ensure_named_branch)"
if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
  log "Would push branch $branch_name and tag $RELEASE_TAG to $(release_remote)."
else
  git -C "$REPO_ROOT" push -u "$(release_remote)" "$branch_name"
  git -C "$REPO_ROOT" push "$(release_remote)" "$RELEASE_TAG"
  log "Pushed branch $branch_name and tag $RELEASE_TAG."
fi

if [ "$REPO_MAINTENANCE_SKIP_GH_RELEASE" = "true" ]; then
  log "Skipping GitHub release creation because --skip-gh-release was requested."
elif ! command -v gh >/dev/null 2>&1; then
  warn "gh is unavailable, so the release tag was pushed without creating a GitHub release object."
elif [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
  log "Would create a GitHub release for $RELEASE_TAG with gh release create --verify-tag."
elif gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  log "GitHub release $RELEASE_TAG already exists."
else
  gh release create "$RELEASE_TAG" --verify-tag --generate-notes
  log "Created GitHub release $RELEASE_TAG."
fi

if [ "$REPO_MAINTENANCE_REFRESH_LIVE_SERVICE" = "true" ]; then
  staged_tool="$(release_artifact_current_dir)/SpeakSwiftlyServerTool"
  if [ "$REPO_MAINTENANCE_DRY_RUN" = "true" ]; then
    log "Would refresh the live LaunchAgent-backed service with $staged_tool using config $REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE."
  else
    [ -n "$REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE" ] || die "Live service refresh requires a non-empty config file path. Pass --live-service-config-file /absolute/path/to/server.yaml or use --skip-live-service-refresh."
    [ -f "$REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE" ] || die "Live service refresh expected a server config file at $REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE, but that file does not exist. Pass --live-service-config-file /absolute/path/to/server.yaml or use --skip-live-service-refresh."
    [ -x "$staged_tool" ] || die "Live service refresh expected the staged release tool at $staged_tool, but it was missing or not executable."
    log "Refreshing the live LaunchAgent-backed service from $staged_tool."
    "$staged_tool" launch-agent install --config-file "$REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE"
    log "Refreshed the live LaunchAgent-backed service with config $REPO_MAINTENANCE_LIVE_SERVICE_CONFIG_FILE."
  fi
else
  log "Skipping live service refresh because --skip-live-service-refresh was requested."
fi

if [ "$REPO_MAINTENANCE_RELEASE_MODE" = "submodule" ]; then
  log "Submodule release finished. Update the parent repository's submodule pointer in a separate follow-up commit."
fi

log "Release publish completed successfully."
