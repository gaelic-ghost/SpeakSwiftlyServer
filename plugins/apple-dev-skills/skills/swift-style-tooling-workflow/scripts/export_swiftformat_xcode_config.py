#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# ///
"""Export SwiftFormat for Xcode shared defaults to a SwiftFormat config file."""

from __future__ import annotations

import argparse
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


DEFAULT_SUITE_DOMAIN = "com.charcoaldesign.SwiftFormat"
MEANINGLESS_VERSION_VALUES = {"", "0", "auto", "undefined"}
VERSION_OPTION_KEYS = {"swiftversion", "swift-version", "languagemode", "language-mode"}
SAFE_LITERAL_RE = re.compile(r"^[A-Za-z0-9_.,:/+-]+$")


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def load_defaults_domain(domain: str) -> dict[str, Any]:
    proc = subprocess.run(
        ["defaults", "export", domain, "-"],
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        stderr = proc.stderr.decode("utf-8", errors="replace").strip()
        fail(
            "Unable to read the SwiftFormat shared defaults domain "
            f"`{domain}` via `defaults export`. {stderr or 'The domain may not exist on this machine.'}"
        )

    try:
        loaded = plistlib.loads(proc.stdout)
    except Exception as exc:  # pragma: no cover - defensive parse guard
        fail(f"Unable to parse plist data returned by `defaults export`: {exc}")

    if not isinstance(loaded, dict):
        fail("The exported SwiftFormat defaults payload was not a dictionary.")
    return loaded


def load_plist(path: Path) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            loaded = plistlib.load(handle)
    except FileNotFoundError:
        fail(f"Missing plist input file: {path}")
    except Exception as exc:
        fail(f"Unable to read plist input file {path}: {exc}")

    if not isinstance(loaded, dict):
        fail(f"Expected plist root to be a dictionary in {path}")
    return loaded


def expect_mapping(payload: dict[str, Any], key: str) -> dict[str, Any]:
    value = payload.get(key, {})
    if value is None:
        return {}
    if not isinstance(value, dict):
        fail(f"Expected `{key}` in the SwiftFormat defaults payload to be a dictionary.")
    return value


def normalize_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return ""
    return str(value)


def encode_argument(value: str) -> str:
    if SAFE_LITERAL_RE.fullmatch(value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def serialize_lines(payload: dict[str, Any]) -> list[str]:
    rules = expect_mapping(payload, "rules")
    options = expect_mapping(payload, "format-options")
    infer_options = bool(payload.get("infer-options", True))

    enabled_rules = sorted(name for name, enabled in rules.items() if bool(enabled))
    rendered_options: list[tuple[str, str]] = []

    if infer_options:
        for key in sorted(options):
            if key not in VERSION_OPTION_KEYS:
                continue
            value = normalize_scalar(options[key]).strip()
            if value.lower() in MEANINGLESS_VERSION_VALUES:
                continue
            rendered_options.append((key, value))
    else:
        for key in sorted(options):
            rendered_options.append((key, normalize_scalar(options[key]).strip()))

    lines = [
        "# Generated from SwiftFormat for Xcode shared defaults.",
        f"# Source suite: {DEFAULT_SUITE_DOMAIN}",
    ]
    if infer_options:
        lines.append("# infer-options is enabled, so only explicit Swift version or language mode values are exported.")
    lines.append("")

    if enabled_rules:
        lines.append(f"--rules {','.join(enabled_rules)}")

    for key, value in rendered_options:
        lines.append(f"--{key} {encode_argument(value)}")

    if not enabled_rules and not rendered_options:
        lines.append("# No explicit rules or exportable options were found in the shared defaults payload.")

    return lines


def write_output(lines: list[str], output: Path | None) -> None:
    text = "\n".join(lines).rstrip() + "\n"
    if output is None:
        sys.stdout.write(text)
        return
    output.write_text(text, encoding="utf-8")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--suite-domain",
        default=DEFAULT_SUITE_DOMAIN,
        help="UserDefaults suite domain to export. Defaults to SwiftFormat's shared suite.",
    )
    parser.add_argument(
        "--input-plist",
        type=Path,
        help="Read a plist file instead of calling `defaults export`. Useful for testing or offline export.",
    )
    parser.add_argument(
        "--output",
        type=Path,
        help="Write the generated config to this path. Defaults to stdout.",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    payload = load_plist(args.input_plist) if args.input_plist else load_defaults_domain(args.suite_domain)
    lines = serialize_lines(payload)
    write_output(lines, args.output)


if __name__ == "__main__":
    main()
