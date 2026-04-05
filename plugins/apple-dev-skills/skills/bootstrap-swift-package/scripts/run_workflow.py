#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Unified runtime entrypoint for bootstrap-swift-package."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import customization_config


def load_effective_config() -> dict:
    return customization_config.merge_configs(
        customization_config.load_template(),
        customization_config.load_durable(),
    )


def parse_output(stdout: str) -> dict:
    result = {
        "resolved_path": None,
        "validation_result": None,
        "git_initialized": None,
        "agents_copied": None,
        "testing_mode": None,
        "testing_strategy": None,
        "swift_toolchain": None,
    }
    for line in stdout.splitlines():
        if line.startswith("Created Swift package: "):
            result["resolved_path"] = line.split(": ", 1)[1].strip()
        elif line.startswith("Validation: "):
            result["validation_result"] = line.split(": ", 1)[1].strip()
        elif line.startswith("Git: "):
            result["git_initialized"] = line.endswith("initialized")
        elif line.startswith("AGENTS: "):
            result["agents_copied"] = line.endswith("copied")
        elif line.startswith("Swift toolchain: "):
            result["swift_toolchain"] = line.split(": ", 1)[1].strip()
        elif line.startswith("Testing mode: "):
            result["testing_mode"] = line.split(": ", 1)[1].strip()
        elif line.startswith("Testing strategy: "):
            result["testing_strategy"] = line.split(": ", 1)[1].strip()
    return result


def blocked_payload(normalized_inputs: dict, next_step: str, *, validation_result: str | None = None, stderr: str = "") -> dict:
    return {
        "status": "blocked",
        "path_type": "primary",
        "resolved_path": None,
        "normalized_inputs": normalized_inputs,
        "validation_result": validation_result,
        "stderr": stderr,
        "next_step": next_step,
    }


def probe_testing_mode(script_path: Path, testing_mode: str) -> tuple[bool, str, str | None]:
    proc = subprocess.run(
        [str(script_path), "--name", "ProbePackage", "--probe-testing-mode", testing_mode],
        capture_output=True,
        text=True,
        check=False,
    )
    parsed = parse_output(proc.stdout)
    return proc.returncode == 0, proc.stderr.strip(), parsed["testing_strategy"]


def probe_bootstrap_inputs(command: list[str]) -> tuple[int, str]:
    probe_command = [command[0], *command[1:], "--probe-bootstrap-inputs"]
    proc = subprocess.run(
        probe_command,
        capture_output=True,
        text=True,
        check=False,
    )
    return proc.returncode, proc.stderr.strip()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name")
    parser.add_argument("--type")
    parser.add_argument("--destination")
    parser.add_argument("--platform")
    parser.add_argument("--version-profile")
    parser.add_argument("--testing-mode")
    parser.add_argument("--skip-validation", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_effective_config()
    settings = config["settings"]

    name = args.name
    pkg_type = args.type or "library"
    destination = args.destination or "."
    platform = args.platform or "multiplatform"
    version_profile = args.version_profile or str(settings.get("defaultVersionProfile", "current-minus-one"))
    testing_mode = args.testing_mode or str(settings.get("defaultTestingMode", "swift-testing"))
    initialize_git = bool(settings.get("initializeGit", True))
    copy_agents = bool(settings.get("copyAgentsMd", True))

    normalized_inputs = {
        "name": name,
        "type": pkg_type,
        "destination": destination,
        "platform": platform,
        "version_profile": version_profile,
        "testing_mode": testing_mode,
        "skip_validation": args.skip_validation,
        "initialize_git": initialize_git,
        "copy_agents_md": copy_agents,
    }

    if testing_mode not in {"swift-testing", "xctest"}:
        payload = blocked_payload(
            normalized_inputs,
            "Choose a supported testing mode and rerun the workflow.",
            stderr="--testing-mode must be 'swift-testing' or 'xctest'",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if not name:
        payload = {
            "status": "blocked",
            "path_type": "primary",
            "resolved_path": None,
            "normalized_inputs": normalized_inputs,
            "validation_result": None,
            "next_step": "Provide --name to create a new Swift package.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    script_path = Path(__file__).with_name("bootstrap_swift_package.sh")
    if not script_path.exists():
        payload = {
            "status": "success",
            "path_type": "fallback",
            "resolved_path": None,
            "normalized_inputs": normalized_inputs,
            "validation_result": None,
            "next_step": "The bootstrap script is missing. Fall back to manual swift package init guidance.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    probe_ok, probe_stderr, testing_strategy = probe_testing_mode(script_path, testing_mode)
    if not probe_ok:
        payload = blocked_payload(
            normalized_inputs,
            "Resolve the bootstrap prerequisite or toolchain selection issue and rerun the workflow.",
            validation_result="blocked (--testing-mode probe)",
            stderr=probe_stderr,
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    command = [
        str(script_path),
        "--name",
        name,
        "--type",
        pkg_type,
        "--destination",
        destination,
        "--platform",
        platform,
        "--version-profile",
        version_profile,
        "--testing-mode",
        testing_mode,
    ]
    if args.skip_validation:
        command.append("--skip-validation")
    if not initialize_git:
        command.append("--skip-git-init")
    if not copy_agents:
        command.append("--skip-copy-agents")

    if args.dry_run:
        probe_code, probe_stderr = probe_bootstrap_inputs(command)
        if probe_code != 0:
            payload = {
                "status": "blocked" if probe_code == 2 else "failed",
                "path_type": "primary",
                "resolved_path": None,
                "normalized_inputs": normalized_inputs,
                "validation_result": "blocked (--dry-run input probe)" if probe_code == 2 else "failed (--dry-run input probe)",
                "stderr": probe_stderr,
                "next_step": (
                    "Resolve the bootstrap prerequisite or input validation issue and rerun the workflow."
                    if probe_code == 2
                    else "Fix the dry-run validation failure and rerun the workflow."
                ),
            }
            print(json.dumps(payload, indent=2, sort_keys=True))
            return 1
        payload = {
            "status": "success",
            "path_type": "primary",
            "resolved_path": str(Path(destination).expanduser() / name),
            "normalized_inputs": normalized_inputs,
            "validation_result": "skipped (--dry-run)",
            "testing_strategy": testing_strategy,
            "command": command,
            "next_step": "Run the bootstrap workflow without --dry-run to create the package.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    parsed = parse_output(proc.stdout)
    status = "success" if proc.returncode == 0 else ("blocked" if proc.returncode == 2 else "failed")
    next_step = (
        "Use xcode-app-project-workflow for build, test, or xcodebuild-based package work when Xcode-managed tooling is required."
        if status == "success"
        else (
            "Resolve the bootstrap prerequisite or toolchain selection issue and rerun the workflow."
            if status == "blocked"
            else "Fix the bootstrap error and rerun the workflow."
        )
    )
    payload = {
        "status": status,
        "path_type": "primary",
        "resolved_path": parsed["resolved_path"],
        "normalized_inputs": normalized_inputs,
        "validation_result": parsed["validation_result"],
        "git_initialized": parsed["git_initialized"],
        "agents_copied": parsed["agents_copied"],
        "testing_mode": parsed["testing_mode"],
        "testing_strategy": parsed["testing_strategy"],
        "swift_toolchain": parsed["swift_toolchain"],
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "next_step": (
            "Use swift build and swift test by default, and switch to xcode-app-project-workflow when Xcode-managed toolchain behavior is required."
            if status == "success"
            else next_step
        ),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if proc.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
