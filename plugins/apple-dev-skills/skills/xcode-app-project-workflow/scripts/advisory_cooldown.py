#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import os
import sys
from pathlib import Path

DEFAULT_STATE = os.path.expanduser("~/.codex/state/apple_dev_advisory_cooldowns.json")


def now_utc() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


def parse_iso(value: str) -> dt.datetime:
    return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))


def load_state(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def save_state(path: Path, state: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(state, indent=2, sort_keys=True) + "\n")


def should_emit(state: dict, key: str, cooldown_days: int) -> bool:
    last = state.get(key)
    if not last:
        return True
    try:
        last_dt = parse_iso(last)
    except Exception:
        return True
    return (now_utc() - last_dt) >= dt.timedelta(days=cooldown_days)


def main() -> int:
    parser = argparse.ArgumentParser(description="Advisory cooldown helper")
    parser.add_argument("action", choices=["should-emit", "mark-emitted", "show"])
    parser.add_argument("--key", default="mcp-fallback-advisory")
    parser.add_argument("--cooldown-days", type=int, default=21)
    parser.add_argument("--state-file", default=DEFAULT_STATE)
    args = parser.parse_args()

    state_path = Path(args.state_file)
    state = load_state(state_path)

    if args.action == "show":
        print(json.dumps(state, indent=2, sort_keys=True))
        return 0

    if args.action == "should-emit":
        emit = should_emit(state, args.key, args.cooldown_days)
        print("yes" if emit else "no")
        return 0 if emit else 1

    state[args.key] = now_utc().isoformat().replace("+00:00", "Z")
    save_state(state_path, state)
    print(state[args.key])
    return 0


if __name__ == "__main__":
    sys.exit(main())
