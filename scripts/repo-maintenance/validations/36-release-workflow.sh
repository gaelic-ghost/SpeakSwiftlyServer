#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
export REPO_MAINTENANCE_COMMON_DIR="$SELF_DIR/../lib"
. "$SELF_DIR/../lib/common.sh"

release_script="$REPO_MAINTENANCE_ROOT/release.sh"

require_text() {
  needle="$1"
  haystack="$2"
  context="$3"

  printf '%s\n' "$haystack" | grep -F -- "$needle" >/dev/null || die "$context. Expected to find: $needle"
}

line_number() {
  needle="$1"
  line="$(grep -n -F -- "$needle" "$release_script" | tail -n 1 | cut -d: -f1)"
  [ -n "$line" ] || die "Release workflow validation could not find required source text: $needle"
  printf '%s\n' "$line"
}

sh -n "$release_script"

help_output="$(sh "$release_script" --help)"
require_text "--skip-local-e2e" "$help_output" "Release help is missing the local E2E opt-out"
require_text "--skip-live-service-update" "$help_output" "Release help is missing the live-service opt-out"

require_text 'base_worktree="$(base_branch_worktree)"' "$(cat "$release_script")" "Standard release mode must locate the main-owning worktree"
require_text 'git -C "$base_worktree" merge --ff-only "origin/$base_branch"' "$(cat "$release_script")" "Standard release mode must fast-forward the main-owning worktree without rebase configuration"
require_text 'xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live' "$(cat "$release_script")" "Standard release mode must promote the live service"
require_text 'xcrun swift run SpeakSwiftlyServerTool healthcheck' "$(cat "$release_script")" "Standard release mode must healthcheck HTTP and MCP after promotion"
require_text 'Would wait for GitHub to report initial checks on PR #$pr_number.' "$(cat "$release_script")" "Release dry-run must not query GitHub for its simulated pull request"

validation_line="$(grep -n -F 'sh "$SELF_DIR/validate-all.sh"' "$release_script" | head -n 1 | cut -d: -f1)"
[ -n "$validation_line" ] || die "Release workflow validation could not find the standard maintainer gate."
e2e_line="$(line_number 'run_local_e2e_gate')"
version_line="$(line_number 'run_version_bump')"
promotion_line="$(line_number 'update_live_service "$base_worktree"')"
github_release_line="$(line_number 'create_github_release')"

[ "$validation_line" -lt "$e2e_line" ] || die "Standard release mode must run local live E2E after the normal maintainer gate."
[ "$e2e_line" -lt "$version_line" ] || die "Standard release mode must run local live E2E before release branch publication work."
[ "$github_release_line" -lt "$promotion_line" ] || die "Standard release mode must promote and healthcheck the live service only after the GitHub release exists."

log "Verified standard release workflow flags, worktree handoff, live gates, and ordering."
