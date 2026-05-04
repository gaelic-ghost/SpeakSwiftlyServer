---
name: speak-swiftly-mcp
description: Use when a user wants general help with the Speak Swiftly MCP surface, including broad requests to inspect runtime state, read replies aloud, manage voice or text profiles, or decide which SpeakSwiftly MCP workflow to use. This skill is the orientation layer for the local `speak_swiftly` MCP server and routes work into the narrower runtime, voice, and text-profile skills.
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

- Runtime, queue, playback, request tracking, backend switching, and cancellation:
  Use `$speak-swiftly-runtime-operator`.
- Voice creation, voice selection, live speech, retained artifact generation, and retained artifact inspection:
  Use `$speak-swiftly-voice-workflows`.
- Text normalization styles, stored text profiles, and replacement authoring:
  Use `$speak-swiftly-text-profiles`.

## General Operating Rules

- Prefer resources for orientation and verification, then use tools for queueing, mutations, cancellation, clearing, playback control, and runtime changes.
- When the user needs help deciding which action family fits best, use the `choose_surface_action` prompt instead of improvising from memory.
- When a tool returns `request_id`, follow it with `speak-swiftly://requests/{request_id}` or `speak-swiftly://overview` instead of guessing whether the work finished.
- Distinguish generation backlog from playback backlog. A request can be done generating and still be queued for playback.
- Do not silently substitute a different voice profile when the requested profile is missing unless the user explicitly asks for fallback behavior.
- When repository docs and the live MCP server seem out of sync, trust the current source files in `Sources/SpeakSwiftlyServer/MCP/` over older prose.
