#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Unified runtime entrypoint for explore-apple-swift-docs."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import customization_config


VALID_MODES = {"explore", "dash-install", "dash-generate"}
DASH_INSTALL_REPO_NAME = {
    "built_in": "Main Docsets",
    "user_contributed": "User Contributed Docsets",
    "cheatsheet": "Cheat Sheets",
}
VALID_SOURCES = {"xcode-mcp-docs", "dash", "official-web"}


def load_effective_config() -> dict:
    return customization_config.merge_configs(
        customization_config.load_template(),
        customization_config.load_durable(),
    )


def split_csv(raw: str) -> list[str]:
    return [item.strip() for item in raw.split(",") if item.strip()]


def normalize_source_order(raw: str) -> list[str]:
    normalized = [item for item in split_csv(raw) if item in VALID_SOURCES]
    return normalized or ["xcode-mcp-docs", "dash", "official-web"]


def run_json_script(script_name: str, args: list[str]) -> dict:
    script_path = Path(__file__).with_name(script_name)
    proc = subprocess.run(
        [sys.executable, str(script_path), *args],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        payload = {}
    payload["_returncode"] = proc.returncode
    payload["_stderr"] = proc.stderr
    return payload


def load_matches(query: str, limit: int) -> list[dict]:
    payload = run_json_script("dash_catalog_match.py", ["--query", query, "--limit", str(limit)])
    return payload.get("matches", []) if isinstance(payload.get("matches"), list) else []


def shape_matches(matches: list[dict], include_snippets: bool) -> list[dict]:
    if include_snippets:
        return matches
    trimmed: list[dict] = []
    for match in matches:
        trimmed.append(
            {
                "name": match.get("name"),
                "slug": match.get("slug"),
                "source": match.get("source"),
            }
        )
    return trimmed


def probe_dash(status_file: str | None) -> dict:
    probe_args: list[str] = []
    if status_file:
        probe_args.extend(["--status-file", status_file])
    return run_json_script("dash_api_probe.py", probe_args)


def dash_available(probe: dict) -> bool:
    return bool(probe.get("health_ok")) and bool(probe.get("schema_ok"))


def select_source(
    order: list[str],
    preferred_source: str,
    mcp_failure_reason: str | None,
    dash_probe: dict,
) -> tuple[str | None, list[str]]:
    if preferred_source != "auto":
        preferred = preferred_source
        if preferred == "xcode-mcp-docs":
            if not mcp_failure_reason:
                return preferred, order
        elif preferred == "dash":
            if dash_available(dash_probe):
                return preferred, order
        elif preferred == "official-web":
            return preferred, order

    for source in order:
        if source == "xcode-mcp-docs":
            if not mcp_failure_reason:
                return source, order
            continue
        if source == "dash":
            if dash_available(dash_probe):
                return source, order
            continue
        if source == "official-web":
            return source, order
    return None, order


def choose_match(matches: list[dict], source_priority: list[str]) -> dict | None:
    for source in source_priority:
        for match in matches:
            if match.get("source") == source:
                return match
    return matches[0] if matches else None


def explore_mode(args: argparse.Namespace, settings: dict) -> tuple[int, dict]:
    if not args.query:
        return 1, {
            "status": "blocked",
            "path_type": "primary",
            "mode": "explore",
            "source_used": None,
            "configured_order": [],
            "matches": [],
            "next_step": "Provide --query for docs exploration.",
        }

    order = normalize_source_order(str(settings.get("defaultSourceOrder", "xcode-mcp-docs,dash,official-web")))
    preferred_source = args.preferred_source or "auto"
    include_snippets = True
    raw_matches = load_matches(args.query, 20)
    matches = shape_matches(raw_matches, include_snippets)
    dash_probe = probe_dash(args.status_file)
    selected_source, configured_order = select_source(order, preferred_source, args.mcp_failure_reason, dash_probe)

    if not selected_source:
        troubleshooting_preference = "xcode-mcp-first"
        if troubleshooting_preference == "dash-first":
            next_step = "No usable Apple or Swift docs source is available. Recover Dash access first, then fall back to official web docs."
        else:
            next_step = "No usable Apple or Swift docs source is available. Recover Xcode MCP docs first, then fall back through Dash and official web docs."
        return 1, {
            "status": "blocked",
            "path_type": "fallback",
            "mode": "explore",
            "source_used": None,
            "configured_order": configured_order,
            "matches": matches,
            "dash_probe": dash_probe,
            "search_snippets_enabled": include_snippets,
            "troubleshooting_preference": troubleshooting_preference,
            "next_step": next_step,
        }

    path_type = "primary" if selected_source == configured_order[0] and preferred_source in {"", "auto"} else "fallback"
    if preferred_source not in {"", "auto"} and selected_source == preferred_source:
        path_type = "primary"

    if selected_source == "xcode-mcp-docs":
        next_step = "Use Xcode MCP docs tools first for the Apple or Swift lookup."
    elif selected_source == "dash":
        next_step = (
            "Use Dash for the Apple or Swift lookup. If the needed docset is missing, rerun with --mode dash-install."
        )
    else:
        next_step = "Use official Apple or Swift web docs for the lookup."

    return 0, {
        "status": "success",
        "path_type": path_type,
        "mode": "explore",
        "source_used": selected_source,
        "configured_order": configured_order,
        "preferred_source": preferred_source,
        "docs_kind": args.docs_kind or "search",
        "matches": matches,
        "dash_probe": dash_probe,
        "search_snippets_enabled": include_snippets,
        "next_step": next_step,
    }


def dash_install_mode(args: argparse.Namespace, settings: dict) -> tuple[int, dict]:
    if not args.docset_request:
        return 1, {
            "status": "blocked",
            "path_type": "primary",
            "mode": "dash-install",
            "source_used": "dash",
            "source_path": None,
            "matches": [],
            "next_step": "Provide --docset-request for the Dash install follow-up.",
        }

    matches = load_matches(args.docset_request, 20)
    source_priority = split_csv("built-in,user-contributed,cheatsheet")
    normalized_priority = [item.replace("-", "_") for item in source_priority]
    selected = choose_match(matches, normalized_priority)
    if not selected:
        return 0, {
            "status": "handoff",
            "path_type": "primary",
            "mode": "dash-install",
            "source_used": "dash",
            "source_path": None,
            "matches": matches,
            "next_step": "No installable Dash catalog match was found. Hand off to dash-generate.",
        }

    approval_required = True
    approved = bool(args.yes) or not approval_required or args.dry_run
    source = str(selected.get("source", "built_in"))
    repo_name = DASH_INSTALL_REPO_NAME.get(source, "Main Docsets")
    install_result = run_json_script(
        "dash_url_install.py",
        [
            "--repo-name",
            repo_name,
            "--entry-name",
            str(selected.get("name", args.docset_request)),
            *(["--yes"] if approved and not args.dry_run else []),
            *(["--dry-run"] if args.dry_run else []),
        ],
    )

    if approval_required and not args.dry_run and not args.yes:
        return 1, {
            "status": "blocked",
            "path_type": "primary",
            "mode": "dash-install",
            "source_used": "dash",
            "source_path": source,
            "matches": matches,
            "selected_match": selected,
            "next_step": "Rerun with --yes to allow Dash install side effects.",
        }

    return 0, {
        "status": "success",
        "path_type": "primary",
        "mode": "dash-install",
        "source_used": "dash",
        "source_path": source,
        "matches": matches,
        "selected_match": selected,
        "install_result": install_result,
        "next_step": "Return to explore mode after installation if you still need docs lookup results.",
    }


def dash_generate_mode(args: argparse.Namespace, settings: dict) -> tuple[int, dict]:
    if not args.docset_request:
        return 1, {
            "status": "blocked",
            "path_type": "primary",
            "mode": "dash-generate",
            "source_used": "dash",
            "source_path": None,
            "matches": [],
            "next_step": "Provide --docset-request for the Dash generation follow-up.",
        }

    matches = load_matches(args.docset_request, 20)
    generation_policy = "automate-stable"
    guidance = {
        "policy": generation_policy,
        "automation_first": generation_policy == "automate-stable",
        "steps": [
            "Confirm the missing Apple or Swift docs surface is not already available through Xcode MCP docs or official web docs.",
            "Check whether an existing Dash-compatible docset source already exists before generating anything new.",
            "Prefer stable automated generation only when the docs source is durable and repeatable.",
            "Fall back to deterministic manual docset guidance when stable automation is unavailable.",
        ],
    }
    return 0, {
        "status": "success",
        "path_type": "primary" if generation_policy == "automate-stable" else "fallback",
        "mode": "dash-generate",
        "source_used": "dash",
        "source_path": "automation-guidance",
        "matches": matches,
        "guidance": guidance,
        "next_step": "Use this guidance only if the user explicitly wants Dash coverage for the missing docs source.",
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", default="explore", choices=sorted(VALID_MODES))
    parser.add_argument("--query")
    parser.add_argument("--docs-kind")
    parser.add_argument("--preferred-source", choices=["auto", "xcode-mcp-docs", "dash", "official-web"], default="auto")
    parser.add_argument("--docset-request")
    parser.add_argument("--mcp-failure-reason")
    parser.add_argument("--status-file")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--yes", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_effective_config()
    settings = config["settings"]

    if args.mode == "explore":
        code, payload = explore_mode(args, settings)
    elif args.mode == "dash-install":
        code, payload = dash_install_mode(args, settings)
    else:
        code, payload = dash_generate_mode(args, settings)

    payload["dry_run"] = args.dry_run
    print(json.dumps(payload, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
