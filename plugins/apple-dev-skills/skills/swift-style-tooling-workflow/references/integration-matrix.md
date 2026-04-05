# Swift Style Tooling Integration Matrix

Use this matrix before proposing or generating setup steps.

| Surface | SwiftFormat | SwiftLint | Preferred path notes |
| --- | --- | --- | --- |
| CLI | Supported | Supported | Prefer checked-in root config files and pinned tool versions when collaborating. |
| Xcode Run Script Build Phase | Supported | Supported | Both tools document this path. Both can hit Xcode user-script sandboxing unless that setting is disabled where required. |
| Xcode source editor extension | Supported | Unsupported | This is SwiftFormat-only. The extension uses host-app-imported settings, not true per-project auto-detection. |
| Swift Package plugin | Supported as a command plugin | Supported as command and build-tool plugins | SwiftLint plugin support is stronger here. SwiftFormat documents the command plugin path. |
| AppleScript | Supported | Unsupported | SwiftFormat documents an AppleScript path that formats the frontmost Xcode document. |
| Git pre-commit hook | Supported | Supported | SwiftFormat documents a `git-format-staged` flow; SwiftLint documents `pre-commit` framework hooks. |
| GitHub Actions | Supported | Supported | SwiftFormat documents a `--reporter github-actions-log` lint path. SwiftLint exposes `github-actions-logging` reporter support, so repo-authored workflow recipes are reasonable. |
| Export Xcode extension settings to project config | Supported | Unsupported | Prefer the SwiftFormat host app `Export Configuration` flow first; use the shared-defaults script when deterministic export is needed. |

## Caveats That Change The Recommended Path

- SwiftLint build tool plugins cannot accept arbitrary `--config` paths. When the config location is incompatible, use a local `parent_config` shim or a Run Script path instead.
- SwiftFormat for Xcode does not auto-follow a project `.swiftformat` file after import. If the file changes, re-import it into the host app.
- Locally installed CLI paths are convenient but can create version drift across a team. Prefer package-managed, pinned, or otherwise repo-controlled versions where possible.
