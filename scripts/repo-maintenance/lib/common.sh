#!/usr/bin/env sh
set -eu

COMMON_DIR=${SELF_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)}
case "$(basename -- "$COMMON_DIR")" in
  repo-maintenance)
    REPO_MAINTENANCE_ROOT=$COMMON_DIR
    ;;
  *)
    REPO_MAINTENANCE_ROOT=$(CDPATH= cd -- "$COMMON_DIR/.." && pwd)
    ;;
esac
REPO_ROOT=$(CDPATH= cd -- "$REPO_MAINTENANCE_ROOT/../.." && pwd)

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

ensure_git_repo() {
  git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "The repo-maintenance toolkit must run inside a git worktree rooted at $REPO_ROOT."
}

release_artifacts_root() {
  printf '%s\n' "$REPO_ROOT/.release-artifacts"
}

release_artifact_tag_dir() {
  [ -n "${RELEASE_TAG:-}" ] || die "RELEASE_TAG must be set before resolving a tagged release artifact directory."
  printf '%s\n' "$(release_artifacts_root)/$RELEASE_TAG"
}

release_artifact_current_dir() {
  printf '%s\n' "$(release_artifacts_root)/current"
}

release_artifact_resources_dir() {
  dir="$1"
  printf '%s\n' "$dir/Resources"
}

find_speak_swiftly_metallib() {
  speak_swiftly_root="$REPO_ROOT/../SpeakSwiftly"

  for candidate in \
    "$speak_swiftly_root/.local/xcode/derived-data/Release/Build/Products/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "$speak_swiftly_root/.local/xcode/Release/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "$speak_swiftly_root/.derived/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "$speak_swiftly_root/.local/xcode/derived-data/Debug/Build/Products/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib" \
    "$speak_swiftly_root/.local/xcode/Debug/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
  do
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  die "Could not find SpeakSwiftly's default.metallib in the expected sibling Xcode build locations under $speak_swiftly_root."
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
