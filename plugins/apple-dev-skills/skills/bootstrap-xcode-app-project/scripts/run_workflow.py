#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# dependencies = [
#   "PyYAML>=6.0.2,<7",
# ]
# ///
"""Unified runtime entrypoint for bootstrap-xcode-app-project."""

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


def normalize_platform(raw: str) -> tuple[str | None, str | None]:
    value = raw.strip().lower()
    if value in {"mac", "macos", "osx"}:
        return "macos", None
    if value in {"ios", "iphone"}:
        return "ios", None
    if value in {"ipados", "ipad"}:
        return "ipados", None
    if value in {"", "ask"}:
        return None, "Choose a supported platform: macos, ios, or ipados."
    return None, "Choose a supported platform: macos, ios, or ipados."


def normalize_ui_stack(raw: str) -> tuple[str | None, str | None]:
    value = raw.strip().lower()
    aliases = {
        "swiftui": "swiftui",
        "uikit": "uikit",
        "appkit": "appkit",
        "ask": None,
        "": None,
    }
    normalized = aliases.get(value)
    if normalized is None:
        if value in {"ask", ""}:
            return None, "Choose a supported UI stack: swiftui, uikit, or appkit."
        return None, "Choose a supported UI stack: swiftui, uikit, or appkit."
    return normalized, None


def normalize_generator(raw: str) -> tuple[str | None, str | None]:
    value = raw.strip().lower()
    if value in {"xcode", "xcodegen", "ask"}:
        return value, None
    if value == "":
        return "ask", None
    return None, "Choose a supported project generator: ask, xcode, or xcodegen."


def derive_bundle_identifier(name: str, explicit: str | None, org_identifier: str) -> str:
    if explicit:
        return explicit
    cleaned = "".join(ch for ch in name if ch.isalnum())
    if not cleaned:
        cleaned = "App"
    return f"{org_identifier}.{cleaned}"


def blocked_payload(normalized_inputs: dict, next_step: str, *, stderr: str = "", validation_result: str | None = None) -> dict:
    return {
        "status": "blocked",
        "path_type": "primary",
        "resolved_path": None,
        "normalized_inputs": normalized_inputs,
        "validation_result": validation_result,
        "stderr": stderr,
        "next_step": next_step,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name")
    parser.add_argument("--destination")
    parser.add_argument("--project-kind")
    parser.add_argument("--platform")
    parser.add_argument("--ui-stack")
    parser.add_argument("--project-generator")
    parser.add_argument("--bundle-identifier")
    parser.add_argument("--org-identifier")
    parser.add_argument("--skip-validation", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main() -> int:
    args = build_parser().parse_args()
    config = load_effective_config()
    settings = config["settings"]

    name = args.name
    destination = args.destination or "."
    project_kind = args.project_kind or str(settings.get("defaultProjectKind", "app"))
    platform_raw = args.platform or str(settings.get("defaultPlatform", "ask"))
    ui_stack_raw = args.ui_stack or str(settings.get("defaultUIStack", "swiftui"))
    generator_raw = args.project_generator or str(settings.get("defaultProjectGenerator", "ask"))
    org_identifier = args.org_identifier or str(settings.get("defaultOrgIdentifier", "com.example"))
    copy_agents = bool(settings.get("copyAgentsMd", True))
    validation_mode = str(settings.get("validationMode", "full"))

    platform, platform_error = normalize_platform(platform_raw)
    ui_stack, ui_error = normalize_ui_stack(ui_stack_raw)
    generator, generator_error = normalize_generator(generator_raw)

    normalized_inputs = {
        "name": name,
        "destination": destination,
        "project_kind": project_kind,
        "platform": platform_raw if platform is None else platform,
        "ui_stack": ui_stack_raw if ui_stack is None else ui_stack,
        "project_generator": generator,
        "bundle_identifier": args.bundle_identifier,
        "org_identifier": org_identifier,
        "skip_validation": args.skip_validation,
        "copy_agents_md": copy_agents,
        "validation_mode": validation_mode,
    }

    if not name:
        print(json.dumps(blocked_payload(normalized_inputs, "Provide --name to create a new Xcode app project."), indent=2, sort_keys=True))
        return 1

    if project_kind != "app":
        payload = blocked_payload(
            normalized_inputs,
            "Use bootstrap-swift-package for package bootstrap or rerun with --project-kind app.",
            stderr="bootstrap-xcode-app-project only supports native Apple app bootstrap.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if platform_error:
        print(json.dumps(blocked_payload(normalized_inputs, platform_error), indent=2, sort_keys=True))
        return 1

    if ui_error:
        print(json.dumps(blocked_payload(normalized_inputs, ui_error), indent=2, sort_keys=True))
        return 1

    if generator_error:
        print(json.dumps(blocked_payload(normalized_inputs, generator_error), indent=2, sort_keys=True))
        return 1

    assert platform is not None
    assert ui_stack is not None
    assert generator is not None

    resolved_path = str((Path(destination).expanduser() / name).resolve())
    bundle_identifier = derive_bundle_identifier(name, args.bundle_identifier, org_identifier)
    platform_family = "ios" if platform in {"ios", "ipados"} else "macos"

    normalized_inputs["bundle_identifier"] = bundle_identifier
    normalized_inputs["platform_family"] = platform_family

    if generator == "ask":
        payload = blocked_payload(
            normalized_inputs,
            "Choose --project-generator xcode or --project-generator xcodegen and rerun the workflow.",
            stderr="The generator preference is required when defaults are set to ask.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if args.dry_run:
        payload = {
            "status": "success",
            "path_type": "primary",
            "resolved_path": resolved_path,
            "normalized_inputs": normalized_inputs,
            "validation_result": "skipped (--dry-run)",
            "bundle_identifier": bundle_identifier,
            "next_step": (
                "Run without --dry-run to create the project through the supported XcodeGen path."
                if generator == "xcodegen"
                else "Use the documented guided Xcode path or switch to --project-generator xcodegen for the supported mutating path."
            ),
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 0

    if generator == "xcode":
        payload = blocked_payload(
            normalized_inputs,
            "Create the project in Xcode using Apple's standard app-project flow, then use xcode-app-project-workflow for existing-project work.",
            stderr="The first implementation pass does not automate the standard Xcode GUI creation path yet.",
            validation_result="guided xcode path only",
        )
        payload["resolved_path"] = resolved_path
        payload["bundle_identifier"] = bundle_identifier
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    helper_path = Path(__file__).with_name("bootstrap_xcode_app_project.py")
    command = [
        str(helper_path),
        "--name",
        name,
        "--destination",
        destination,
        "--platform",
        platform,
        "--ui-stack",
        ui_stack,
        "--project-generator",
        generator,
        "--bundle-identifier",
        bundle_identifier,
        "--org-identifier",
        org_identifier,
    ]
    if copy_agents:
        command.append("--copy-agents")
    if args.skip_validation:
        command.append("--skip-validation")

    proc = subprocess.run(command, capture_output=True, text=True, check=False)
    payload = json.loads(proc.stdout) if proc.stdout.strip() else {
        "status": "failed",
        "path_type": "primary",
        "resolved_path": resolved_path,
        "normalized_inputs": normalized_inputs,
        "bundle_identifier": bundle_identifier,
        "validation_result": None,
        "stdout": proc.stdout,
        "stderr": proc.stderr,
        "next_step": "Fix the bootstrap error and rerun the workflow.",
    }
    payload.setdefault("normalized_inputs", normalized_inputs)
    payload.setdefault("bundle_identifier", bundle_identifier)
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0 if proc.returncode == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
