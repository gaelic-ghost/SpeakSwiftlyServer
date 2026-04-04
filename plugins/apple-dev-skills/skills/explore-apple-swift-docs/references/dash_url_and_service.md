# Dash URL Scheme and macOS Service

Use these integrations when MCP or local HTTP is unavailable, or when the user requests app-level integration.

## AppleScript

Search:

```applescript
open location "dash://?query={query}"
```

Keyword-constrained search:

```applescript
open location "dash://?query=php:{query}"
```

## Terminal

Search:

```bash
open "dash://?query={query}"
```

## Global system service

Dash installs a global macOS service:

- Select text in any app.
- Use `Services > Look Up in Dash`.
- Optional keyboard shortcut can be assigned in macOS keyboard shortcuts.

## URL schemes observed in Dash app metadata

- `dash://`
- `dash-plugin://`
- `dash-feed://`
- `dash-install://`
- `dash-advanced://`
- `dash-advanced-with-keys://`
- `dash-workflow-callback://`
- `dash-silent-open://`
- `dash-activate://`
- `dash-snippet://`

## Install URL notes

Observed install query keys:

- `repo_name`
- `entry_name`
- `version` (optional)

Use `scripts/dash_url_install.py` with confirmation-first behavior.
