# Project Generator Notes

## Purpose

Describe the supported generator choices for `bootstrap-xcode-app-project`.

## Supported Generator Modes

### `xcodegen`

- Use when the user explicitly prefers reproducible generated project files.
- This is the currently supported mutating implementation path in the first iteration of the skill.
- Reference:
  - [XcodeGen Project Spec documentation](https://yonaskolb.github.io/XcodeGen/Docs/ProjectSpec.html)
  - [XcodeGen repository](https://github.com/yonaskolb/XcodeGen)

### `xcode`

- Use when the user explicitly prefers the standard Xcode-created-project flow.
- Treat this as a guided path in the first implementation pass.
- Do not pretend the skill has a safe full GUI automation path unless that support is actually implemented and validated.
- Reference:
  - [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating_an_xcode_project_for_an_app)

### `ask`

- Use when the request does not make the generator preference clear.
- Block with a concise next step instead of silently choosing a generator.

## Policy

- Be cautious about centering the whole workflow around `XcodeGen`. It is an extra dependency and an extra abstraction layer, so it should only be preferred when it clearly improves reproducibility or team maintenance.
- Treat the standard Xcode path as the baseline conceptual model because it reflects Apple's first-party project-creation flow.
