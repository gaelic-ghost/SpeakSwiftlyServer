from __future__ import annotations

import subprocess
from pathlib import Path

from speak_swiftly_agent.graph import invoke_agent
from speak_swiftly_agent.skills import guidance_sync_handoff


def init_repo(path: Path) -> None:
    subprocess.run(["git", "init", "-b", "main"], cwd=path, check=True, capture_output=True)
    subprocess.run(
        ["git", "config", "user.email", "tests@example.com"],
        cwd=path,
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Tests"],
        cwd=path,
        check=True,
        capture_output=True,
    )
    (path / "Package.swift").write_text(
        """
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Fixture",
    dependencies: [
        .package(url: "https://github.com/gaelic-ghost/SpeakSwiftly", from: "11.0.0-alpha.1"),
    ],
    targets: []
)
""".strip(),
        encoding="utf-8",
    )
    subprocess.run(["git", "add", "Package.swift"], cwd=path, check=True, capture_output=True)
    subprocess.run(
        ["git", "commit", "-m", "test: seed repo"],
        cwd=path,
        check=True,
        capture_output=True,
    )


def test_overview_reports_clean_repo(tmp_path: Path) -> None:
    init_repo(tmp_path)

    report = invoke_agent({"task": "overview", "repo_root": str(tmp_path)})

    assert report.title == "SpeakSwiftlyAgent Repo Overview"
    assert "Working tree: clean" in report.findings


def test_dependency_plan_stays_read_only(tmp_path: Path) -> None:
    init_repo(tmp_path)

    report = invoke_agent(
        {
            "task": "dependency-plan",
            "repo_root": str(tmp_path),
            "package": "SpeakSwiftly",
            "target_version": "v11.0.0-alpha.2",
        }
    )

    assert report.title == "Dependency Update Plan"
    assert any("xcrun swift build" in command.command for command in report.commands)
    assert "Target dependency: SpeakSwiftly -> v11.0.0-alpha.2" in report.findings


def test_guidance_sync_handoff_names_codex_skill(tmp_path: Path) -> None:
    handoff = guidance_sync_handoff(tmp_path)

    assert handoff.skill_name == "sync-swift-package-guidance"
    assert "Use $sync-swift-package-guidance." in handoff.prompt
    assert any("validate-all.sh" in command.command for command in handoff.commands)
