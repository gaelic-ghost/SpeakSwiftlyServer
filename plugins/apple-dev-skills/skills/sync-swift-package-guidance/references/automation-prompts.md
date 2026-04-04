# Swift Package Guidance Sync Automation Prompts

## Dry Run

```text
Run `scripts/run_workflow.py --repo-root <path> --dry-run` and return the planned Swift package guidance-sync actions without writing files.
```

## Apply Sync

```text
Run `scripts/run_workflow.py --repo-root <path>` and sync the bounded Swift package guidance into `AGENTS.md` for the existing SwiftPM repo at that path.
```

## Apply Sync Without Validation

```text
Run `scripts/run_workflow.py --repo-root <path> --skip-validation` when the caller explicitly wants the Swift package guidance merged without post-write validation.
```
