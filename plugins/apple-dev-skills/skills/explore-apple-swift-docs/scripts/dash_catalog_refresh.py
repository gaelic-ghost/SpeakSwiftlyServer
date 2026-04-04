#!/usr/bin/env python3
"""Refresh Dash catalog snapshots from Kapeli sources."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.error import URLError
from urllib.request import Request, urlopen


GITHUB_API_FEEDS = "https://api.github.com/repos/Kapeli/feeds/contents?ref=master"
GITHUB_API_CONTRIB = (
    "https://api.github.com/repos/Kapeli/Dash-User-Contributions/contents/docsets?ref=master"
)
GITHUB_API_CHEATS = (
    "https://api.github.com/repos/Kapeli/cheatsheets/contents/cheatsheets?ref=master"
)


USER_AGENT = "dash-skill-catalog-refresh/1.0"


def _fetch_json(url: str) -> Any:
    req = Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urlopen(req, timeout=20) as response:
        return json.loads(response.read().decode("utf-8"))


def _humanize(name: str) -> str:
    return name.replace("_", " ").strip()


def _references_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "references"


def _write_catalog(path: Path, entries: list[dict[str, Any]], source_url: str) -> None:
    payload = {
        "refreshed_at": datetime.now(timezone.utc).isoformat(),
        "source_url": source_url,
        "count": len(entries),
        "entries": entries,
    }
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _refresh(force: bool) -> dict[str, Any]:
    refs = _references_dir()
    refs.mkdir(parents=True, exist_ok=True)

    built_in_path = refs / "catalog_built_in_docsets.json"
    contrib_path = refs / "catalog_user_contrib_docsets.json"
    cheats_path = refs / "catalog_cheatsheets.json"

    status: dict[str, Any] = {
        "built_in": {"updated": False, "count": 0, "error": None},
        "user_contrib": {"updated": False, "count": 0, "error": None},
        "cheatsheets": {"updated": False, "count": 0, "error": None},
    }

    try:
        feed_items = _fetch_json(GITHUB_API_FEEDS)
        built_in_entries: list[dict[str, Any]] = []
        for item in feed_items:
            name = item.get("name", "")
            if item.get("type") != "file" or not name.endswith(".xml"):
                continue
            slug = name[:-4]
            built_in_entries.append(
                {
                    "name": _humanize(slug),
                    "slug": slug,
                    "feed_xml_url": item.get("download_url"),
                    "source": "built_in",
                }
            )
        built_in_entries.sort(key=lambda x: x["name"].lower())
        _write_catalog(built_in_path, built_in_entries, GITHUB_API_FEEDS)
        status["built_in"]["updated"] = True
        status["built_in"]["count"] = len(built_in_entries)
    except (OSError, URLError, json.JSONDecodeError) as exc:
        status["built_in"]["error"] = str(exc)
        if force and not built_in_path.exists():
            raise

    try:
        contrib_items = _fetch_json(GITHUB_API_CONTRIB)
        contrib_entries: list[dict[str, Any]] = []
        for item in contrib_items:
            if item.get("type") != "dir":
                continue
            slug = item.get("name", "").strip()
            if not slug:
                continue
            contrib_entries.append(
                {
                    "name": _humanize(slug),
                    "slug": slug,
                    "repo_path": item.get("path"),
                    "html_url": item.get("html_url"),
                    "source": "user_contributed",
                }
            )
        contrib_entries.sort(key=lambda x: x["name"].lower())
        _write_catalog(contrib_path, contrib_entries, GITHUB_API_CONTRIB)
        status["user_contrib"]["updated"] = True
        status["user_contrib"]["count"] = len(contrib_entries)
    except (OSError, URLError, json.JSONDecodeError) as exc:
        status["user_contrib"]["error"] = str(exc)
        if force and not contrib_path.exists():
            raise

    try:
        cheat_items = _fetch_json(GITHUB_API_CHEATS)
        cheat_entries: list[dict[str, Any]] = []
        for item in cheat_items:
            name = item.get("name", "")
            if item.get("type") != "file" or not name.endswith(".rb"):
                continue
            slug = name[:-3]
            cheat_entries.append(
                {
                    "name": _humanize(slug),
                    "slug": slug,
                    "definition_url": item.get("html_url"),
                    "source": "cheatsheet",
                }
            )
        cheat_entries.sort(key=lambda x: x["name"].lower())
        _write_catalog(cheats_path, cheat_entries, GITHUB_API_CHEATS)
        status["cheatsheets"]["updated"] = True
        status["cheatsheets"]["count"] = len(cheat_entries)
    except (OSError, URLError, json.JSONDecodeError) as exc:
        status["cheatsheets"]["error"] = str(exc)
        if force and not cheats_path.exists():
            raise

    return status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--force",
        action="store_true",
        help="Fail if refresh cannot produce missing catalogs.",
    )
    args = parser.parse_args()

    status = _refresh(force=args.force)
    print(json.dumps(status, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
