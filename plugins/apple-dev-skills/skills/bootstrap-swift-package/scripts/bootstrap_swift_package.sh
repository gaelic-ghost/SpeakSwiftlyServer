#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  bootstrap_swift_package.sh --name <PackageName> [--type library|executable|tool] [--destination <dir>] [--platform mac|macos|mobile|ios|multiplatform|both] [--version-profile latest-major|current-minus-one|current-minus-two|latest|minus-one|minus-two] [--testing-mode swift-testing|xctest] [--skip-validation] [--skip-git-init] [--skip-copy-agents]

Examples:
  bootstrap_swift_package.sh --name MyLibrary
  bootstrap_swift_package.sh --name MyExecutable --type executable --destination /tmp --platform mac
  bootstrap_swift_package.sh --name MyTool --type tool --platform mobile --version-profile minus-two
  bootstrap_swift_package.sh --name MyCrossPlatformLib --platform both --version-profile minus-one
  bootstrap_swift_package.sh --name iOSOnlyLib --platform ios
  bootstrap_swift_package.sh --name MacOnlyLib --platform macos
USAGE
}

blocked() {
  echo "$*" >&2
  exit 2
}

failed() {
  echo "$*" >&2
  exit 1
}

load_swift_version() {
  swift_version_output="$(swift --version 2>/dev/null || true)"
  if [[ -z "$swift_version_output" ]]; then
    blocked "Unable to determine the local Swift toolchain version. The bootstrap skill supports Swift 5.10+."
  fi

  if [[ "$swift_version_output" =~ Swift[[:space:]]+version[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
    swift_major_version="${BASH_REMATCH[1]}"
    swift_minor_version="${BASH_REMATCH[2]}"
    return 0
  fi

  blocked "Unable to parse the local Swift toolchain version from 'swift --version'. The bootstrap skill supports Swift 5.10+."
}

ensure_supported_swift_toolchain() {
  load_swift_version

  if (( swift_major_version < 5 )); then
    blocked "Swift $swift_major_version.$swift_minor_version is too old for this bootstrap workflow. The supported and validated floor is Swift 5.10+."
  fi

  if (( swift_major_version == 5 && swift_minor_version < 10 )); then
    blocked "Swift $swift_major_version.$swift_minor_version is too old for this bootstrap workflow. The supported and validated floor is Swift 5.10+."
  fi
}

name=""
pkg_type="library"
destination="."
platform_mode="multiplatform"
version_profile="current-minus-one"
testing_mode="swift-testing"
run_validation="true"
initialize_git="true"
copy_agents="true"
probe_testing_mode="false"
probe_bootstrap_inputs="false"

ios_version=""
macos_version=""
swift_version_output=""
swift_major_version=""
swift_minor_version=""
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agents_template="$script_dir/../assets/AGENTS.md"

is_ignorable_directory_entry() {
  local entry_name="$1"
  case "$entry_name" in
    .DS_Store|.AppleDouble|.LSOverride|Icon$'\r'|._*|.Spotlight-V100|.Trashes|.fseventsd)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

directory_has_non_ignorable_entries() {
  local dir="$1"
  local entry_path=""
  local entry_name=""

  while IFS= read -r -d '' entry_path; do
    entry_name="${entry_path##*/}"
    if ! is_ignorable_directory_entry "$entry_name"; then
      return 0
    fi
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null || true)

  return 1
}

set_version_targets() {
  case "$version_profile" in
    latest-major)
      ios_version="26.0"
      macos_version="26.0"
      ;;
    current-minus-one)
      ios_version="18.0"
      macos_version="15.0"
      ;;
    current-minus-two)
      ios_version="17.0"
      macos_version="14.0"
      ;;
    *)
      echo "Unsupported --version-profile: $version_profile" >&2
      exit 1
      ;;
  esac
}

platforms_snippet() {
  case "$platform_mode" in
    mac)
      cat <<EOF
    platforms: [
        .macOS("$macos_version"),
    ],
EOF
      ;;
    mobile)
      cat <<EOF
    platforms: [
        .iOS("$ios_version"),
    ],
EOF
      ;;
    multiplatform)
      cat <<EOF
    platforms: [
        .iOS("$ios_version"),
        .macOS("$macos_version"),
    ],
EOF
      ;;
    *)
      echo "Unsupported --platform: $platform_mode" >&2
      exit 1
      ;;
  esac
}

swift_package_init_supports() {
  local flag="$1"
  swift package init --help 2>/dev/null | grep -Fq -- "$flag"
}

