# AGENTS.md

## Apple / Xcode Project Workflow

- Use `xcode-app-project-workflow` for normal work inside this existing Xcode project.
- Use `sync-xcode-project-guidance` when the repo guidance for this project drifts and needs to be refreshed or merged forward.
- Use `scripts/repo-maintenance/validate-all.sh` for local maintainer validation, `scripts/repo-maintenance/sync-shared.sh` for repo-local sync steps, and `scripts/repo-maintenance/release.sh` for releases.
- Read relevant Apple documentation before proposing or making Xcode, SwiftUI, lifecycle, architecture, or build-configuration changes.
- Prefer Dash or local Apple docs first, then official Apple docs when local docs are insufficient.
- Prefer the simplest correct Swift that is easiest to read and reason about.
- Prefer synthesized and framework-provided behavior over extra wrappers and boilerplate.
- Keep data flow straight and dependency direction unidirectional.
- Treat the `.xcworkspace` or `.xcodeproj` as the source of truth for app integration, schemes, and build settings.
- Prefer Xcode-aware tooling or `xcodebuild` over ad hoc filesystem assumptions when project structure or target membership is involved.
- Never edit `.pbxproj` files directly. If a project-file change is needed and no safe project-aware tool is available, stop and make that change through Xcode instead.
- Validate Xcode-project changes with explicit `xcodebuild` commands when build or test integrity matters.
