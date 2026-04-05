#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

workflow_path="$REPO_ROOT/.github/workflows/validate-repo-maintenance.yml"

if [ ! -f "$workflow_path" ]; then
  log "Skipping CI wrapper validation because $workflow_path is not present."
  exit 0
fi

grep -Fq "scripts/repo-maintenance/validate-all.sh" "$workflow_path" || die "Expected $workflow_path to call scripts/repo-maintenance/validate-all.sh."
