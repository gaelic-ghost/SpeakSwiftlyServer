from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer
from rich.console import Console

from speak_swiftly_agent.graph import AgentState, invoke_agent
from speak_swiftly_agent.reports import DEFAULT_REPORT_DIR, write_agent_report

app = typer.Typer(help="Maintainer-side repo agent for SpeakSwiftlyServer.")
console = Console()


RepoRootOption = Annotated[Path | None, typer.Option(help="Repository root to inspect.")]
ReportDirOption = Annotated[
    Path | None,
    typer.Option(help=f"Directory for durable Markdown reports. Defaults to {DEFAULT_REPORT_DIR}."),
]
WriteReportOption = Annotated[
    bool,
    typer.Option(
        "--write-report/--no-write-report",
        help="Persist the generated Markdown report under docs/agents.",
    ),
]


def default_repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


def print_report(
    state: AgentState,
    *,
    report_dir: Path | None = None,
    write_report: bool = True,
) -> None:
    report = invoke_agent(state)
    console.print(report.as_markdown())
    if write_report:
        path = write_agent_report(
            Path(state["repo_root"]),
            state.get("task", "report"),
            report,
            report_dir,
        )
        console.print(f"[dim]Saved report to {path}[/dim]")


@app.command()
def overview(
    repo_root: RepoRootOption = None,
    report_dir: ReportDirOption = None,
    write_report: WriteReportOption = True,
) -> None:
    """Summarize repository state without making changes."""

    print_report(
        {"task": "overview", "repo_root": str(repo_root or default_repo_root())},
        report_dir=report_dir,
        write_report=write_report,
    )


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
    report_dir: ReportDirOption = None,
    write_report: WriteReportOption = True,
) -> None:
    """Plan a dependency update without editing package files."""

    print_report(
        {
            "task": "dependency-plan",
            "repo_root": str(repo_root or default_repo_root()),
            "package": package,
            "target_version": target_version,
        },
        report_dir=report_dir,
        write_report=write_report,
    )


@app.command()
def branch_audit(
    base_branch: Annotated[str, typer.Option(help="Branch used to decide merged status.")] = "main",
    repo_root: RepoRootOption = None,
    report_dir: ReportDirOption = None,
    write_report: WriteReportOption = True,
) -> None:
    """Audit merged local branches without deleting anything."""

    print_report(
        {
            "task": "branch-audit",
            "repo_root": str(repo_root or default_repo_root()),
            "base_branch": base_branch,
        },
        report_dir=report_dir,
        write_report=write_report,
    )


@app.command()
def guidance_sync(
    kind: Annotated[str, typer.Option(help="Guidance sync family to prepare.")] = "swift-package",
    repo_root: RepoRootOption = None,
    report_dir: ReportDirOption = None,
    write_report: WriteReportOption = True,
) -> None:
    """Emit a Codex skill handoff for repo guidance sync."""

    print_report(
        {
            "task": "guidance-sync",
            "repo_root": str(repo_root or default_repo_root()),
            "guidance_kind": kind,
        },
        report_dir=report_dir,
        write_report=write_report,
    )
