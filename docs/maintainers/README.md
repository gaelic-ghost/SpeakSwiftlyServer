# Maintainer Docs

This directory holds current maintainer maps, durable workflow contracts, and compact historical notes for `SpeakSwiftlyServer`.

Keep active docs here only when they still guide present-day editing, validation, release, or operator decisions. Completed implementation plans should be folded into [`implementation-history.md`](implementation-history.md) or the relevant release notes instead of remaining as parallel roadmaps.

## Active Maps

- [`source-layout.md`](source-layout.md)
  Current source ownership map for host, HTTP, MCP, config, executable, resources, and tests.
- [`speakswiftly-api-coverage-matrix.md`](speakswiftly-api-coverage-matrix.md)
  Current comparison between the resolved `SpeakSwiftly` package API and this server's HTTP, MCP, and embedded surfaces.
- [`speakswiftly-vnext-adoption-plan.md`](speakswiftly-vnext-adoption-plan.md)
  Planned adoption path for the next upstream `SpeakSwiftly` release, with public-product integration rules.
- [`release-workflow.md`](release-workflow.md)
  Current release contract and validation handoff.
- [`webui-control-panel.md`](webui-control-panel.md)
  Current build, routing, and API-boundary guidance for the bundled local control panel.

## Active Operational Notes

- [`default-voices-and-media-options.md`](default-voices-and-media-options.md)
  Built-in voice media, package resources, and default voice policy.
- [`live-service-reliability-follow-ups.md`](live-service-reliability-follow-ups.md)
  Follow-up notes for live service reliability and runtime checks.
- [`plugin-install-testing.md`](plugin-install-testing.md)
  Current plugin install and doctor testing guidance.
- [`skills-surface-audit.md`](skills-surface-audit.md)
  Current skills and plugin surface audit notes.

## Maintainer Tools

- [`../../Tools/SpeakSwiftlyAgent`](../../Tools/SpeakSwiftlyAgent)
  LangGraph-based maintainer assistant for repo explanation, dependency-update planning, branch
  cleanup audits, and guidance-sync handoff prompts.
- [`../../Tools/SpeakSwiftlyAgent/docs/next-slices.md`](../../Tools/SpeakSwiftlyAgent/docs/next-slices.md)
  Planned next slices for the maintainer assistant.

## Historical Notes

- [`implementation-history.md`](implementation-history.md)
  Consolidated history for completed host phases, public API cleanup decisions, DocC setup, Application Support config, runtime profile-root threading, and embedded lifecycle composition.

Release-specific checklists and notes remain under [`../releases`](../releases/). Investigation writeups remain under [`../investigations`](../investigations/).
