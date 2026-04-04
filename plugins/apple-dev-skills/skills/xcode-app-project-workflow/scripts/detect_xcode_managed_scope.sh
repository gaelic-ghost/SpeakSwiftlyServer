#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  detect_xcode_managed_scope.sh [PATH]

Return JSON describing whether PATH contains Xcode-managed markers
(.xcodeproj, .xcworkspace, .pbxproj) within depth 4.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

ROOT="${1:-.}"
if [ ! -d "$ROOT" ]; then
  echo "{\"managed\":false,\"reason\":\"path-not-directory\",\"path\":\"$ROOT\"}"
  exit 0
fi

found="$(find "$ROOT" -maxdepth 4 \( -name "*.xcodeproj" -o -name "*.xcworkspace" -o -name "*.pbxproj" \) -print 2>/dev/null | head -n 20)"

if [ -n "$found" ]; then
  printf '{"managed":true,"path":"%s","markers":[\n' "$ROOT"
  first=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "$first" -eq 0 ]; then
      printf ',\n'
    fi
    first=0
    esc="${line//\"/\\\"}"
    printf '  "%s"' "$esc"
  done <<< "$found"
  printf '\n]}\n'
else
  printf '{"managed":false,"path":"%s","markers":[]}\n' "$ROOT"
fi