write_swift_testing_test_file() {
  local file_path="$1"
  local module_name="$2"
  cat > "$file_path" <<EOF
import Testing
@testable import $module_name

@Test func example() async throws {
    // Write your test here and use APIs like \`#expect(...)\` to check expected conditions.
}
EOF
}

write_xctest_test_file() {
  local file_path="$1"
  local module_name="$2"
  cat > "$file_path" <<EOF
import XCTest
@testable import $module_name

final class ${module_name}Tests: XCTestCase {
    func testExample() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest
    }
}
EOF
}

configure_testing_mode() {
  local requested_mode="$1"
  local supports_swift_testing="false"
  local supports_disable_swift_testing="false"
  local supports_enable_xctest="false"
  local supports_disable_xctest="false"
  local args=()

  if swift_package_init_supports "--enable-swift-testing"; then
    supports_swift_testing="true"
  fi
  if swift_package_init_supports "--disable-swift-testing"; then
    supports_disable_swift_testing="true"
  fi
  if swift_package_init_supports "--enable-xctest"; then
    supports_enable_xctest="true"
  fi
  if swift_package_init_supports "--disable-xctest"; then
    supports_disable_xctest="true"
  fi

  case "$requested_mode" in
    swift-testing)
      if [[ "$supports_swift_testing" != "true" ]]; then
        echo "The active 'swift package init' command does not support Swift Testing selection flags. Choose --testing-mode xctest or use a newer Swift toolchain." >&2
        exit 1
      fi
      args+=(--enable-swift-testing)
      if [[ "$supports_disable_xctest" == "true" ]]; then
        args+=(--disable-xctest)
      fi
      ;;
    xctest)
      if [[ "$supports_enable_xctest" == "true" ]]; then
        args+=(--enable-xctest)
      fi
      if [[ "$supports_disable_swift_testing" == "true" ]]; then
        args+=(--disable-swift-testing)
      fi
      ;;
    *)
      echo "Unsupported --testing-mode: $requested_mode" >&2
      exit 1
      ;;
  esac

  printf '%s\n' "${args[@]}"
}

ensure_test_target() {
  local requested_mode="$1"
  local module_name="$2"
  local test_dir="Tests/${module_name}Tests"
  local test_file="$test_dir/${module_name}Tests.swift"

  if [[ ! -d Tests ]]; then
    swift package add-target "${module_name}Tests" --type test --dependencies "$module_name" >/dev/null
  fi

  mkdir -p "$test_dir"
  case "$requested_mode" in
    swift-testing)
      write_swift_testing_test_file "$test_file" "$module_name"
      ;;
    xctest)
      write_xctest_test_file "$test_file" "$module_name"
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      name="${2:-}"
      shift 2
      ;;
    --type)
      pkg_type="${2:-}"
      shift 2
      ;;
    --destination)
      destination="${2:-}"
      shift 2
      ;;
    --platform)
      platform_mode="${2:-}"
      shift 2
      ;;
    --version-profile)
      version_profile="${2:-}"
      shift 2
      ;;
    --testing-mode)
      testing_mode="${2:-}"
      shift 2
      ;;
    --skip-validation)
      run_validation="false"
      shift
      ;;
    --skip-git-init)
      initialize_git="false"
      shift
      ;;
    --skip-copy-agents)
      copy_agents="false"
      shift
      ;;
    --probe-testing-mode)
      testing_mode="${2:-}"
      probe_testing_mode="true"
      shift 2
      ;;
    --probe-bootstrap-inputs)
      probe_bootstrap_inputs="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$platform_mode" in
  ios)
    platform_mode="mobile"
    ;;
  macos)
    platform_mode="mac"
    ;;
  both)
    platform_mode="multiplatform"
    ;;
esac

case "$version_profile" in
  latest)
    version_profile="latest-major"
    ;;
  minus-one)
    version_profile="current-minus-one"
    ;;
  minus-two)
    version_profile="current-minus-two"
    ;;
esac

if [[ -z "$name" ]]; then
  echo "--name is required" >&2
  usage >&2
  exit 2
fi

if [[ "$pkg_type" != "library" && "$pkg_type" != "executable" && "$pkg_type" != "tool" ]]; then
  blocked "--type must be 'library', 'executable', or 'tool'"
fi

if [[ "$platform_mode" != "mac" && "$platform_mode" != "mobile" && "$platform_mode" != "multiplatform" ]]; then
  blocked "--platform must be 'mac', 'mobile', or 'multiplatform' (aliases: macos, ios, both)"
fi

