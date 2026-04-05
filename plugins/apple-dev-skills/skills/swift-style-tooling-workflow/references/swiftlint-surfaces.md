# SwiftLint Surfaces

Authoritative source: [SwiftLint README](https://github.com/realm/swiftlint/blob/master/README.md)

## Supported Surfaces

- CLI
- Swift Package command plugin
- Swift Package build tool plugin
- Xcode package dependency with build tool plugin
- Xcode Run Script Build Phase
- Git `pre-commit` integration through the `pre-commit` framework
- GitHub Actions through reporter support and repo-authored workflow steps

## Preferred Path Notes

- Prefer SwiftLint plugins when the project shape supports them and the config file lives inside the package or project directory.
- Prefer a checked-in root `.swiftlint.yml` file, with `parent_config` or nested config flows when repo structure needs them.
- Prefer the Run Script Build Phase when the plugin path cannot express the needed config placement or invocation shape.

## High-Signal Caveats

- Build tool plugins cannot take arbitrary `--config` paths.
- Xcode 15+ script sandboxing can block Run Script usage unless `ENABLE_USER_SCRIPT_SANDBOXING` is disabled for that target.
- SwiftLint does not ship an Xcode source editor extension or AppleScript integration surface comparable to SwiftFormat.
