#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

command -v swiftlint >/dev/null 2>&1 || die "SwiftLint is required for repository validation. Install it before running scripts/repo-maintenance/validate-all.sh."
[ -f "$REPO_ROOT/.swiftlint.yml" ] || die "Expected $REPO_ROOT/.swiftlint.yml to exist."

log "Running SwiftLint with the checked-in repository config."
cd "$REPO_ROOT"
swiftlint lint --config .swiftlint.yml
