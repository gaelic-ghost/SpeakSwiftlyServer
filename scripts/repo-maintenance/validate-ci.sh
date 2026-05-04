#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

load_profile_env
load_env_file "$SELF_DIR/config/validation.env"
ensure_git_repo

log "Running remote CI validation from $REPO_ROOT with the $REPO_MAINTENANCE_PROFILE profile."

for step in \
  10-toolkit-layout.sh \
  20-agents-guidance.sh \
  25-codex-plugin.sh \
  30-ci-wrapper.sh \
  35-swift-package.sh
do
  script="$SELF_DIR/validations/$step"
  [ -f "$script" ] || die "Remote CI validation expected $script to exist."
  log "Running remote CI validation step $step"
  sh "$script"
done

log "Remote CI validation completed successfully."
