#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# ///
"""Synchronize baseline repo guidance for an existing Xcode app repository."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


REQUIRED_STRINGS = [
    "xcode-app-project-workflow",
    "sync-xcode-project-guidance",
    "Never edit `.pbxproj` files directly.",
]


def discover_xcode_state(repo_root: Path) -> dict:
    workspaces = sorted(str(path) for path in repo_root.rglob("*.xcworkspace"))
    projects = sorted(str(path) for path in repo_root.rglob("*.xcodeproj"))
    return {
        "workspace": workspaces[0] if workspaces else None,
        "project": projects[0] if projects else None,
        "is_xcode_repo": bool(workspaces or projects),
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--workspace-path")
    parser.add_argument("--append-section", action="store_true")
    parser.add_argument("--copy-agents-template", action="store_true")
    parser.add_argument("--skip-validation", action="store_true")
    return parser


def read_asset(name: str) -> str:
    return (Path(__file__).resolve().parents[1] / "assets" / name).read_text(encoding="utf-8").rstrip() + "\n"


def validate_agents(text: str) -> tuple[bool, list[str]]:
    missing = [needle for needle in REQUIRED_STRINGS if needle not in text]
    return not missing, missing


def main() -> int:
    args = build_parser().parse_args()
    repo_root = Path(args.repo_root).expanduser().resolve()
    agents_path = repo_root / "AGENTS.md"
    detected_state = discover_xcode_state(repo_root)
    actions: list[str] = []

    if not detected_state["is_xcode_repo"]:
        payload = {
            "status": "blocked",
            "path_type": "primary",
            "repo_root": str(repo_root),
            "agents_path": str(agents_path),
            "detected_state": detected_state,
            "validation_result": None,
            "actions": actions,
            "stderr": "The repository does not contain an .xcodeproj or .xcworkspace marker.",
            "next_step": "Run this workflow on an existing Xcode app repo.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if agents_path.exists() and not agents_path.is_file():
        payload = {
            "status": "blocked",
            "path_type": "primary",
            "repo_root": str(repo_root),
            "agents_path": str(agents_path),
            "detected_state": detected_state,
            "validation_result": None,
            "actions": actions,
            "stderr": "The target AGENTS.md path exists but is not a regular file.",
            "next_step": "Resolve the AGENTS.md path conflict and rerun the workflow.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if not agents_path.exists():
        if not args.copy_agents_template:
            payload = {
                "status": "blocked",
                "path_type": "primary",
                "repo_root": str(repo_root),
                "agents_path": str(agents_path),
                "detected_state": detected_state,
                "validation_result": None,
                "actions": actions,
                "stderr": "AGENTS.md is missing and template copy is disabled.",
                "next_step": "Enable template copy or create AGENTS.md manually before rerunning.",
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 1
        agents_path.write_text(read_asset("AGENTS.md"), encoding="utf-8")
        actions.append("created AGENTS.md from template")
    else:
        current = agents_path.read_text(encoding="utf-8")
        if "## Apple / Xcode Project Workflow" in current:
            actions.append("left existing AGENTS.md unchanged")
        elif args.append_section:
            appended = current.rstrip() + "\n\n" + read_asset("append-section.md")
            agents_path.write_text(appended, encoding="utf-8")
            actions.append("appended the bounded Xcode guidance section to AGENTS.md")
        else:
            payload = {
                "status": "blocked",
                "path_type": "primary",
                "repo_root": str(repo_root),
                "agents_path": str(agents_path),
                "detected_state": detected_state,
                "validation_result": None,
                "actions": actions,
                "stderr": "AGENTS.md exists but the bounded Xcode guidance section is missing and append behavior is disabled.",
                "next_step": "Enable append behavior or merge the guidance section manually before rerunning.",
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 1

    validation_result = "skipped (--skip-validation)"
    if not args.skip_validation:
        text = agents_path.read_text(encoding="utf-8")
        is_valid, missing = validate_agents(text)
        if not is_valid:
            payload = {
                "status": "failed",
                "path_type": "primary",
                "repo_root": str(repo_root),
                "agents_path": str(agents_path),
                "detected_state": detected_state,
                "validation_result": "failed",
                "actions": actions,
                "stderr": f"Synced AGENTS.md is missing required guidance: {', '.join(missing)}",
                "next_step": "Fix the guidance template or section content, then rerun the workflow.",
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 1
        validation_result = "validated"

    payload = {
        "status": "success",
        "path_type": "primary",
        "repo_root": str(repo_root),
        "agents_path": str(agents_path),
        "detected_state": detected_state,
        "validation_result": validation_result,
        "actions": actions,
        "next_step": "Use xcode-app-project-workflow for active Xcode collaboration now that repo guidance is aligned.",
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
