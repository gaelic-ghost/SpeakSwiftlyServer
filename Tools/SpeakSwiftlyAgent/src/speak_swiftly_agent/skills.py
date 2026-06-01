from __future__ import annotations

from pathlib import Path

from speak_swiftly_agent.models import CommandRecommendation, GuidanceHandoff


def guidance_sync_handoff(repo_root: Path, kind: str = "swift-package") -> GuidanceHandoff:
    if kind != "swift-package":
        raise ValueError(f"Unsupported guidance sync kind: {kind}")

    prompt = f"""Use $sync-swift-package-guidance.

Scope:
- Repository: {repo_root}
- Treat Package.swift as the package source of truth.
- Preserve repo-local AGENTS.md sections and user-authored prose.
- Report whether AGENTS.md and repo-maintenance guidance are already current.

Task:
1. Run the Swift package guidance sync workflow in dry-run mode first if available.
2. If it reports needed changes, summarize the exact files it would change before editing.
3. After any approved edit, run the repo's relevant validation path and report results.
"""
    return GuidanceHandoff(
        skill_name="sync-swift-package-guidance",
        prompt=prompt,
        commands=(
            CommandRecommendation(
                command="sh scripts/repo-maintenance/sync-shared.sh",
                reason="Refresh shared repo-maintenance tooling through the repo-owned sync path",
                requires_approval=False,
            ),
            CommandRecommendation(
                command="sh scripts/repo-maintenance/validate-all.sh",
                reason="Validate guidance and maintainer tooling after a sync",
                requires_approval=False,
            ),
        ),
    )
