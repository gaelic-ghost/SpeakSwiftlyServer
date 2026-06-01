# Agent Reports

This directory is the durable home for maintainer-agent docs and generated reports.

`SpeakSwiftlyAgent` writes command reports under [`reports`](reports/) by default. These files are
maintainer notes, not package API documentation and not runtime resources.

Use `--no-write-report` for one-off terminal-only runs, or `--report-dir` when a report belongs in a
different review artifact.
