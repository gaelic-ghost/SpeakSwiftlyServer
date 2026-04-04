# Xcode App Bootstrap Automation Contract

## Purpose

Provide one consistent automation contract for deterministic native Apple app bootstrap runs.

## Inputs

- `project_name`
- `destination_dir`
- `project_kind`
- `platform`
- `ui_stack`
- `project_generator`
- `bundle_identifier`
- `org_identifier`
- `skip_validation`

## Constraints

- Run this workflow only for native Apple app bootstrap requests.
- Do not use this workflow for plain Swift packages, libraries, or tools.
- Keep changes scoped to `<DESTINATION_DIR>/<PROJECT_NAME>`.
- Refuse to overwrite a non-empty target directory.
- Treat `project_generator=xcode` as a guided path unless and until a safe automated path exists.

## Status Values

- `success`
- `blocked`
- `failed`

## Output

- `status`
- `path_type`
- `resolved_path`
- normalized project options
- resolved bundle identifier
- validation result
- one concise follow-up note

## Codex App Prompt Template

```text
Use $bootstrap-xcode-app-project.

Run this workflow only when the request is for a new native Apple app project on macOS.

Create a new app project with:
- Name: <PROJECT_NAME>
- Destination directory: <DESTINATION_DIR>
- Project kind: <PROJECT_KIND>
- Platform: <PLATFORM>
- UI stack: <UI_STACK>
- Project generator: <PROJECT_GENERATOR>
- Bundle identifier: <BUNDLE_IDENTIFIER>
- Org identifier: <ORG_IDENTIFIER>
- Skip validation: <SKIP_VALIDATION>

Execution requirements:
1) Stop immediately if this is really a Swift package request instead of an app-project request.
2) Refuse to overwrite a non-empty target directory.
3) Prefer the documented XcodeGen path when <PROJECT_GENERATOR> is `xcodegen`.
4) If <PROJECT_GENERATOR> is `xcode`, return the documented guided next step instead of pretending a safe GUI automation path exists.
5) Keep changes scoped to <DESTINATION_DIR>/<PROJECT_NAME>.

Return the documented contract only:
- `status`
- `path_type`
- `resolved_path`
- normalized scaffold options
- resolved bundle identifier
- validation result
- blocker or next step when needed
```

## Codex CLI Prompt Template

```text
Use $bootstrap-xcode-app-project for a deterministic CLI automation run.

Task:
Bootstrap one native Apple app project with:
- `--name <PROJECT_NAME>`
- `--destination <DESTINATION_DIR>`
- `--project-kind <PROJECT_KIND>`
- `--platform <PLATFORM>`
- `--ui-stack <UI_STACK>`
- `--project-generator <PROJECT_GENERATOR>`
- `--bundle-identifier <BUNDLE_IDENTIFIER>`
- `--org-identifier <ORG_IDENTIFIER>`
- include `--skip-validation` only when `<SKIP_VALIDATION>` is `true`

Constraints:
- Make no unrelated edits.
- Do not overwrite non-empty directories.
- Stop on missing prerequisites instead of guessing.
- Keep changes scoped to `<DESTINATION_DIR>/<PROJECT_NAME>`.

Verification:
- Confirm the expected scaffold files exist.
- If validation is enabled, verify the supported project-generation path completed successfully.

Return contract:
- `status: success|blocked|failed`
- `path_type: <primary|fallback>`
- `resolved_path: <resolved path>`
- `options: <normalized project options>`
- `bundle_identifier: <resolved bundle identifier>`
- `checks: <passed checks or skipped>`
- `notes: <brief follow-up>`
```
