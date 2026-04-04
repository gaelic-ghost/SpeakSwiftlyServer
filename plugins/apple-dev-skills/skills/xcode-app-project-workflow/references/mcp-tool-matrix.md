# MCP Tool Matrix

## Workspace and session

- `XcodeListWindows`
- `XcodeListNavigatorIssues`

## Discovery and read/search

- `XcodeLS`
- `XcodeGlob`
- `XcodeRead`
- `XcodeGrep`

## Diagnostics, build, and tests

- `XcodeRefreshCodeIssuesInFile`
- `GetBuildLog`
- `GetTestList`
- `BuildProject`
- `RunAllTests`
- `RunSomeTests`

## Runtime and previews

- `ExecuteSnippet`
- `RenderPreview`

## Structured mutation

- `XcodeWrite`
- `XcodeUpdate`
- `XcodeMakeDir`
- `XcodeMV`
- `XcodeRM`

## Known constraints

- Runtime and preview operations require files in active scheme targets.
- Tab indices can remain stable after window closure; always resolve by workspace path.
- Deep directory creation may require parent-by-parent creation.
