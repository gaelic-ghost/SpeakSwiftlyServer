# SwiftFormat Surfaces

Authoritative source: [SwiftFormat README](https://github.com/nicklockwood/SwiftFormat/blob/main/README.md)

## Supported Surfaces

- CLI
- Xcode source editor extension through the `SwiftFormat for Xcode` host app
- Xcode Run Script Build Phase
- Swift Package Manager command plugin
- AppleScript
- Git pre-commit hook
- GitHub Actions

## Preferred Path Notes

- Prefer a checked-in `.swiftformat` file at the project root for shared repos.
- Prefer pinned package-managed or project-managed installs over purely developer-local CLI installs when the output is committed.
- The Xcode extension is convenient for interactive formatting but does not give true per-project config auto-discovery. Import the config into the host app and re-import after project config changes.

## High-Signal Caveats

- For Xcode build phases, SwiftFormat documents that `ENABLE_USER_SCRIPT_SANDBOXING` must be `NO` on newer Xcode versions for the script path to work correctly.
- The host app can import and export config files, which is the preferred supported path for turning extension settings into a shared config.
- The scriptable export path should be described as a deterministic fallback, not as the primary supported upstream workflow.
