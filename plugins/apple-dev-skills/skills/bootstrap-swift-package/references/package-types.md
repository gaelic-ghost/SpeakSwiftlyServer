# Swift Package Type Guide

## Package Types

- `library`: reusable code consumed by other packages or apps. Default choice.
- `executable`: runnable command-line package with an entry point. Default CLI choice.
- `tool`: advanced explicit passthrough to `swift package init --type tool`. Use this only when the active Swift toolchain's tool template is explicitly desired; otherwise prefer `executable`.

Choose `library` unless you explicitly need a runnable CLI (`executable` or `tool`).

## Platform Presets

- `mac`: macOS only.
- `macos`: Alias for `mac`.
- `mobile`: iOS only.
- `ios`: Alias for `mobile`.
- `multiplatform`: iOS + macOS.
- `both`: Alias for `multiplatform`.

Choose `multiplatform` unless platform scope is explicitly constrained.

## Version Profiles

- `latest-major`: iOS `26.0`, macOS `26.0`
- `current-minus-one`: iOS `18.0`, macOS `15.0` (default)
- `current-minus-two`: iOS `17.0`, macOS `14.0`
- `latest`: Alias for `latest-major`
- `minus-one`: Alias for `current-minus-one`
- `minus-two`: Alias for `current-minus-two`

The bootstrap script applies these by patching `Package.swift` with string platform versions.

## Testing Modes

- Supported and validated Swift toolchain floor: `5.10+`.
- Toolchains older than `5.10`, including `5.9`, are outside the supported bootstrap floor and should be blocked with clear upgrade guidance.
- `swift-testing`: preferred default on current toolchains that expose `swift package init --enable-swift-testing`.
- `xctest`: use when the package must stay on XCTest or when the active toolchain does not support Swift Testing selection the way the workflow requires.

On supported Swift toolchains, the bootstrap workflow should prefer `swift package init` testing flags over patching stale templates after the fact. When the active toolchain is older than `5.10`, stop with a clear blocked message instead of attempting best-effort compatibility below the supported floor. When `swift-testing` is requested on a supported toolchain that still lacks the relevant selection flags, stop with a clear toolchain error instead of silently claiming Swift Testing support that the local CLI cannot provide.

When `xctest` is requested on a supported toolchain that exposes no testing-selection flags at all, the workflow may rely on the toolchain's default XCTest template and then verify the generated package shape instead of pretending newer flags exist. If a supported toolchain exposes partial testing-selection flags but still cannot guarantee the requested mode, stop with a clear blocked message instead of guessing.

Executable and tool package templates may still require follow-up test-target alignment on some toolchains. When that happens, keep the package shape simple and make the generated test file match the selected testing mode.

## Build Path Guidance

- Use `swift build` and `swift test` by default for ordinary Swift package work.
- Hand off to `xcode-app-project-workflow` when the package build needs Xcode-managed SDK or toolchain behavior, such as builds that depend on Xcode-only components or Apple toolchain paths that are more reliable through `xcodebuild`.
- In those cases, confirm package scheme visibility first with `xcodebuild -list -json`, then use package-oriented `xcodebuild` commands such as:
  - `xcodebuild -scheme <PackageName> -destination 'generic/platform=macOS' build`
  - `xcodebuild -scheme <PackageName> -destination 'platform=macOS' test`

This path is especially relevant when the active Xcode toolchain is responsible for components like the Metal toolchain or other Apple-managed build assets that plain SwiftPM invocation may not surface the same way.
