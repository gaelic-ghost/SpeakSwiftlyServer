# Bootstrap Automation Contract

## Purpose

Provide one consistent automation contract for deterministic Swift package scaffold runs.

## Inputs

- `package_name`
- `package_type`
- `destination_dir`
- `platform_preset`
- `version_profile`
- `skip_validation`

## Constraints

- `swift` and `git` must be on `PATH`.
- `assets/AGENTS.md` and `scripts/bootstrap_swift_package.sh` must exist.
- Do not overwrite a non-empty target directory.
- Keep changes scoped to `<DESTINATION_DIR>/<PACKAGE_NAME>`.

## Status Values

- `success`
- `blocked`
- `failed`

## Output

- `status`
- `path_type`
- `path`
- normalized `type`, `platform`, and `version_profile`
- validation result
- one concise follow-up note

## Codex App Prompt Template

```text
Use $bootstrap-swift-package.

Run this workflow only when a package scaffold is explicitly requested.

Create a Swift package with:
- Name: <PACKAGE_NAME>
- Type: <PACKAGE_TYPE>
- Destination directory: <DESTINATION_DIR>
- Platform preset: <PLATFORM_PRESET>
- Version profile: <VERSION_PROFILE>
- Skip validation: <SKIP_VALIDATION>

Execution requirements:
1) Run `scripts/bootstrap_swift_package.sh` with the mapped flags.
2) Refuse to overwrite a non-empty target directory.
3) Stop immediately if `swift`, `git`, or `assets/AGENTS.md` is missing.
4) If `<SKIP_VALIDATION>` is `false`, require `swift build` and `swift test` to pass.
5) Do not modify files outside `<DESTINATION_DIR>/<PACKAGE_NAME>`.

Return the documented contract only:
- `status`
- `path_type`
- `path`
- normalized scaffold options
- validation result
- blocker or next step when needed
```

## Codex CLI Prompt Template

```text
Use $bootstrap-swift-package for a deterministic CLI automation run.

Task:
Bootstrap one Swift package using `scripts/bootstrap_swift_package.sh` with:
- `--name <PACKAGE_NAME>`
- `--type <PACKAGE_TYPE>`
- `--destination <DESTINATION_DIR>`
- `--platform <PLATFORM_PRESET>`
- `--version-profile <VERSION_PROFILE>`
- include `--skip-validation` only when `<SKIP_VALIDATION>` is `true`

Constraints:
- Make no unrelated edits.
- Do not overwrite non-empty directories.
- Stop on missing prerequisites instead of guessing.
- Keep changes scoped to `<DESTINATION_DIR>/<PACKAGE_NAME>`.

Verification:
- Confirm `Package.swift`, `AGENTS.md`, `Tests/`, and `.git` exist.
- If validation is enabled, verify `swift build` and `swift test` success.

Return contract:
- `status: success|blocked|failed`
- `path_type: <primary|fallback>`
- `path: <resolved path>`
- `options: <normalized type/platform/version profile>`
- `checks: <passed checks or skipped>`
- `notes: <brief follow-up>`
```

## Customization Knobs

- `<PACKAGE_NAME>`: Swift package name.
- `<PACKAGE_TYPE>`: `library`, `executable`, or explicit passthrough `tool`.
- `<DESTINATION_DIR>`: Absolute or workspace-relative parent directory.
- `<PLATFORM_PRESET>`: `mac`, `mobile`, or `multiplatform` (aliases accepted by script).
- `<VERSION_PROFILE>`: `latest-major`, `current-minus-one`, or `current-minus-two` (aliases accepted).
- `<SKIP_VALIDATION>`: `true` or `false`.

## Guardrails and Stop Conditions

- Stop if prerequisites are missing.
- Stop if target exists and is non-empty.
- Stop if script invocation fails at any step.
- Never continue after failed validation unless `<SKIP_VALIDATION>` is explicitly `true`.
