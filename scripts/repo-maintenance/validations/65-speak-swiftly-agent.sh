#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

agent_dir="$REPO_ROOT/Tools/SpeakSwiftlyAgent"

if [ ! -d "$agent_dir" ]; then
  log "Skipping SpeakSwiftlyAgent validation because $agent_dir is not present."
  exit 0
fi

command -v uv >/dev/null 2>&1 || die "SpeakSwiftlyAgent validation requires uv. Install uv before running the local maintainer gate."

log "Validating SpeakSwiftlyAgent Python maintainer tool."
(
  cd "$agent_dir"
  uv run pytest
  uv run ruff check .
  uv run mypy .
)