if [[ "$version_profile" != "latest-major" && "$version_profile" != "current-minus-one" && "$version_profile" != "current-minus-two" ]]; then
  blocked "--version-profile must be 'latest-major', 'current-minus-one', 'current-minus-two' (or aliases: latest, minus-one, minus-two)"
fi

if [[ "$testing_mode" != "swift-testing" && "$testing_mode" != "xctest" ]]; then
  blocked "--testing-mode must be 'swift-testing' or 'xctest'"
fi

if [[ ! "$name" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
  blocked "--name must start with a letter and contain only letters, numbers, underscore, or hyphen"
fi

if ! command -v swift >/dev/null 2>&1; then
  blocked "Swift is not installed or not on PATH."
fi

ensure_supported_swift_toolchain

if [[ "$initialize_git" == "true" ]] && ! command -v git >/dev/null 2>&1; then
  blocked "git is not installed or not on PATH."
fi

if [[ "$copy_agents" == "true" ]] && [[ ! -f "$agents_template" ]]; then
  blocked "Template missing: $agents_template"
fi

target_dir="$destination/$name"

if [[ -e "$destination" && ! -d "$destination" ]]; then
  blocked "Destination exists and is not a directory: $destination"
fi

if [[ -e "$target_dir" && ! -d "$target_dir" ]]; then
  blocked "Target exists and is not a directory: $target_dir"
fi

mkdir -p "$destination"

if [[ -e "$target_dir" ]] && directory_has_non_ignorable_entries "$target_dir"; then
  blocked "Target directory exists and is not empty: $target_dir"
fi

set_version_targets
init_testing_args=()
init_testing_output="$(configure_testing_mode "$testing_mode")"
while IFS= read -r arg; do
  [[ -n "$arg" ]] || continue
  init_testing_args+=("$arg")
done <<EOF
$init_testing_output
EOF

if [[ "$probe_testing_mode" == "true" ]]; then
  echo "Testing mode supported: $testing_mode"
  exit 0
fi

if [[ "$probe_bootstrap_inputs" == "true" ]]; then
  echo "Bootstrap inputs supported for: $name"
  exit 0
fi

mkdir -p "$target_dir"
(
  cd "$target_dir"
  swift package init --name "$name" --type "$pkg_type" "${init_testing_args[@]}"

  if ! grep -Eq '^[[:space:]]*platforms:[[:space:]]*\[' Package.swift; then
    snippet="$(platforms_snippet)"
    name_line_num="$(grep -nE '^[[:space:]]*name:[[:space:]]*".*",?[[:space:]]*$' Package.swift | head -n 1 | cut -d: -f1)"
    if [[ -z "$name_line_num" ]]; then
      failed "Validation failed: unable to locate package name line in Package.swift."
    fi

    {
      head -n "$name_line_num" Package.swift
      printf '%s\n' "$snippet"
      tail -n +"$((name_line_num + 1))" Package.swift
    } > Package.swift.tmp
    mv Package.swift.tmp Package.swift
  fi

  if [[ "$initialize_git" == "true" ]]; then
    git init >/dev/null 2>&1
  fi

  if [[ "$copy_agents" == "true" ]]; then
    cp "$agents_template" AGENTS.md
  fi

  ensure_test_target "$testing_mode" "$name"

  if [[ ! -f Package.swift ]]; then
    failed "Validation failed: Package.swift missing after initialization."
  fi

  if [[ "$initialize_git" == "true" ]] && [[ ! -d .git ]]; then
    failed "Validation failed: git repository was not initialized."
  fi

  if [[ "$copy_agents" == "true" ]] && [[ ! -f AGENTS.md ]]; then
    failed "Validation failed: AGENTS.md missing."
  fi

  if [[ ! -d Tests ]]; then
    failed "Validation failed: Tests target directory missing."
  fi

  if ! grep -q "${name}Tests" Package.swift; then
    failed "Validation failed: test target entry not found in Package.swift."
  fi

  if [[ "$run_validation" == "true" ]]; then
    swift build
    swift test
  fi
)

echo "Created Swift package: $target_dir"
echo "Type: $pkg_type"
echo "Platform: $platform_mode"
echo "Version profile: $version_profile (iOS $ios_version, macOS $macos_version)"
echo "Testing mode: $testing_mode"
if [[ "$initialize_git" == "true" ]]; then
  echo "Git: initialized"
else
  echo "Git: skipped"
fi
if [[ "$copy_agents" == "true" ]]; then
  echo "AGENTS: copied"
else
  echo "AGENTS: skipped"
fi
if [[ "$run_validation" == "true" ]]; then
  echo "Validation: swift build + swift test passed"
else
  echo "Validation: skipped (--skip-validation)"
fi
