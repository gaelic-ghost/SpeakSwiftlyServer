# SwiftFormat for Xcode Config Export

Authoritative sources:

- [SwiftFormat README](https://github.com/nicklockwood/SwiftFormat/blob/main/README.md)
- [SwiftFormat AppDelegate.swift](https://github.com/nicklockwood/SwiftFormat/blob/main/EditorExtension/Application/Source/AppDelegate.swift)
- [SwiftFormat OptionsStore.swift](https://github.com/nicklockwood/SwiftFormat/blob/main/EditorExtension/Shared/OptionsStore.swift)
- [SwiftFormat RulesStore.swift](https://github.com/nicklockwood/SwiftFormat/blob/main/EditorExtension/Shared/RulesStore.swift)

## Preferred Supported Path

Use the `SwiftFormat for Xcode` host app and choose `File > Export Configuration`.

Why this is the preferred path:

- It is the tool's supported export workflow.
- It serializes the currently loaded host-app configuration into a normal SwiftFormat config file.
- It matches the upstream app behavior rather than depending on local reverse engineering.

## Deterministic Fallback Path

Use `scripts/export_swiftformat_xcode_config.py` when you need a scriptable export from the SwiftFormat shared defaults domain.

Example:

```bash
skills/swift-style-tooling-workflow/scripts/export_swiftformat_xcode_config.py --output .swiftformat
```

The script reads the shared UserDefaults suite `com.charcoaldesign.SwiftFormat` and reconstructs a config file from:

- `rules`
- `format-options`
- `infer-options`

## Behavioral Notes

- When `infer-options` is enabled, the host app intentionally avoids exporting the full option set. The script mirrors that behavior by exporting only explicit Swift-version or language-mode values plus the selected rules.
- The script produces an explicit, deterministic config file. It is optimized for reproducibility and reviewability rather than minimal diff size.
- If the host app cannot see the current project config automatically, export the file, add it to the project root, then re-import it into the host app when you want the extension to use that config again.
