#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Unified runtime entrypoint for sync-swift-package-guidance."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path

import customization_config


def load_effective_config() -> dict:
    return customization_config.merge_configs(
        customization_config.load_template(),
        customization_config.load_durable(),
    )


def discover_repo_state(repo_root: Path) -> dict:
    workspaces = sorted(str(path) for path in repo_root.rglob("*.xcworkspace"))
    projects = sorted(str(path) for path in repo_root.rglob("*.xcodeproj"))
    return {
        "package_manifest": str(repo_root / "Package.swift") if (repo_root / "Package.swift").exists() else None,
        "workspace": workspaces[0] if workspaces else None,
        "project": projects[0] if projects else None,
        "is_package_repo": (repo_root / "Package.swift").exists(),
        "is_xcode_repo": bool(workspaces or projects),
        "is_ambiguous_repo": (repo_root / "Package.swift").exists() and bool(workspaces or projects),
    }


def blocked_payload(
    repo_root: str,
    detected_state: dict,
    next_step: str,
    *,
    stderr: str = "",
    validation_result: str | None = None,
) -> dict:
    return {
        "status": "blocked",
        "path_type": "primary",
        "repo_root": repo_root,
        "detected_state": detected_state,
        "agents_path": str(Path(repo_root) / "AGENTS.md"),
        "validation_result": validation_result,
        "stderr": stderr,
        "actions": [],
        "next_step": next_step,
    }


def normalize_write_mode(raw: object) -> tuple[str, bool, bool, bool]:
    value = str(raw or "sync-if-needed").strip().lower()
    mapping = {
        "sync-if-needed": (True, True, False),
        "create-missing-only": (True, False, False),
        "append-existing-only": (False, True, False),
        "report-only": (False, False, True),
    }
    copy_missing, append_existing, report_only = mapping.get(value, mapping["sync-if-needed"])
    normalized = value if value in mapping else "sync-if-needed"
    return normalized, copy_missing, append_existing, report_only


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root")
    parser.add_argument("--skip-validation", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_effective_config()
    settings = config["settings"]

    repo_root = Path(args.repo_root or ".").expanduser().resolve()
    detected_state = discover_repo_state(repo_root)
    agents_path = repo_root / "AGENTS.md"
    write_mode, copy_missing, append_existing, report_only = normalize_write_mode(settings.get("writeMode", "sync-if-needed"))
    normalized_inputs = {
        "repo_root": str(repo_root),
        "skip_validation": args.skip_validation,
        "write_mode": write_mode,
        "copy_agents_template_when_missing": copy_missing,
        "append_section_when_agents_exists": append_existing,
        "report_only": report_only,
    }

    if not repo_root.exists():
        print(
            json.dumps(
                blocked_payload(
                    str(repo_root),
                    detected_state,
                    "Resolve the repository root and rerun the workflow.",
                    stderr="The requested repo root does not exist.",
                ),
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    if not repo_root.is_dir():
        print(
            json.dumps(
                blocked_payload(
                    str(repo_root),
                    detected_state,
                    "Use a directory path for --repo-root and rerun the workflow.",
                    stderr="The requested repo root is not a directory.",
                ),
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    if not detected_state["is_package_repo"]:
        print(
            json.dumps(
                blocked_payload(
                    str(repo_root),
                    detected_state,
                    "Use bootstrap-swift-package for new package creation, or rerun this skill on an existing Swift package repo.",
                    stderr="The repository does not contain a Package.swift manifest at the requested root.",
                ),
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    if detected_state["is_ambiguous_repo"]:
        print(
            json.dumps(
                blocked_payload(
                    str(repo_root),
                    detected_state,
                    "Choose the plain Swift package root explicitly, or use sync-xcode-project-guidance for the Xcode app repo instead.",
                    stderr="The requested repo root contains both Package.swift and Xcode app markers, so the guidance boundary is ambiguous.",
                ),
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    actions: list[str] = []
    if not agents_path.exists():
        if normalized_inputs["copy_agents_template_when_missing"]:
            actions.append("create AGENTS.md from assets/AGENTS.md")
        elif normalized_inputs["report_only"]:
            actions.append("report that AGENTS.md is missing and would need template creation")
    elif agents_path.exists():
        text = agents_path.read_text(encoding="utf-8") if agents_path.is_file() else ""
        if "## Swift Package Workflow" in text:
            actions.append("leave existing AGENTS.md unchanged")
        elif normalized_inputs["append_section_when_agents_exists"]:
            actions.append("append the bounded Swift package guidance section to AGENTS.md")
        elif normalized_inputs["report_only"]:
            actions.append("report that AGENTS.md is missing the bounded Swift package guidance section")

    if args.dry_run:
        payload = {
            "status": "success",
            "path_type": "fallback",
            "repo_root": str(repo_root),
            "agents_path": str(agents_path),
            "detected_state": detected_state,
            "normalized_inputs": normalized_inputs,
            "validation_result": "skipped (--dry-run)",
            "actions": actions,
            "next_step": "Run without --dry-run to sync AGENTS.md guidance for this Swift package repo.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    if normalized_inputs["report_only"]:
        payload = {
            "status": "success",
            "path_type": "fallback",
            "repo_root": str(repo_root),
            "agents_path": str(agents_path),
            "detected_state": detected_state,
            "normalized_inputs": normalized_inputs,
            "validation_result": "skipped (writeMode=report-only)",
            "actions": actions,
            "next_step": "Rerun with a mutating write mode if you want this workflow to create or append AGENTS.md guidance.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    helper_path = Path(__file__).with_name("sync_swift_package_guidance.py")
    command = [
        str(helper_path),
        "--repo-root",
        str(repo_root),
    ]
    if normalized_inputs["append_section_when_agents_exists"]:
        command.append("--append-section")
    if normalized_inputs["copy_agents_template_when_missing"]:
        command.append("--copy-agents-template")
    if args.skip_validation:
        command.append("--skip-validation")

    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    payload = json.loads(proc.stdout) if proc.stdout.strip() else {
        "status": "failed",
        "path_type": "primary",
        "repo_root": str(repo_root),
        "agents_path": str(agents_path),
        "detected_state": detected_state,
        "normalized_inputs": normalized_inputs,
        "validation_result": None,
        "actions": actions,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "next_step": "Fix the guidance-sync error and rerun the workflow.",
    }
    payload.setdefault("normalized_inputs", normalized_inputs)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if proc.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
