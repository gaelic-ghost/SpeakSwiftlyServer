#!/usr/bin/env python3
"""Launch Dash docset install URL after confirmation."""

from __future__ import annotations

import argparse
import json
import subprocess
from urllib.parse import urlencode


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-name", required=True, help="Dash repo name, e.g. Main Docsets")
    parser.add_argument("--entry-name", required=True, help="Entry name, e.g. Rust")
    parser.add_argument("--version", help="Optional version")
    parser.add_argument("--yes", action="store_true", help="Skip interactive confirmation")
    parser.add_argument("--dry-run", action="store_true", help="Print URL without opening it")
    args = parser.parse_args()

    params = {"repo_name": args.repo_name, "entry_name": args.entry_name}
    if args.version:
        params["version"] = args.version
    url = "dash-install://?" + urlencode(params)

    result = {"url": url, "launched": False, "returncode": None, "confirmed": args.yes}
    if args.dry_run:
        print(json.dumps(result, indent=2, sort_keys=True))
        return 0

    if not args.yes:
        answer = input(f"Launch Dash install URL?\n{url}\n[y/N]: ").strip().lower()
        result["confirmed"] = answer in {"y", "yes"}
        if not result["confirmed"]:
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0

    proc = subprocess.run(["open", url], check=False)
    result["launched"] = proc.returncode == 0
    result["returncode"] = proc.returncode
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
