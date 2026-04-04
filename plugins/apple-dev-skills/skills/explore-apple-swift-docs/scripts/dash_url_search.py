#!/usr/bin/env python3
"""Launch a Dash search through the dash:// URL scheme."""

from __future__ import annotations

import argparse
import json
import subprocess
from urllib.parse import quote


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", required=True, help="Search query")
    parser.add_argument("--keyword", help="Optional Dash keyword prefix, e.g. python")
    parser.add_argument("--dry-run", action="store_true", help="Print URL without opening it")
    args = parser.parse_args()

    query_text = f"{args.keyword}:{args.query}" if args.keyword else args.query
    url = f"dash://?query={quote(query_text)}"

    result = {"url": url, "launched": False, "returncode": None}
    if not args.dry_run:
        proc = subprocess.run(["open", url], check=False)
        result["launched"] = proc.returncode == 0
        result["returncode"] = proc.returncode

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
