#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Runtime workflow policy engine for xcode-app-project-workflow."""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

import customization_config


VALID_OPERATION_TYPES = {
    "workspace-inspection",
    "session-inspection",
    "read-search-diagnostics",
    "build",
    "test",
    "run",
    "package-toolchain-management",
    "mutation",
}


def load_effective_config() -> dict:
    return customization_config.merge_configs(
        customization_config.load_template(),
        customization_config.load_durable(),
    )


def detect_managed_scope(workspace_path: str | None) -> dict:
    if not workspace_path:
        return {"managed": False, "path": None, "markers": [], "reason": "workspace-path-missing"}

    script_path = Path(__file__).with_name("detect_xcode_managed_scope.sh")
    proc = subprocess.run(
        [str(script_path), workspace_path],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        payload = json.loads(proc.stdout or "{}")
    except json.JSONDecodeError:
        payload = {
            "managed": False,
            "path": workspace_path,
            "markers": [],
            "reason": "scope-detection-json-error",
        }
    if proc.returncode != 0 and "reason" not in payload:
        payload["reason"] = "scope-detection-failed"
    return payload


def advisory_status(cooldown_days: int, state_file: str | None) -> dict:
    script_path = Path(__file__).with_name("advisory_cooldown.py")
    command = [
        sys.executable,
        str(script_path),
        "should-emit",
        "--cooldown-days",
        str(cooldown_days),
    ]
    if state_file:
        command.extend(["--state-file", state_file])
    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    should_emit = proc.returncode == 0
    return {
        "cooldown_days": cooldown_days,
        "should_emit": should_emit,
        "state_file": state_file,
    }


def discover_workspace_state(workspace_path: str | None) -> dict:
    if not workspace_path:
        return {"workspace": None, "project": None, "swift_package": False}

    root = Path(workspace_path).expanduser()
    if not root.exists():
        return {"workspace": None, "project": None, "swift_package": False}

    workspaces = sorted(str(path) for path in root.rglob("*.xcworkspace"))
    projects = sorted(str(path) for path in root.rglob("*.xcodeproj"))
    swift_package = (root / "Package.swift").exists()
    return {
        "workspace": workspaces[0] if workspaces else None,
        "project": projects[0] if projects else None,
        "swift_package": swift_package,
    }


def shell_join(parts: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in parts)


def build_fallback_commands(operation_type: str, workspace_path: str | None, mapping_profile: str) -> list[str]:
    state = discover_workspace_state(workspace_path)
    commands: list[str] = []

    if mapping_profile != "official-default":
        mapping_profile = "official-default"

    if operation_type in {"workspace-inspection", "session-inspection", "read-search-diagnostics"}:
        if state["workspace"]:
            commands.append(shell_join(["xcodebuild", "-workspace", state["workspace"], "-list"]))
        if state["project"]:
            commands.append(shell_join(["xcodebuild", "-project", state["project"], "-list"]))
        if state["swift_package"]:
            commands.append("swift package describe")
    elif operation_type == "build":
        if state["workspace"]:
            commands.append(shell_join(["xcodebuild", "-workspace", state["workspace"], "-scheme", "<scheme>", "build"]))
        if state["project"]:
            commands.append(shell_join(["xcodebuild", "-project", state["project"], "-scheme", "<scheme>", "build"]))
        if state["swift_package"]:
            commands.append("swift build")
    elif operation_type == "test":
        if state["workspace"]:
            commands.append(
                shell_join(
                    [
                        "xcodebuild",
                        "test",
                        "-workspace",
                        state["workspace"],
                        "-scheme",
                        "<scheme>",
                        "-destination",
                        "<destination>",
                    ]
                )
            )
        if state["project"]:
            commands.append(
                shell_join(
                    [
                        "xcodebuild",
                        "test",
                        "-project",
                        state["project"],
                        "-scheme",
                        "<scheme>",
                        "-destination",
                        "<destination>",
                    ]
                )
            )
        if state["swift_package"]:
            commands.append("swift test")
    elif operation_type == "run":
        if state["swift_package"]:
            commands.append("swift run <target>")
        commands.append("xcrun simctl list")
    elif operation_type == "package-toolchain-management":
        if state["swift_package"]:
            commands.extend(["swift package describe", "swift package resolve", "swift package update"])
        commands.extend(["xcrun --find swift", "xcrun --find xcodebuild"])
    return commands


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--operation-type", required=True, choices=sorted(VALID_OPERATION_TYPES))
    parser.add_argument("--workspace-path")
    parser.add_argument("--tab-identifier")
    parser.add_argument("--mcp-failure-reason")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--filesystem-fallback-opt-in", action="store_true")
    parser.add_argument("--advisory-state-file")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_effective_config()
    settings = config["settings"]

    advisory = advisory_status(int(settings.get("advisoryCooldownDays", 21)), args.advisory_state_file)
    fallback_commands = build_fallback_commands(
        args.operation_type,
        args.workspace_path,
        str(settings.get("fallbackCommandMappingProfile", "official-default")),
    )

    guard_result = {
        "applied": False,
        "managed_scope": False,
        "filesystem_fallback_allowed": True,
        "reason": "not-applicable",
    }
    status = "success"
    path_type = "primary"
    next_step = "Proceed with the agent-side MCP path."

    if args.operation_type == "mutation":
        scope = detect_managed_scope(args.workspace_path)
        guard_result = {
            "applied": True,
            "managed_scope": bool(scope.get("managed")),
            "filesystem_fallback_allowed": True,
            "reason": "mcp-or-explicit-opt-in",
            "markers": scope.get("markers", []),
        }
        if scope.get("managed") and settings.get("requireExplicitMutationOptInForFilesystemFallback", True):
            guard_result["filesystem_fallback_allowed"] = bool(args.filesystem_fallback_opt_in)
            if not args.filesystem_fallback_opt_in:
                status = "blocked"
                next_step = "Use MCP mutation tools or rerun with --filesystem-fallback-opt-in for direct filesystem fallback planning."
        elif not scope.get("managed"):
            guard_result["reason"] = "non-managed-scope"

    if args.mcp_failure_reason and status != "blocked":
        path_type = "fallback"
        next_step = (
            f"Use the first documented fallback command because MCP reported {args.mcp_failure_reason}."
            if fallback_commands
            else "No documented CLI fallback is available for this operation type."
        )

    payload = {
        "status": status,
        "path_type": path_type,
        "operation_type": args.operation_type,
        "workspace_path": args.workspace_path,
        "tab_identifier": args.tab_identifier,
        "mcp_failure_reason": args.mcp_failure_reason,
        "guard_result": guard_result,
        "advisory": advisory,
        "fallback_commands": fallback_commands,
        "retry_count": int(settings.get("mcpRetryCount", 1)),
        "next_step": next_step,
        "execution_model": "agent-mcp-orchestrated",
        "dry_run": args.dry_run,
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if status != "blocked" else 1


if __name__ == "__main__":
    raise SystemExit(main())
