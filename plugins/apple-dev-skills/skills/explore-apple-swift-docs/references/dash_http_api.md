# Dash Local HTTP API

Dash exposes a localhost API server when integration is enabled.

## Discovery

- Status file: `~/Library/Application Support/Dash/.dash_api_server/status.json`
- The file contains JSON with a `port` key.
- Build `base_url` as `http://127.0.0.1:{port}`.

Use `scripts/dash_api_probe.py` to produce:

```json
{
  "status_file_port": 50364,
  "health_ok": false,
  "schema_ok": false,
  "base_url": "http://127.0.0.1:50364",
  "schema_paths": []
}
```

## Important endpoints

- `GET /schema`
  - OpenAPI schema for the running Dash API.
- `GET /health`
  - Returns server status.
- `GET /docsets/list`
  - Returns installed docsets.
- `GET /search`
  - Query args:
    - `query` (required)
    - `docset_identifiers` (optional in raw API)
    - `search_snippets` (optional)
    - `max_results` (optional)
- `GET /docsets/enable_fts`
  - In practice called with query param `identifier`.

## Caveats

- `status.json` may contain a stale port while the API server is down.
- Always test `/health` before other requests.
- `docset_identifiers` in Dash MCP wrapper is effectively required for targeted searches.
- If API is unavailable, fallback to URL scheme or service guidance.
