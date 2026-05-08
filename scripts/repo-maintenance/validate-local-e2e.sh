#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/lib"
. "$SELF_DIR/lib/common.sh"

LIVE_SERVICE_BASE_URL="${SPEAKSWIFTLYSERVER_LIVE_BASE_URL:-http://127.0.0.1:7337}"
E2E_TEST_FILTER="${SPEAKSWIFTLYSERVER_LOCAL_E2E_FILTER:-ServerTransportE2ETests}"
live_models_need_reload="false"

post_live_runtime_control() {
  path="$1"
  response_file="$(mktemp "${TMPDIR:-/tmp}/speak-swiftly-server-local-e2e.XXXXXX")"

  if ! curl -fsS -X POST "$LIVE_SERVICE_BASE_URL/$path" -o "$response_file"; then
    rm -f "$response_file"
    return 1
  fi

  rm -f "$response_file"
  return 0
}

require_live_runtime_control() {
  operation_name="$1"
  path="$2"

  post_live_runtime_control "$path" || die "Local live E2E preflight could not ask the LaunchAgent-backed service at $LIVE_SERVICE_BASE_URL to $operation_name. Confirm the live service is installed, HTTP is reachable, and no other local server is occupying the configured port."
}

reload_live_models_before_exit() {
  status="$?"
  trap - EXIT INT TERM

  if [ "$live_models_need_reload" = "true" ]; then
    log "Reloading resident models in the LaunchAgent-backed live service after local E2E."
    if post_live_runtime_control "models/reload"; then
      log "Reloaded resident models in the LaunchAgent-backed live service."
    else
      warn "Local live E2E finished with exit status $status, but the live service model reload also failed. Run curl -X POST $LIVE_SERVICE_BASE_URL/models/reload after checking the service logs."
    fi
  fi

  exit "$status"
}

ensure_git_repo

log "Running local live E2E from $REPO_ROOT."
log "Unloading resident models in the LaunchAgent-backed live service before local E2E."
require_live_runtime_control "unload resident models" "models/unload"
live_models_need_reload="true"
trap reload_live_models_before_exit EXIT INT TERM

(
  cd "$REPO_ROOT"
  SPEAKSWIFTLYSERVER_E2E=1 xcrun swift test --filter "$E2E_TEST_FILTER"
)

live_models_need_reload="false"
trap - EXIT INT TERM

log "Reloading resident models in the LaunchAgent-backed live service after local E2E."
require_live_runtime_control "reload resident models" "models/reload"
log "Local live E2E completed successfully."
