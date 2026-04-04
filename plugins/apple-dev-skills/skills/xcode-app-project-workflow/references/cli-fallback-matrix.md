# CLI Fallback Matrix

## Build and test

- Xcode project/workspace build:
  - `xcodebuild -project <proj.xcodeproj> -scheme <scheme> build`
  - `xcodebuild -workspace <ws.xcworkspace> -scheme <scheme> build`
- Xcode tests:
  - `xcodebuild test -project <proj.xcodeproj> -scheme <scheme> -destination '<dest>'`

## Runtime and tooling

- Tool lookup:
  - `xcrun --find swift`
  - `xcrun --find xcodebuild`
- Simulator-related tools:
  - `xcrun simctl list`

## SwiftPM

- Build:
  - `swift build`
- Test:
  - `swift test`
- Run executable target:
  - `swift run <target>`
- Package commands:
  - `swift package describe`
  - `swift package resolve`
  - `swift package update`
  - `swift package test` (alias behavior varies by toolchain; prefer `swift test` for test execution)
- Xcode-managed package fallback when the package needs Xcode SDK or toolchain behavior:
  - confirm package scheme discovery first with `xcodebuild -list -json`
  - build with `xcodebuild -scheme <PackageName> -destination 'generic/platform=macOS' build`
  - test with `xcodebuild -scheme <PackageName> -destination 'platform=macOS' test`
  - use this path when plain SwiftPM invocation is insufficient for Apple-managed toolchain components or build assets surfaced through Xcode

## Fallback message content

Include:
- command used
- reason MCP path was unavailable
- concise MCP setup offer (cooldown-gated)
