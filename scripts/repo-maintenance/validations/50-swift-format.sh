#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

command -v swiftformat >/dev/null 2>&1 || die "SwiftFormat is required for repository validation. Install it before running scripts/repo-maintenance/validate-all.sh."
[ -f "$REPO_ROOT/.swiftformat" ] || die "Expected $REPO_ROOT/.swiftformat to exist."

log "Checking Swift formatting with the checked-in SwiftFormat config."
cd "$REPO_ROOT"
swiftformat --lint --config .swiftformat .
