# AGENTS.md

- Use `xcode-app-project-workflow` for normal work inside this existing Xcode project.
- Use `sync-xcode-project-guidance` when this repo's local workflow guidance drifts and should be refreshed or merged forward.
- Read relevant Apple documentation before proposing or making Xcode, SwiftUI, lifecycle, or architecture changes.
- Prefer the simplest correct Swift that is easiest to read and reason about.
- Prefer synthesized and framework-provided behavior over extra wrappers and boilerplate.
- Keep data flow straight and dependency direction unidirectional.
- Never edit `.pbxproj` files directly. If a project-file change is needed and no safe project-aware tool is available, stop and make that change through Xcode instead.
