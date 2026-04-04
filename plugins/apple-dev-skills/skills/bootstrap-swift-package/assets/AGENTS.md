# AGENTS.md

## Baseline Provenance

- This template is the full bootstrap `AGENTS.md` used for new Swift package repositories.
- It intentionally incorporates the shared Swift-package baseline from `shared/agents-snippets/apple-swift-package-core.md`.
- Keep baseline guidance aligned with the shared snippet and use this template for deterministic scaffold output.

## Repository Expectations

- Use Swift Package Manager (SPM) as the source of truth for package structure and dependencies.
- Use `sync-swift-package-guidance` if this repo's package-specific `AGENTS.md` guidance later drifts and needs to be refreshed or merged forward.
- Prefer `swift package` CLI commands for structural changes whenever the command exists.
- Use `swift package add-dependency` to add dependencies instead of hand-editing package graphs.
- Use `swift package add-target` to add library, executable, or test targets.
- For package configuration not covered by CLI commands, update `Package.swift` intentionally and keep edits minimal.
- Keep package graph updates together in the same change (`Package.swift`, `Package.resolved`, and target/test layout when applicable).
- Validate package changes with:
  - `swift build`
  - `swift test`

## Swift Coding Preferences

- Prefer the simplest correct Swift that is easiest to read, reason about, and maintain.
- Treat idiomatic Swift and Cocoa-style naming conventions as tools in service of readability, not goals by themselves.
- Prefer explicit, consistent, and unambiguous names.
- Prefer compact and concise code; use shorthand syntax and trailing-closure syntax when readability improves.
- Do not add boilerplate, helper types, or extra layers just to make code look more architectural or more "Swifty".
- Strongly prefer synthesized, implicit, and framework-provided behavior over handwritten setup code.
- Prefer applicable existing framework or platform error types before inventing custom error wrappers or error hierarchies.
- Prefer stable, source-of-truth naming across layers when the data and meaning have not changed.
- Treat naming consistency as a reliability feature: if the same data still serves the same purpose, keep the same name.
- Do not rename fields just to match local style conventions when the external schema is already clear and stable.
- Do not use automatic case-conversion strategies such as `.convertFromSnakeCase` or `.convertToSnakeCase` unless the project explicitly wants that behavior and it clearly improves readability overall.
- This guidance is optimized for an advanced Swift reader and may prefer dense but readable modern Swift over beginner-style explicitness.

## Types and Architecture

- Prefer concrete, straightforward types and data flow that keep the code easy to follow.
- Use `struct`, `enum`, `class`, `actor`, and protocols only when each one is the clearest fit for the actual problem.
- Mark classes as `final` by default.
- Prefer synthesized conformances (`Codable`, `Equatable`, `Hashable`, etc.) whenever they satisfy the actual requirements.
- Prefer memberwise and otherwise synthesized initializers, default property values, and framework defaults over handwritten setup code.
- Do not add `CodingKeys`, manual `Codable`, custom initializers, wrappers, helper types, protocols, coordinators, or extra layers unless they are required by a concrete constraint or make the final code clearly easier to understand.
- When an API, cloud service, or wire format already provides clear names, preserve those names directly in Swift models and nearby code unless the meaning actually changes or a concrete collision must be resolved.
- Preserve raw wire and persistence shapes by default; do not add DTO, domain, or view-model conversion layers unless meaning actually changes or a concrete boundary requires it.
- Treat redundant wrappers, rename-and-copy layers, and duplicated logic as anti-patterns by default.
- Use enums as namespaces only when they genuinely reduce clutter instead of adding indirection.
- Keep code modular and cohesive without fragmenting simple logic across unnecessary files or types.
- Prefer pure Swift solutions where practical.

## Concurrency and Language Mode

- Keep code compliant with Swift 6 language mode.
- Keep strict concurrency checking enabled.
- Use modern structured concurrency (`async`/`await`, task groups, actors, `AsyncSequence`) instead of legacy async patterns when it keeps the flow clearer and more direct.
- Prefer compact syntax when it improves local reasoning, including shorthand syntax, ternary expressions, trailing closures, `switch`, `map`, `filter`, `forEach`, and async iteration.
- Prefer explicit default values at initialization when they reduce optional-handling clutter and keep the code easier to follow.
- When lines, chains, or expressions get long, prefer chopping them down into a clean vertical, top-down structure with straight visual flow.
- For app-facing packages, prefer approachable concurrency defaults with main-actor isolation by default.
- Introduce parallelism where it produces clear performance gains.

## State, Frameworks, and Dependencies

- Prefer `@Observation` over Combine for observation/state propagation.
- For Apple app projects, prefer Apple-native logging facilities first and allow Swift Logging where it makes the project API clearer.
- For packages, server-side, or cross-platform Swift, prefer Swift Logging as the primary logging API.
- Prefer Swift OpenTelemetry for telemetry and instrumentation when telemetry is needed, and prefer existing ecosystem integrations over bespoke wrappers.
- Prefer frameworks and packages from Swift.org, Swift on Server, Apple, and Apple Open Source ecosystems when they simplify the code and make it easier to reason about.
- Commonly approved examples include packages such as `swift-configuration`, `swift-async-algorithms`, and `swift-algorithms`.

## Testing and Tooling Baseline

- Use Swift Testing (`import Testing`) as the default test framework.
- Avoid XCTest unless an external constraint requires it.
- Prefer Nick Lockwood's SwiftFormat and/or SwiftLint as baseline Swift formatting and linting tools; at least one should be configured and used in any Swift project.
- Keep formatting consistent with `swift-format` conventions.
- Keep linting clean against `swiftlint` with clear, maintainable rule intent.

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

## CLI Tooling Preferences

- Prefer `swift package` for package-focused workflows (dependency graph, targets, manifest intent, and local package validation).
- Prefer `swift package` subcommands for structural package edits before manually editing `Package.swift`.
- Use `swift build` and `swift test` as the default first-pass validation commands.
- Use `xcodebuild` when validating Apple platform integration details that `swift package` does not cover well (schemes, destinations, SDK-specific behavior, and configuration-specific builds/tests).
- Keep `xcodebuild` invocations explicit and reproducible (always pass scheme, destination or SDK, and configuration when relevant).
- Prefer deterministic non-interactive CLI usage in automation/CI for both `swift package` and `xcodebuild`.
