from __future__ import annotations

from pathlib import Path
from typing import Any, Literal, TypedDict, cast
from uuid import uuid4

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph

from speak_swiftly_agent.models import AgentReport, CommandRecommendation
from speak_swiftly_agent.repo import audit_merged_branches, collect_repo_snapshot
from speak_swiftly_agent.skills import guidance_sync_handoff

AgentTask = Literal["overview", "dependency-plan", "branch-audit", "guidance-sync"]


class AgentState(TypedDict, total=False):
    task: AgentTask
    repo_root: str
    package: str
    target_version: str
    base_branch: str
    guidance_kind: str
    report: AgentReport


def build_graph() -> Any:
    graph = StateGraph(AgentState)
    graph.add_node("overview", overview_node)
    graph.add_node("dependency_plan", dependency_plan_node)
    graph.add_node("branch_audit", branch_audit_node)
    graph.add_node("guidance_sync", guidance_sync_node)
    graph.add_conditional_edges(
        START,
        route_task,
        {
            "overview": "overview",
            "dependency-plan": "dependency_plan",
            "branch-audit": "branch_audit",
            "guidance-sync": "guidance_sync",
        },
    )
    graph.add_edge("overview", END)
    graph.add_edge("dependency_plan", END)
    graph.add_edge("branch_audit", END)
    graph.add_edge("guidance_sync", END)
    return graph.compile(checkpointer=InMemorySaver())


def invoke_agent(state: AgentState) -> AgentReport:
    app = build_graph()
    result = app.invoke(state, {"configurable": {"thread_id": str(uuid4())}})
    return cast(AgentReport, result["report"])


def route_task(state: AgentState) -> AgentTask:
    return state.get("task", "overview")


def overview_node(state: AgentState) -> AgentState:
    snapshot = collect_repo_snapshot(Path(state["repo_root"]))
    cleanliness = "clean" if snapshot.is_clean else "dirty"
    findings = [
        f"Current branch: {snapshot.branch}",
        f"Working tree: {cleanliness}",
        f"Latest tag: {snapshot.latest_tag or 'none found'}",
    ]
    if snapshot.status_lines:
        findings.extend(f"Status: {line}" for line in snapshot.status_lines)
    if snapshot.package_dependencies:
        dependency_count = len(snapshot.package_dependencies)
        findings.append(f"Package dependency declarations found: {dependency_count}")

    return {
        "report": AgentReport(
            title="SpeakSwiftlyAgent Repo Overview",
            summary="Repository state was inspected without making changes.",
            findings=findings,
            commands=[
                CommandRecommendation(
                    command="sh scripts/repo-maintenance/validate-all.sh",
                    reason="Full local maintainer validation before a release or broad handoff",
                )
            ],
        )
    }


def dependency_plan_node(state: AgentState) -> AgentState:
    repo_root = Path(state["repo_root"])
    snapshot = collect_repo_snapshot(repo_root)
    package = state.get("package", "SpeakSwiftly")
    target_version = state.get("target_version", "the requested version")
    findings = [
        f"Current branch: {snapshot.branch}",
        f"Target dependency: {package} -> {target_version}",
        "Keep public dependency declarations pointed at fetchable GitHub versions.",
        "Run normal SwiftPM build/test checks before wider validation.",
    ]
    commands = [
        CommandRecommendation(
            command=f"xcrun swift package update {package}",
            reason="Resolve the requested dependency through SwiftPM",
        ),
        CommandRecommendation(
            command="xcrun swift build",
            reason="Catch package graph or compile breakage after resolution",
        ),
        CommandRecommendation(
            command="xcrun swift test",
            reason="Run the non-live package test suite",
        ),
        CommandRecommendation(
            command="sh scripts/repo-maintenance/validate-all.sh",
            reason="Run the full maintainer gate before release handoff",
        ),
    ]
    return {
        "report": AgentReport(
            title="Dependency Update Plan",
            summary="A safe dependency-update plan was prepared without editing files.",
            findings=findings,
            commands=commands,
        )
    }


def branch_audit_node(state: AgentState) -> AgentState:
    repo_root = Path(state["repo_root"])
    base_branch = state.get("base_branch", "main")
    audit = audit_merged_branches(repo_root, base_branch=base_branch)
    findings = [
        f"Base branch: {audit.base_branch}",
        f"Current branch: {audit.current_branch}",
        f"Merged local branches: {', '.join(audit.merged_local_branches) or 'none'}",
        f"Deletion candidates: {', '.join(audit.deletion_candidates) or 'none'}",
    ]
    commands = [
        CommandRecommendation(
            command=f"git branch --merged {base_branch}",
            reason="Review merged local branches before deleting anything",
        )
    ]
    commands.extend(
        CommandRecommendation(
            command=f"git branch -d {branch}",
            reason=f"Delete merged local branch {branch}",
            requires_approval=True,
        )
        for branch in audit.deletion_candidates
    )
    return {
        "report": AgentReport(
            title="Branch Cleanup Audit",
            summary="Merged branch cleanup was audited without deleting branches.",
            findings=findings,
            commands=commands,
        )
    }


def guidance_sync_node(state: AgentState) -> AgentState:
    repo_root = Path(state["repo_root"]).expanduser().resolve()
    handoff = guidance_sync_handoff(repo_root, kind=state.get("guidance_kind", "swift-package"))
    return {
        "report": AgentReport(
            title="Guidance Sync Handoff",
            summary=(
                "Guidance sync is exposed as a Codex skill handoff because installed skills are "
                "owned by the Codex harness rather than this Python process."
            ),
            guidance_handoffs=[handoff],
        )
    }
