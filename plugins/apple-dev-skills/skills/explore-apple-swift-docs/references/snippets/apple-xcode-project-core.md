# Apple Xcode Project Core AGENTS Snippet

Use this snippet in repository `AGENTS.md` files when you want baseline standards for an existing native Apple app project managed through Xcode.

## General Swift Baseline

- For any Swift, Apple-framework, Apple-platform, SwiftUI, SwiftData, Observation, AppKit, UIKit, Foundation-on-Apple, or Xcode-related task, read the relevant Apple documentation first before planning, proposing, or making changes.
- Use Dash or Xcode-local documentation first, then official Apple documentation when local docs are insufficient.
- Before proposing an architecture or implementation, state the documented API behavior, lifecycle rule, or workflow requirement being relied on.
- Do not rely on memory, habit, or analogy as the primary source when Apple documentation exists.
- If Apple documentation and the current code disagree, stop and report the conflict before continuing.
- If no relevant Apple documentation can be found, say that explicitly before proceeding.
- Prefer the simplest correct Swift that is easiest to read, reason about, and maintain.
- Treat idiomatic Swift, Cocoa conventions, and modern Swift features as tools in service of readability, not as goals by themselves.
- Do not add ceremony, abstraction, or boilerplate just to make code look more architectural, more generic, or more "Swifty".
- Strongly prefer synthesized, implicit, and framework-provided behavior over custom code.
- Prefer synthesized conformances (`Codable`, `Equatable`, `Hashable`, etc.) whenever they satisfy the actual requirements.
- Prefer memberwise and otherwise synthesized initializers, default property values, and framework defaults over handwritten setup code.
- Do not add `CodingKeys`, manual `Codable` methods, custom initializers, wrappers, helper types, protocols, coordinators, or extra layers unless they are required by a concrete constraint or they make the final code clearly easier to understand.
- Prefer applicable existing framework or platform error types before inventing custom error wrappers or error hierarchies.
- Prefer direct, simple error flows and small focused error enums only when they materially improve understanding.
- Prefer stable, source-of-truth naming across layers when the data and meaning have not changed.
- Treat naming consistency as a reliability feature: if the same data still serves the same purpose, keep the same name.
- Do not rename fields just to match local style conventions when the external schema is already clear and stable.
- Do not use automatic case-conversion strategies such as `.convertFromSnakeCase` or `.convertToSnakeCase` unless the project explicitly wants that behavior and it clearly improves readability overall.
- When an API, cloud service, or wire format already provides clear names, preserve those names directly in Swift models and nearby code unless the meaning actually changes or a concrete collision must be resolved.
- Preserve raw wire and persistence shapes by default; do not add DTO, domain, or view-model conversion layers unless meaning actually changes or a concrete boundary requires it.
- Treat redundant wrappers, rename-and-copy layers, and duplicated logic as anti-patterns by default.
- This guidance is optimized for an advanced Swift reader and may prefer dense but readable modern Swift over beginner-style explicitness.
- Prefer explicit names that are consistent, unambiguous, and easy to scan at the call site.
- Prefer compact syntax when it improves local reasoning, including shorthand syntax, ternary expressions, trailing closures, enums, `switch`, `map`, `filter`, `forEach`, async iteration, `AsyncSequence`, `AsyncStream`, and `AsyncAlgorithms`.
- Prefer explicit default values at initialization when they reduce optional-handling clutter and keep the code easier to follow.
- When lines, chains, or expressions get long, prefer chopping them down into a clean vertical, top-down structure with straight visual flow.
- Do not force value types by default, protocols at seams, actors by default, or other pattern slogans when a plainer concrete implementation is easier to reason about.
- Keep code compliant with Swift 6 language mode.
- Keep strict concurrency checking enabled.
- Prefer modern structured concurrency (`async`/`await`, task groups, actors) over legacy async patterns when it keeps the flow clearer and more direct.
- Prefer Swift Testing (`import Testing`) as the default test framework, and use XCTest only when a dependency or platform constraint requires it.
- Prefer first-party and top-tier Swift ecosystem packages from Apple, `swiftlang`, the Swift Server Work Group, and similarly trusted core Swift projects when they simplify the code and make it easier to reason about.
- Commonly approved examples include `swift-configuration` and `swift-async-algorithms` when they reduce bespoke code and improve readability.
- For Apple app projects, prefer Apple-native logging facilities first and allow Swift Logging where it makes the project API clearer.
- Prefer Swift OpenTelemetry for telemetry and instrumentation when telemetry is needed, and prefer existing ecosystem integrations over bespoke wrappers.
- Prefer Nick Lockwood's SwiftFormat and/or SwiftLint as the default Swift formatting and linting tools; at least one should be configured and used in any Swift project.
- Keep automation and CI commands deterministic, non-interactive, and explicit about toolchain, platform, and configuration assumptions.

## SwiftUI and State Architecture

- Treat SwiftUI views as component UI: keep them small, composable, reusable, and easy to scan from top to bottom.
- Prefer straight, top-down data flow with small focused controller classes that own matching state for a view or small view cluster.
- Do not build monolithic views, monolithic controllers, or broad shared mutable state when a smaller component boundary would be clearer.
- Keep updates to view-driving state minimal and localized.
- Prefer durable identity for types that drive SwiftUI state and view updates.
- Treat `App` as the application entry and scene composition boundary, `Scene` as the container for scene-specific lifecycle and environment, and `View` as the component rendering layer.
- Use app-level lifecycle concerns at the `App` boundary, scene lifecycle concerns at the `Scene` boundary, and view-local active or presentation behavior inside views.
- Use `@Binding` to pass a focused writable piece of parent-owned state into a child view.
- Use `@Bindable` when working with an observable model that should project bindings to its mutable properties in a view.
- Prefer `@Query` for view-driven SwiftData fetching that should stay in sync with the model context; use explicit fetches only when the view should not be driven by a live query.
- Prefer environment values for shared context that truly belongs to the surrounding hierarchy, not as a dumping ground for unrelated dependencies.
- Prefer key-path-based APIs, predicates, and sort descriptors when they keep data access direct and readable.
- Extract repeated chains of view modifiers into custom view modifiers early when that reduces clutter and clearly matches a view or family of views.

## Xcode Workspace and Project Baseline

- Treat the `.xcworkspace` or `.xcodeproj` as the source of truth for Apple platform app integration, schemes, build settings, destinations, and target membership.
- Prefer edits through Xcode-aware project structure and keep project file changes intentional and reviewed closely.
- Use `xcodebuild` for Apple platform integration validation, including scheme, destination or SDK, and configuration-specific build or test runs.
- Keep `xcodebuild` invocations reproducible in automation by passing explicit schemes, destinations or SDKs, and configurations when relevant.
- Prefer direct filesystem edits in Xcode-managed scope only when the workflow already accounts for project-file and scheme integrity.
- Never edit `.pbxproj` files directly. If a project-file change is needed and no safe project-aware tool is available, stop and ask for an Xcode-mediated project change instead.
