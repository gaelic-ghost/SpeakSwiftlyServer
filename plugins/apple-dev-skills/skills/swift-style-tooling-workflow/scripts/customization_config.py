#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Load and persist per-skill customization state."""

from __future__ import annotations

import argparse
import copy
import os
import re
import sys
from pathlib import Path

import yaml

SCHEMA_VERSION = 1
SKILL_NAME = "swift-style-tooling-workflow"
CONFIG_HOME_ENV = "APPLE_DEV_SKILLS_CONFIG_HOME"
DEFAULT_CONFIG_ROOT = "~/.config/gaelic-ghost/apple-dev-skills"
ALLOWED_TOP_LEVEL = {"schemaVersion", "isCustomized", "settings"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def quote_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def encode_scalar(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if value is None:
        return quote_string("")
    return quote_string(str(value))


def parse_yaml(path: Path) -> dict:
    if not path.exists():
        fail(f"Missing YAML file: {path}")

    try:
        loaded = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as exc:
        fail(f"Invalid YAML in {path}: {exc}")

    if loaded is None:
        return {}
    if not isinstance(loaded, dict):
        fail(f"Top-level YAML document must be a mapping in {path}")

    if isinstance(loaded.get("settings"), dict):
        loaded["settings"] = {
            key: ("" if value is None else value) for key, value in loaded["settings"].items()
        }

    return loaded


def validate_config(config: dict, *, allow_partial: bool) -> None:
    unknown = set(config.keys()) - ALLOWED_TOP_LEVEL
    if unknown:
        fail(f"Unknown top-level keys: {', '.join(sorted(unknown))}")

    if not allow_partial:
        for required in ("schemaVersion", "isCustomized", "settings"):
            if required not in config:
                fail(f"Missing required key: {required}")

    if "schemaVersion" in config and config["schemaVersion"] != SCHEMA_VERSION:
        fail(f"schemaVersion must be {SCHEMA_VERSION}")

    if "isCustomized" in config and not isinstance(config["isCustomized"], bool):
        fail("isCustomized must be boolean")

    if "settings" in config:
        if not isinstance(config["settings"], dict):
            fail("settings must be a mapping")
        for key, value in config["settings"].items():
            if not re.fullmatch(r"[A-Za-z0-9_]+", key):
                fail(f"Invalid settings key: {key}")
            if isinstance(value, (dict, list)):
                fail(f"settings values must be scalar: {key}")


def merge_configs(base: dict, overlay: dict) -> dict:
    merged = {
        "schemaVersion": base.get("schemaVersion", SCHEMA_VERSION),
        "isCustomized": base.get("isCustomized", False),
        "settings": copy.deepcopy(base.get("settings", {})),
    }

    if "schemaVersion" in overlay:
        merged["schemaVersion"] = overlay["schemaVersion"]
    if "isCustomized" in overlay:
        merged["isCustomized"] = overlay["isCustomized"]
    if "settings" in overlay:
        merged["settings"].update(overlay["settings"])

    return merged


def dump_yaml(config: dict) -> str:
    lines = [
        f"schemaVersion: {int(config['schemaVersion'])}",
        f"isCustomized: {'true' if config['isCustomized'] else 'false'}",
        "settings:",
    ]
    for key in sorted(config["settings"].keys()):
        lines.append(f"  {key}: {encode_scalar(config['settings'][key])}")
    return "\n".join(lines) + "\n"


def template_path() -> Path:
    return Path(__file__).resolve().parents[1] / "references" / "customization.template.yaml"


def config_root() -> Path:
    root = os.environ.get(CONFIG_HOME_ENV, DEFAULT_CONFIG_ROOT)
    return Path(root).expanduser()


def durable_path() -> Path:
    return config_root() / SKILL_NAME / "customization.yaml"


def load_template() -> dict:
    cfg = parse_yaml(template_path())
    validate_config(cfg, allow_partial=False)
    return cfg


def load_durable() -> dict:
    path = durable_path()
    if not path.exists():
        return {}
    cfg = parse_yaml(path)
    validate_config(cfg, allow_partial=False)
    return cfg


def cmd_path(_: argparse.Namespace) -> None:
    print(durable_path())


def cmd_effective(_: argparse.Namespace) -> None:
    effective = merge_configs(load_template(), load_durable())
    validate_config(effective, allow_partial=False)
    print(dump_yaml(effective), end="")


def cmd_apply(args: argparse.Namespace) -> None:
    template = load_template()
    current = merge_configs(template, load_durable())
    incoming = parse_yaml(Path(args.input))
    validate_config(incoming, allow_partial=True)

    updated = merge_configs(current, incoming)
    updated["schemaVersion"] = SCHEMA_VERSION
    updated["isCustomized"] = True
    validate_config(updated, allow_partial=False)

    target = durable_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(dump_yaml(updated), encoding="utf-8")
    print(target)


def cmd_reset(_: argparse.Namespace) -> None:
    target = durable_path()
    if target.exists():
        target.unlink()
    print(target)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Manage per-skill customization config")
    subparsers = parser.add_subparsers(dest="command", required=True)

    parser_path = subparsers.add_parser("path", help="Print durable config path")
    parser_path.set_defaults(func=cmd_path)

    parser_effective = subparsers.add_parser("effective", help="Print merged effective config")
    parser_effective.set_defaults(func=cmd_effective)

    parser_apply = subparsers.add_parser("apply", help="Apply and persist config overrides")
    parser_apply.add_argument("--input", required=True, help="Path to YAML overrides")
    parser_apply.set_defaults(func=cmd_apply)

    parser_reset = subparsers.add_parser("reset", help="Delete durable config for this skill")
    parser_reset.set_defaults(func=cmd_reset)

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
