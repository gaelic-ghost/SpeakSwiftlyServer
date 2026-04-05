#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.9"
# ///
"""Install or refresh the managed repo-maintenance toolkit files."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


MANAGED_TOOLKIT_FILES = [
    ("repo-maintenance/validate-all.sh", "scripts/repo-maintenance/validate-all.sh"),
    ("repo-maintenance/sync-shared.sh", "scripts/repo-maintenance/sync-shared.sh"),
    ("repo-maintenance/release.sh", "scripts/repo-maintenance/release.sh"),
    ("repo-maintenance/lib/common.sh", "scripts/repo-maintenance/lib/common.sh"),
    ("repo-maintenance/validations/10-toolkit-layout.sh", "scripts/repo-maintenance/validations/10-toolkit-layout.sh"),
    ("repo-maintenance/validations/20-agents-guidance.sh", "scripts/repo-maintenance/validations/20-agents-guidance.sh"),
    ("repo-maintenance/validations/30-ci-wrapper.sh", "scripts/repo-maintenance/validations/30-ci-wrapper.sh"),
    ("repo-maintenance/syncing/README.md", "scripts/repo-maintenance/syncing/README.md"),
    ("repo-maintenance/release/10-preflight.sh", "scripts/repo-maintenance/release/10-preflight.sh"),
    ("repo-maintenance/release/20-tag-release.sh", "scripts/repo-maintenance/release/20-tag-release.sh"),
    ("repo-maintenance/release/30-push-release.sh", "scripts/repo-maintenance/release/30-push-release.sh"),
    ("repo-maintenance/release/40-github-release.sh", "scripts/repo-maintenance/release/40-github-release.sh"),
    ("repo-maintenance/config/validation.env", "scripts/repo-maintenance/config/validation.env"),
    ("repo-maintenance/config/release.env", "scripts/repo-maintenance/config/release.env"),
    ("repo-maintenance/hooks/pre-commit.sample", "scripts/repo-maintenance/hooks/pre-commit.sample"),
]
MANAGED_WORKFLOW_FILE = ".github/workflows/validate-repo-maintenance.yml"
EXECUTABLE_SUFFIXES = {".sh", ".py", ".sample"}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", required=True)
    parser.add_argument("--operation", choices=("install", "refresh", "report-only"), default="install")
    parser.add_argument("--skip-github-workflow", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    return parser


def assets_root() -> Path:
    return Path(__file__).resolve().parents[1] / "assets"


def target_pairs(skip_github_workflow: bool) -> list[tuple[Path, Path]]:
    root = assets_root()
    pairs = []
    for source_relative, target_relative in MANAGED_TOOLKIT_FILES:
        pairs.append((root / source_relative, Path(target_relative)))
    if not skip_github_workflow:
        pairs.append(
            (
                root / "github" / "repo-maintenance-workflows" / "validate-repo-maintenance.yml",
                Path(MANAGED_WORKFLOW_FILE),
            )
        )
    return pairs


def ensure_safe_target(repo_root: Path, relative_target: Path) -> None:
    target = repo_root / relative_target
    if target.exists() and not target.is_file():
        raise RuntimeError(
            f"The managed target path {target} exists but is not a regular file."
        )


def copy_file(source: Path, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    if source.suffix in EXECUTABLE_SUFFIXES:
        target.chmod(0o755)


def main() -> int:
    args = build_parser().parse_args()
    repo_root = Path(args.repo_root).expanduser().resolve()
    actions: list[str] = []
    managed_files = [relative.as_posix() for _, relative in target_pairs(args.skip_github_workflow)]

    if not repo_root.exists():
        print(
            json.dumps(
                {
                    "status": "blocked",
                    "path_type": "primary",
                    "repo_root": str(repo_root),
                    "managed_files": managed_files,
                    "actions": actions,
                    "stderr": "The requested repo root does not exist.",
                    "next_step": "Create or choose an existing repository root and rerun the workflow.",
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    if not repo_root.is_dir():
        print(
            json.dumps(
                {
                    "status": "blocked",
                    "path_type": "primary",
                    "repo_root": str(repo_root),
                    "managed_files": managed_files,
                    "actions": actions,
                    "stderr": "The requested repo root is not a directory.",
                    "next_step": "Use a directory path for --repo-root and rerun the workflow.",
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    try:
        for _, relative_target in target_pairs(args.skip_github_workflow):
            ensure_safe_target(repo_root, relative_target)
    except RuntimeError as exc:
        print(
            json.dumps(
                {
                    "status": "blocked",
                    "path_type": "primary",
                    "repo_root": str(repo_root),
                    "managed_files": managed_files,
                    "actions": actions,
                    "stderr": str(exc),
                    "next_step": "Resolve the conflicting target path and rerun the workflow.",
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 1

    if args.operation == "report-only" or args.dry_run:
        for source, relative_target in target_pairs(args.skip_github_workflow):
            target = repo_root / relative_target
            if target.exists():
                actions.append(f"refresh {relative_target.as_posix()} from {source.relative_to(assets_root()).as_posix()}")
            else:
                actions.append(f"install {relative_target.as_posix()} from {source.relative_to(assets_root()).as_posix()}")
        print(
            json.dumps(
                {
                    "status": "success",
                    "path_type": "fallback",
                    "repo_root": str(repo_root),
                    "managed_files": managed_files,
                    "actions": actions,
                    "validation_result": "skipped (--dry-run)" if args.dry_run else "skipped (report-only)",
                    "next_step": "Run without --dry-run or report-only to install or refresh the repo-maintenance toolkit.",
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    for source, relative_target in target_pairs(args.skip_github_workflow):
        target = repo_root / relative_target
        action = "refreshed" if target.exists() else "installed"
        copy_file(source, target)
        actions.append(f"{action} {relative_target.as_posix()}")

    print(
        json.dumps(
            {
                "status": "success",
                "path_type": "primary",
                "repo_root": str(repo_root),
                "managed_files": managed_files,
                "actions": actions,
                "validation_result": "managed files synced",
                "next_step": "Use scripts/repo-maintenance/validate-all.sh locally and keep CI as a thin wrapper around that command.",
            },
            indent=2,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
