#!/usr/bin/env python3
"""Probe local Dash API availability and schema."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import urlopen


STATUS_FILE = (
    Path.home()
    / "Library"
    / "Application Support"
    / "Dash"
    / ".dash_api_server"
    / "status.json"
)


def _read_json_url(url: str, timeout: float = 2.0) -> tuple[bool, Any]:
    try:
        with urlopen(url, timeout=timeout) as response:
            return True, json.loads(response.read().decode("utf-8"))
    except (OSError, URLError, json.JSONDecodeError):
        return False, None


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--status-file",
        default=str(STATUS_FILE),
        help="Path to Dash status.json file",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=2.0,
        help="HTTP timeout in seconds for Dash API probes",
    )
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()

    status_file = Path(args.status_file).expanduser()
    result: dict[str, Any] = {
        "status_file_port": None,
        "health_ok": False,
        "schema_ok": False,
        "base_url": None,
        "schema_paths": [],
    }

    try:
        status_data = json.loads(status_file.read_text(encoding="utf-8"))
        if isinstance(status_data, dict) and isinstance(status_data.get("health_ok"), bool):
            result["health_ok"] = status_data["health_ok"]
        if isinstance(status_data, dict) and isinstance(status_data.get("schema_ok"), bool):
            result["schema_ok"] = status_data["schema_ok"]
        if result["health_ok"] and result["schema_ok"]:
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0
        port = status_data.get("port")
        if isinstance(port, int):
            result["status_file_port"] = port
            result["base_url"] = f"http://127.0.0.1:{port}"
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    base_url = result["base_url"]
    ok_health, health = _read_json_url(f"{base_url}/health", timeout=args.timeout)
    if ok_health and isinstance(health, dict) and health.get("status") == "ok":
        result["health_ok"] = True

    ok_schema, schema = _read_json_url(f"{base_url}/schema", timeout=args.timeout)
    if ok_schema and isinstance(schema, dict):
        result["schema_ok"] = True
        paths = schema.get("paths", {})
        if isinstance(paths, dict):
            result["schema_paths"] = sorted(paths.keys())

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
