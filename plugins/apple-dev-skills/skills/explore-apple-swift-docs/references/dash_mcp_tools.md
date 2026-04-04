# Dash MCP Tools

Use this order when working with Dash:

1. Prefer `dash-mcp-server` tools.
2. Fallback to local Dash HTTP API if MCP is unavailable.
3. Fallback to URL scheme / System Service guidance.

## Primary tools

- `list_installed_docsets`
  - Returns installed docsets with fields: `name`, `identifier`, `platform`, `full_text_search`, optional `notice`.
- `search_documentation`
  - Inputs: `query`, `docset_identifiers` (comma-separated), optional `search_snippets`, optional `max_results`.
  - For strict docset search, use `search_snippets=false`.
- `enable_docset_fts`
  - Input: `identifier`.
  - Enables full-text search for that docset (if supported).
- `load_documentation_page`
  - Input: `load_url` returned by `search_documentation`.
  - Converts HTML output to plain text with markdown links.

## FTS statuses

Treat `full_text_search` values as:

- `enabled`: ready for full-text search.
- `disabled`: can be enabled.
- `indexing`: enablement happened; indexing still in progress.
- `not supported`: cannot enable FTS for that docset type.

## Common errors

- Dash not running or API disabled.
- Invalid `docset_identifiers`.
- No docsets installed.
- Trial/purchase restrictions in Dash API responses.
