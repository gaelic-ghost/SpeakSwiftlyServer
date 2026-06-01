from __future__ import annotations

import subprocess
from pathlib import Path

from speak_swiftly_agent.models import BranchAudit, RepoSnapshot


class RepoError(RuntimeError):
    """Raised when a repository command cannot complete."""


def resolve_repo_root(repo_root: Path) -> Path:
    path = repo_root.expanduser().resolve()
    if not path.exists():
        raise RepoError(f"{path} does not exist.")

    process = subprocess.run(
        ["git", "-C", str(path), "rev-parse", "--show-toplevel"],
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RepoError(f"{path} is not inside a Git checkout: {detail}")
    return Path(process.stdout.strip()).resolve()


def run_git(repo_root: Path, args: list[str]) -> str:
    process = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise RepoError(f"git {' '.join(args)} failed in {repo_root}: {detail}")
    return process.stdout.strip()


def run_git_optional(repo_root: Path, args: list[str]) -> str | None:
    process = subprocess.run(
        ["git", *args],
        cwd=repo_root,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        return None
    return process.stdout.strip() or None


def collect_repo_snapshot(repo_root: Path) -> RepoSnapshot:
    root = resolve_repo_root(repo_root)
    branch = run_git(root, ["branch", "--show-current"]) or "detached"
    status = tuple(
        line for line in run_git(root, ["status", "--short"]).splitlines() if line.strip()
    )
    latest_tag = run_git_optional(root, ["describe", "--tags", "--abbrev=0"])
    remotes = tuple(line for line in run_git(root, ["remote", "-v"]).splitlines() if line.strip())
    dependencies = read_package_dependency_lines(root)
    return RepoSnapshot(
        repo_root=root,
        branch=branch,
        status_lines=status,
        latest_tag=latest_tag,
        remotes=remotes,
        package_dependencies=dependencies,
    )


def read_package_dependency_lines(repo_root: Path) -> tuple[str, ...]:
    manifest = repo_root / "Package.swift"
    if not manifest.exists():
        return ()

    lines = []
    for line in manifest.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if ".package(" in stripped or "url:" in stripped and "github.com" in stripped:
            lines.append(stripped)
    return tuple(lines)


def audit_merged_branches(repo_root: Path, base_branch: str = "main") -> BranchAudit:
    root = resolve_repo_root(repo_root)
    current_branch = run_git(root, ["branch", "--show-current"]) or "detached"
    merged_output = run_git(
        root,
        ["branch", "--merged", base_branch, "--format", "%(refname:short)"],
    )
    merged_branches = tuple(line.strip() for line in merged_output.splitlines() if line.strip())
    protected = ("main", "master", "develop", current_branch)
    deletion_candidates = tuple(
        branch
        for branch in merged_branches
        if branch not in protected and not branch.startswith("release/")
    )
    return BranchAudit(
        base_branch=base_branch,
        current_branch=current_branch,
        merged_local_branches=merged_branches,
        deletion_candidates=deletion_candidates,
        protected_branches=protected,
    )
