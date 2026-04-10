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
  metadata_path="$(speak_swiftly_runtime_metadata_path Release)"
  runtime_metallib_path="$(speak_swiftly_runtime_metadata_value "$metadata_path" metallib_path)"
  [ -n "$runtime_metallib_path" ] || die "SpeakSwiftly runtime metadata at $metadata_path did not include a metallib_path value."
  runtime_metallib_path="$(rebase_speak_swiftly_runtime_path "$metadata_path" "$runtime_metallib_path")"
  [ -f "$runtime_metallib_path" ] || die "SpeakSwiftly runtime metadata at $metadata_path pointed at a missing metallib path: $runtime_metallib_path"
  printf '%s\n' "$runtime_metallib_path"
}

speak_swiftly_runtime_root() {
  printf '%s\n' "$REPO_ROOT/../SpeakSwiftly/.local/xcode"
}

speak_swiftly_runtime_metadata_path() {
  configuration="$1"
  lower_configuration=$(printf '%s' "$configuration" | tr '[:upper:]' '[:lower:]')
  metadata_path="$(speak_swiftly_runtime_root)/SpeakSwiftly.$lower_configuration.json"
  [ -f "$metadata_path" ] || die "Could not find SpeakSwiftly's published $configuration runtime metadata at $metadata_path. Publish and verify the sibling runtime first."
  printf '%s\n' "$metadata_path"
}

speak_swiftly_runtime_metadata_value() {
  metadata_path="$1"
  key="$2"
  value=$(sed -n "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"\\(.*\\)\"[[:space:]]*,\{0,1\}[[:space:]]*$/\\1/p" "$metadata_path" | head -n 1)
  printf '%s\n' "$value"
}

rebase_speak_swiftly_runtime_path() {
  metadata_path="$1"
  runtime_path="$2"

  if [ -f "$runtime_path" ]; then
    printf '%s\n' "$runtime_path"
    return 0
  fi

  metadata_source_root="$(speak_swiftly_runtime_metadata_value "$metadata_path" source_root)"
  actual_source_root="$(CDPATH= cd -- "$REPO_ROOT/../SpeakSwiftly" && pwd)"

  case "$runtime_path" in
    "$metadata_source_root"/*)
      suffix=${runtime_path#"$metadata_source_root"/}
      rebased_path="$actual_source_root/$suffix"
      if [ -f "$rebased_path" ]; then
        printf '%s\n' "$rebased_path"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$runtime_path"
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
