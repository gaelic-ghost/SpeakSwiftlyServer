#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# ///
"""Create the current supported XcodeGen-backed app-project scaffold."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--ui-stack", required=True)
    parser.add_argument("--project-generator", required=True)
    parser.add_argument("--bundle-identifier", required=True)
    parser.add_argument("--org-identifier", required=True)
    parser.add_argument("--skip-validation", action="store_true")
    parser.add_argument("--copy-agents", action="store_true")
    return parser


def blocked_payload(path: Path, inputs: dict, next_step: str, *, stderr: str = "", validation_result: str | None = None) -> dict:
    return {
        "status": "blocked",
        "path_type": "primary",
        "resolved_path": str(path),
        "normalized_inputs": inputs,
        "validation_result": validation_result,
        "stderr": stderr,
        "next_step": next_step,
    }


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def render_app_file(name: str) -> str:
    return f"""import SwiftUI

@main
struct {name}: App {{
    var body: some Scene {{
        WindowGroup {{
            ContentView()
        }}
    }}
}}
"""


def render_content_view() -> str:
    return """import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("Hello, world!")
            .padding()
    }
}
"""


def render_test_file(name: str) -> str:
    return f"""import XCTest
@testable import {name}

final class {name}Tests: XCTestCase {{
    func testExample() throws {{
        XCTAssertTrue(true)
    }}
}}
"""


def render_project_yml(name: str, platform: str, bundle_identifier: str) -> str:
    xcodegen_platform = "iOS" if platform in {"ios", "ipados"} else "macOS"
    return f"""name: {name}
options:
  minimumXcodeGenVersion: 2.39.0
targets:
  {name}:
    type: application
    platform: {xcodegen_platform}
    sources:
      - path: Sources/App
        group: App
    info:
      path: Sources/Support/Info.plist
      properties:
        CFBundleDisplayName: {name}
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: {bundle_identifier}
        SWIFT_VERSION: "5.0"
    scheme:
      testTargets:
        - {name}Tests
  {name}Tests:
    type: bundle.unit-test
    platform: {xcodegen_platform}
    sources:
      - path: Tests/{name}Tests
        group: Tests
    dependencies:
      - target: {name}
