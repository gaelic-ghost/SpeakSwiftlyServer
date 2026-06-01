from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from speak_swiftly_agent.graph import AgentState, invoke_agent

app = typer.Typer(help="Maintainer-side repo agent for SpeakSwiftlyServer.")
console = Console()


RepoRootOption = Annotated[Path | None, typer.Option(help="Repository root to inspect.")]


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def print_report(state: AgentState) -> None:
    report = invoke_agent(state)
    console.print(report.as_markdown())


@app.command()
def overview(
    repo_root: RepoRootOption = None,
) -> None:
    """Summarize repository state without making changes."""

    print_report({"task": "overview", "repo_root": str(repo_root or default_repo_root())})


@app.command()
def dependency_plan(
    package: Annotated[
        str,
        typer.Option(help="SwiftPM dependency identity to update."),
    ] = "SpeakSwiftly",
    target_version: Annotated[
        str,
        typer.Option(help="Target tag, branch, or version note for the plan."),
    ] = "the requested version",
    repo_root: RepoRootOption = None,
) -> None:
    """Plan a dependency update without editing package files."""

    print_report(
        {
            "task": "dependency-plan",
            "repo_root": str(repo_root or default_repo_root()),
            "package": package,
            "target_version": target_version,
        }
    )


@app.command()
def branch_audit(
    base_branch: Annotated[str, typer.Option(help="Branch used to decide merged status.")] = "main",
    repo_root: RepoRootOption = None,
) -> None:
    """Audit merged local branches without deleting anything."""

    print_report(
        {
            "task": "branch-audit",
            "repo_root": str(repo_root or default_repo_root()),
            "base_branch": base_branch,
        }
    )


@app.command()
def guidance_sync(
    kind: Annotated[str, typer.Option(help="Guidance sync family to prepare.")] = "swift-package",
    repo_root: RepoRootOption = None,
) -> None:
    """Emit a Codex skill handoff for repo guidance sync."""

    print_report(
        {
            "task": "guidance-sync",
            "repo_root": str(repo_root or default_repo_root()),
            "guidance_kind": kind,
        }
    )
