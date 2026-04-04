#!/usr/bin/env python3
"""Match a query against Dash built-in, contributed, and cheatsheet catalogs."""

from __future__ import annotations

import argparse
import json
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any


def _references_dir() -> Path:
    return Path(__file__).resolve().parents[1] / "references"


def _load_entries(filename: str) -> list[dict[str, Any]]:
    path = _references_dir() / filename
    if not path.exists():
        return []
    data = json.loads(path.read_text(encoding="utf-8"))
    entries = data.get("entries", [])
    return entries if isinstance(entries, list) else []


def _score(query: str, name: str, slug: str) -> float:
    q = query.lower().strip()
    n = name.lower()
    s = slug.lower()
    if not q:
        return 0.0
    if q == n or q == s:
        return 1.0

    score = 0.0
    if q in n:
        score += 0.65
    if q in s:
        score += 0.5

    q_tokens = [token for token in q.split() if token]
    if q_tokens:
        overlap = sum(1 for token in q_tokens if token in n or token in s)
        score += 0.2 * (overlap / len(q_tokens))

    ratio = max(SequenceMatcher(None, q, n).ratio(), SequenceMatcher(None, q, s).ratio())
    score += 0.35 * ratio
    return min(score, 1.0)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", required=True, help="Docset or cheatsheet query text")
    parser.add_argument("--limit", type=int, default=20, help="Max matches to return")
    args = parser.parse_args()

    entries: list[dict[str, Any]] = []
    for source, filename in (
        ("built_in", "catalog_built_in_docsets.json"),
        ("user_contributed", "catalog_user_contrib_docsets.json"),
        ("cheatsheet", "catalog_cheatsheets.json"),
    ):
        for item in _load_entries(filename):
            entry = dict(item)
            entry["source"] = source
            entries.append(entry)

    ranked = []
    for item in entries:
        name = str(item.get("name", ""))
        slug = str(item.get("slug", ""))
        sc = _score(args.query, name, slug)
        if sc < 0.2:
            continue
        ranked.append(
            {
                "name": name,
                "slug": slug,
                "source": item.get("source"),
                "score": round(sc, 4),
                "hint": (
                    "install from Dash Downloads"
                    if item.get("source") == "built_in"
                    else "install from User Contributed"
                    if item.get("source") == "user_contributed"
                    else "install from Cheat Sheets"
                ),
            }
        )

    ranked.sort(key=lambda row: row["score"], reverse=True)
    result = {
        "query": args.query,
        "count": len(ranked[: args.limit]),
        "matches": ranked[: args.limit],
    }
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