"""


def main() -> int:
    args = build_parser().parse_args()
    target_dir = (Path(args.destination).expanduser() / args.name).resolve()
    normalized_inputs = {
        "name": args.name,
        "destination": args.destination,
        "platform": args.platform,
        "ui_stack": args.ui_stack,
        "project_generator": args.project_generator,
        "bundle_identifier": args.bundle_identifier,
        "org_identifier": args.org_identifier,
        "skip_validation": args.skip_validation,
        "copy_agents_md": args.copy_agents,
    }

    if args.project_generator != "xcodegen":
        payload = blocked_payload(
            target_dir,
            normalized_inputs,
            "Use the documented XcodeGen path for the current supported mutating implementation.",
            stderr="bootstrap_xcode_app_project.py only supports the xcodegen path.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if args.ui_stack != "swiftui":
        payload = blocked_payload(
            target_dir,
            normalized_inputs,
            "Switch to --ui-stack swiftui for the current supported mutating implementation or use the guided path.",
            stderr="The first supported mutating implementation only scaffolds SwiftUI app projects.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    if target_dir.exists() and any(target_dir.iterdir()):
        payload = blocked_payload(
            target_dir,
            normalized_inputs,
            "Choose an empty destination directory and rerun the workflow.",
            stderr="The target directory already exists and is not empty.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    xcodegen = os.environ.get("XCODEGEN_BIN") or shutil.which("xcodegen")
    if not xcodegen or not Path(xcodegen).exists():
        payload = blocked_payload(
            target_dir,
            normalized_inputs,
            "Install XcodeGen or choose the guided Xcode path and rerun the workflow.",
            stderr="xcodegen is required for the current supported mutating path.",
        )
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    target_dir.mkdir(parents=True, exist_ok=True)

    write_text(target_dir / "project.yml", render_project_yml(args.name, args.platform, args.bundle_identifier))
    write_text(target_dir / "Sources/App/App.swift", render_app_file(args.name))
    write_text(target_dir / "Sources/App/ContentView.swift", render_content_view())
    write_text(target_dir / f"Tests/{args.name}Tests/{args.name}Tests.swift", render_test_file(args.name))

    agents_copied = False
    if args.copy_agents:
        agents_template = Path(__file__).resolve().parents[1] / "assets" / "AGENTS.md"
        if agents_template.exists():
            shutil.copyfile(agents_template, target_dir / "AGENTS.md")
            agents_copied = True

    installer = Path(__file__).with_name("install_repo_maintenance_toolkit.py")
    proc_install_toolkit = subprocess.run(
        [
            str(installer),
            "--repo-root",
            str(target_dir),
            "--operation",
            "install",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if proc_install_toolkit.returncode != 0:
        payload = {
            "status": "failed",
            "path_type": "primary",
            "resolved_path": str(target_dir),
            "normalized_inputs": normalized_inputs,
            "validation_result": "failed (repo-maintenance toolkit install)",
            "stdout": proc_install_toolkit.stdout,
            "stderr": proc_install_toolkit.stderr,
            "next_step": "Fix the repo-maintenance toolkit install failure and rerun the workflow.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    proc_generate = subprocess.run(
        [xcodegen, "generate", "--spec", "project.yml"],
        cwd=target_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    if proc_generate.returncode != 0:
        payload = {
            "status": "failed",
            "path_type": "primary",
            "resolved_path": str(target_dir),
            "normalized_inputs": normalized_inputs,
            "validation_result": "failed (xcodegen generate)",
            "stdout": proc_generate.stdout,
            "stderr": proc_generate.stderr,
            "next_step": "Fix the XcodeGen generation failure and rerun the workflow.",
        }
        print(json.dumps(payload, indent=2, sort_keys=True))
        return 1

    validation_result = "skipped (--skip-validation)"
    validation_stdout = ""
    validation_stderr = ""
    if not args.skip_validation:
        xcodebuild = os.environ.get("XCODEBUILD_BIN") or shutil.which("xcodebuild")
        if xcodebuild and Path(xcodebuild).exists():
            proc_validate = subprocess.run(
                [xcodebuild, "-list", "-project", f"{args.name}.xcodeproj"],
                cwd=target_dir,
                capture_output=True,
                text=True,
                check=False,
            )
            validation_stdout = proc_validate.stdout
            validation_stderr = proc_validate.stderr
            if proc_validate.returncode != 0:
                payload = {
                    "status": "failed",
                    "path_type": "primary",
                    "resolved_path": str(target_dir),
                    "normalized_inputs": normalized_inputs,
                    "validation_result": "failed (xcodebuild -list)",
                    "stdout": validation_stdout,
                    "stderr": validation_stderr,
                    "next_step": "Fix the generated project introspection failure and rerun the workflow.",
                }
                print(json.dumps(payload, indent=2, sort_keys=True))
                return 1
            validation_result = "passed (xcodebuild -list)"
        else:
            validation_result = "skipped (xcodebuild unavailable)"

    payload = {
        "status": "success",
        "path_type": "primary",
        "resolved_path": str(target_dir),
        "normalized_inputs": normalized_inputs,
        "validation_result": validation_result,
        "generator": "xcodegen",
        "project_file": str(target_dir / f"{args.name}.xcodeproj"),
        "agents_copied": agents_copied,
        "stdout": proc_install_toolkit.stdout + proc_generate.stdout + validation_stdout,
        "stderr": proc_install_toolkit.stderr + proc_generate.stderr + validation_stderr,
        "next_step": "Use xcode-app-project-workflow for normal work inside the generated project.",
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
