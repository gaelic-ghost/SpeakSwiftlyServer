# Xcode Project Detection Notes

## Current Detection Rules

- Treat `.xcworkspace` and `.xcodeproj` markers as the positive signal for an existing Xcode-managed app repo.
- Treat a repo with only `Package.swift` and no Xcode markers as out of scope for this skill.
- Prefer repo-root detection over deep project surgery. This skill syncs repo guidance; it does not repair Xcode project structure.

## Guidance Boundaries

- This skill owns repo-guidance alignment for existing Xcode app repos.
- `xcode-app-project-workflow` owns active execution, docs lookup, mutation, build, test, and run work.
- `bootstrap-xcode-app-project` owns new-project creation from nothing.
