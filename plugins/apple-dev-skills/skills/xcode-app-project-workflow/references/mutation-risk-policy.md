# Mutation Risk Policy for Xcode-Managed Projects

## Detect managed scope

Treat scope as managed if project context includes any of:
- `*.xcodeproj`
- `*.xcworkspace`
- `*.pbxproj`

Use `scripts/detect_xcode_managed_scope.sh` to probe quickly.

## Safer alternatives to offer first

1. Xcode MCP mutation tools (`XcodeWrite`, `XcodeUpdate`, `XcodeMV`, `XcodeRM`, `XcodeMakeDir`).
2. Official CLI workflows (`xcodebuild`, `swift`, `xcrun`) where applicable.
3. User-performed changes in Xcode UI when direct file edits are risky.

## Last-resort direct edit conditions

Direct mutation is allowed only if:
- user received explicit risk warning,
- safer method was offered,
- tooling setup/allowlist path was offered,
- user explicitly opted in,
- Xcode.app is closed during direct edits.

If these conditions are not met, stop and ask for missing requirement.
