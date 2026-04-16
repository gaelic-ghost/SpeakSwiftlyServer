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

release_remote() {
  printf '%s\n' "${REPO_MAINTENANCE_DEFAULT_RELEASE_REMOTE:-origin}"
}

release_branch() {
  printf '%s\n' "${REPO_MAINTENANCE_DEFAULT_RELEASE_BRANCH:-main}"
}

current_branch() {
  git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true
}

ensure_named_branch() {
  branch_name="$(current_branch)"
  [ -n "$branch_name" ] || die "Release workflow requires a named branch instead of detached HEAD."
  printf '%s\n' "$branch_name"
}

ensure_clean_worktree() {
  status_output="$(git -C "$REPO_ROOT" status --porcelain)"
  [ -z "$status_output" ] || die "Release workflow requires a clean worktree before continuing."
}

ensure_release_tag_format() {
  case "${RELEASE_TAG:-}" in
    v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*.[0-9]*-*)
      ;;
    *)
      die "Release tag must use vX.Y.Z SemVer syntax."
      ;;
  esac
}

ensure_on_release_branch() {
  branch_name="$(ensure_named_branch)"
  expected_branch="$(release_branch)"
  [ "$branch_name" = "$expected_branch" ] || die "Release publish must run from $expected_branch. Current branch is $branch_name."
}

ensure_not_on_release_branch() {
  branch_name="$(ensure_named_branch)"
  protected_branch="$(release_branch)"
  [ "$branch_name" != "$protected_branch" ] || die "Release prepare must run from a feature branch or worktree, not from $protected_branch. Use release-publish.sh instead."
}

ensure_gh_cli() {
  command -v gh >/dev/null 2>&1 || die "This workflow requires the GitHub CLI (`gh`) to be installed and authenticated."
}

sync_local_release_branch() {
  remote_name="$(release_remote)"
  branch_name="$(release_branch)"

  git -C "$REPO_ROOT" fetch "$remote_name" "$branch_name"

  local_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  remote_sha="$(git -C "$REPO_ROOT" rev-parse "$remote_name/$branch_name")"

  if [ "$local_sha" = "$remote_sha" ]; then
    log "Local $branch_name already matches $remote_name/$branch_name."
    return 0
  fi

  if git -C "$REPO_ROOT" merge-base --is-ancestor "$local_sha" "$remote_sha"; then
    if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
      log "Would fast-forward local $branch_name to $remote_name/$branch_name."
    else
      git -C "$REPO_ROOT" pull --ff-only "$remote_name" "$branch_name"
      log "Fast-forwarded local $branch_name to $remote_name/$branch_name."
    fi
    return 0
  fi

  if git -C "$REPO_ROOT" merge-base --is-ancestor "$remote_sha" "$local_sha"; then
    die "Local $branch_name has commits that are not on $remote_name/$branch_name. Push or reconcile that branch before publishing a release."
  fi

  die "Local $branch_name and $remote_name/$branch_name have diverged. Reconcile them before publishing a release."
}

swiftpm() {
  if command -v xcrun >/dev/null 2>&1; then
    xcrun swift "$@"
    return
  fi
  swift "$@"
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

stage_release_artifact() {
  artifact_root="$(release_artifacts_root)"
  tag_dir="$(release_artifact_tag_dir)"
  current_link="$(release_artifact_current_dir)"

  if [ "${REPO_MAINTENANCE_DRY_RUN:-false}" = "true" ]; then
    log "Would build SpeakSwiftlyServerTool in release mode and stage it under $tag_dir."
    log "Would refresh $current_link to point at $RELEASE_TAG."
    return 0
  fi

  log "Building SpeakSwiftlyServerTool in release mode."
  swiftpm build -c release --product SpeakSwiftlyServerTool

  bin_path="$(swiftpm build -c release --show-bin-path)"
  source_tool="$bin_path/SpeakSwiftlyServerTool"
  [ -f "$source_tool" ] || die "Release build completed, but the expected tool executable was not found at $source_tool."
  [ -x "$source_tool" ] || die "Release build completed, but $source_tool is not executable."
  source_metallib="$(find_speak_swiftly_metallib)"

  mkdir -p "$tag_dir"
  cp "$source_tool" "$tag_dir/SpeakSwiftlyServerTool"
  chmod 755 "$tag_dir/SpeakSwiftlyServerTool"
  resources_dir="$(release_artifact_resources_dir "$tag_dir")"
  mkdir -p "$resources_dir"
  cp "$source_metallib" "$resources_dir/default.metallib"

  mkdir -p "$artifact_root"
  rm -f "$current_link"
  ln -s "$RELEASE_TAG" "$current_link"

  log "Staged release artifact at $tag_dir/SpeakSwiftlyServerTool."
  log "Staged metallib resource at $resources_dir/default.metallib."
  log "Updated current release artifact link at $current_link."
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
