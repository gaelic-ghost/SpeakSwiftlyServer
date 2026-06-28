---
name: speak-swiftly-runtime-operator
description: Use when a user wants to inspect or control the running SpeakSwiftlyServer runtime, including readiness, queues, playback state, active requests, generation backlog, playback backlog, backend switching, model reloads, queue clearing, request cancellation, or the local control panel. Use slim MCP resources for broad reads, HTTP endpoints for controls, and the browser-served control panel for visual operator help.
---

# SpeakSwiftly Runtime Operator

Use this skill for operator-style runtime work. The local `speak_swiftly` MCP surface is the orientation and live-speech layer; HTTP owns runtime and queue controls.

## Local Control Panel

- Call the browser surface the local control panel. Use `WebUI` only when talking about the checked-in frontend package or bundled static resource, and avoid `dashboard` for the whole surface because it includes live controls.
- Open `http://127.0.0.1:7338/control-panel/` for the foreground tool's default local HTTP listener. For an installed service, use the configured local HTTP listener port and the same `/control-panel/` path.
- Use the control panel when the user wants a visual runtime overview, wants to inspect queue and request state interactively, or asks how to operate the service in a browser.
- The control panel is backed by the same HTTP routes documented in `API.md`; it does not add a separate control API. If a control panel action fails, inspect the matching HTTP endpoint or `speak-swiftly://overview` before blaming the frontend.
- Agents should still use MCP resources or direct HTTP calls for precise state capture, automation, and mutations. The control panel is for user-facing inspection and guided operation, not for replacing machine-readable checks.

## Primary Reads

- Start with `speak-swiftly://overview` for any broad runtime question.
- Use `GET /status` when the user specifically needs the worker stage, resident-model state, or current backend.
- Read the playback section of `speak-swiftly://overview` when the question is about whether anything is actively playing.
- Use `GET /requests` when the user is asking about recent server work, or `speak-swiftly://requests/{request_id}` / `GET /requests/{request_id}` for one specific tracked request.

## Queue And Request Triage

- Use the generation queue in `speak-swiftly://overview` for "what is still generating?"
- Use the playback queue in `speak-swiftly://overview` for "what is waiting to be heard?"
- Read `speak-swiftly://playback/guide` when the user wants help choosing the least destructive queue or playback action.
- Use `speak-swiftly://requests/{request_id}` after any accepted request or cancellation so the user can see the retained state directly.
- When multiple similar requests exist, confirm the exact `request_id` from the resource before cancelling anything.

## Control Operations

- Use `POST /playback/pause` or `POST /playback/resume` only after confirming current playback state when that matters to the user.
- Use `DELETE /generation/queue` when the user wants to drop waiting generation work without stopping active generation.
- Use `DELETE /playback/queue` when the user wants to drop queued audible work without stopping active playback.
- Use `DELETE /requests/{request_id}` when the user wants one specific request stopped. Omit `scope` for the broad cancel path, or pass `?scope=generation` / `?scope=playback` when the user wants to target one queue.
- Use `POST /backend` for an immediate backend flip on the running runtime.
- Use `PUT /configuration` when the user wants a different backend or `duck_media_volume` media-ducking setting on the next restart without changing the current runtime.
- Use `POST /models/reload` or `POST /models/unload` only when the user is explicitly asking about model residency or memory pressure.

## Verification

- After any mutation, read `speak-swiftly://overview` again so the response is grounded in the post-change state.
- Use `draft_queue_playback_notice` when the user wants a short spoken-safe acknowledgement for accepted queued playback work.
- When a control path fails, cite the actual runtime or request snapshot instead of paraphrasing vaguely.
- The playback and queue workflow guidance embedded in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift) is the best repo-local explanation of intended operator flow.
