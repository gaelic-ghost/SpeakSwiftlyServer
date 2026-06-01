from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class CommandRecommendation:
    command: str
    reason: str
    requires_approval: bool = False


@dataclass(frozen=True)
class GuidanceHandoff:
    skill_name: str
    prompt: str
    commands: tuple[CommandRecommendation, ...] = ()


@dataclass(frozen=True)
class RepoSnapshot:
    repo_root: Path
    branch: str
    status_lines: tuple[str, ...]
    latest_tag: str | None
    remotes: tuple[str, ...]
    package_dependencies: tuple[str, ...]

    @property
    def is_clean(self) -> bool:
        return not self.status_lines


@dataclass(frozen=True)
class BranchAudit:
    base_branch: str
    current_branch: str
    merged_local_branches: tuple[str, ...]
    deletion_candidates: tuple[str, ...]
    protected_branches: tuple[str, ...] = ("main", "master", "develop")


@dataclass
class AgentReport:
    title: str
    summary: str
    findings: list[str] = field(default_factory=list)
    commands: list[CommandRecommendation] = field(default_factory=list)
    guidance_handoffs: list[GuidanceHandoff] = field(default_factory=list)

    def as_markdown(self) -> str:
        lines = [f"# {self.title}", "", self.summary]
        if self.findings:
            lines.extend(["", "## Findings"])
            lines.extend(f"- {finding}" for finding in self.findings)
        if self.commands:
            lines.extend(["", "## Commands"])
            for command in self.commands:
                approval = " Approval required." if command.requires_approval else ""
                lines.append(f"- `{command.command}` - {command.reason}.{approval}")
        if self.guidance_handoffs:
            lines.extend(["", "## Guidance Handoffs"])
            for handoff in self.guidance_handoffs:
                lines.append(f"### {handoff.skill_name}")
                lines.extend(["", "```markdown", handoff.prompt, "```"])
                for command in handoff.commands:
                    approval = " Approval required." if command.requires_approval else ""
                    lines.append(f"- `{command.command}` - {command.reason}.{approval}")
        return "\n".join(lines).rstrip() + "\n"
