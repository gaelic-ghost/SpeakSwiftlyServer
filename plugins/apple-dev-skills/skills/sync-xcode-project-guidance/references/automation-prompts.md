# Xcode Guidance Sync Automation Prompts

## Purpose

Use these prompts when an automation or operator wants a deterministic way to invoke the guidance-sync workflow for an existing Xcode app repository.

## Required Inputs

- `repo_root`
- optional `workspace_path`
- optional `skip_validation`
- optional `dry_run`

## Prompt Template

```text
Use sync-xcode-project-guidance for this repository.

Inputs:
- repo_root: <REPO_ROOT>
- workspace_path: <WORKSPACE_PATH_OR_BLANK>
- skip_validation: <true_or_false>
- dry_run: <true_or_false>

Goals:
- detect whether this is an existing Xcode app repo
- add or merge AGENTS.md guidance if needed
- keep the result bounded and idempotent
- hand off active engineering work to xcode-app-project-workflow afterward
```
