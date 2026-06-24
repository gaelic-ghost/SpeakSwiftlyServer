---
name: speak-swiftly-mcp
description: Use when a user wants general help with the slim Speak Swiftly MCP surface, including broad requests to inspect runtime state, read replies aloud, draft voice or text-profile guidance, or decide whether to use MCP resources, MCP prompts, the live-speech MCP tool, or HTTP endpoints.
---

# SpeakSwiftly MCP

Use this skill as the first orientation pass when the request is about the SpeakSwiftly MCP surface broadly rather than one narrow operation.

## Start Here

- Treat the local `speak_swiftly` MCP server from this repository's [`.mcp.json`](../../.mcp.json) as the default surface.
- For a broad status question, read `speak-swiftly://overview` first. Use `get_runtime_overview` only for compatibility clients that cannot read MCP resources cleanly.
- For a "what can this surface do?" question, use [API.md](../../API.md) first, then the current source-of-truth catalog files:
  - [MCPToolCatalog.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPToolCatalog.swift)
  - [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift)
  - [MCPPrompts.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPPrompts.swift)

## Workflow Split

- Runtime, queue, playback, request tracking, backend switching, and cancellation over HTTP plus slim MCP reads:
  Use `$speak-swiftly-runtime-operator`.
- Voice creation over HTTP, voice selection, live speech over MCP, retained artifact generation over HTTP, and retained artifact inspection over HTTP:
  Use `$speak-swiftly-voice-workflows`.
- Text normalization styles, stored text profiles, and replacement authoring over HTTP plus MCP drafting prompts:
  Use `$speak-swiftly-text-profiles`.

## General Operating Rules

- Prefer MCP resources for orientation and verification. Use the MCP tool only for immediate live speech playback through `generate_speech`; use HTTP endpoints for mutations, cancellation, clearing, playback control, retained generation, runtime changes, and network-audio selection.
- When the user needs help deciding which action family fits best, use the `choose_surface_action` prompt instead of improvising from memory.
- When a tool returns `request_id`, follow it with `speak-swiftly://requests/{request_id}` or `speak-swiftly://overview` instead of guessing whether the work finished.
- Distinguish generation backlog from playback backlog. A request can be done generating and still be queued for playback.
- Do not silently substitute a different voice profile when the requested profile is missing unless the user explicitly asks for fallback behavior.
- When repository docs and the live MCP server seem out of sync, trust the current source files in `Sources/SpeakSwiftlyServer/MCP/` over older prose.
