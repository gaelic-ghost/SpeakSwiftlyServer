#!/usr/bin/env sh
set -eu

SELF_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SELF_DIR/../lib/common.sh"

log "Building the package with the Xcode-selected Swift toolchain."
swiftpm build

log "Running the package test suite with the Xcode-selected Swift toolchain."
swiftpm test
