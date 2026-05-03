---
name: speak-swiftly-runtime-operator
description: Use when a user wants to inspect or control the running SpeakSwiftlyServer MCP runtime, including readiness, queues, playback state, active requests, generation backlog, playback backlog, backend switching, model reloads, queue clearing, or request cancellation.
---

# SpeakSwiftly Runtime Operator

Use this skill for operator-style runtime work on the local `speak_swiftly` MCP surface.

## Primary Reads

- Start with `speak://runtime/overview` for any broad runtime question. Use `get_runtime_overview` only for compatibility clients that cannot read MCP resources cleanly.
- Read `speak://runtime/status` when the user specifically needs the worker stage, resident-model state, or current backend.
- Read the playback section of `speak://runtime/overview` when the question is about whether anything is actively playing.
- Read `speak://requests` when the user is asking about recent server work, or `speak://requests/{request_id}` for one specific tracked request.

## Queue And Request Triage

- Use the generation queue in `speak://runtime/overview` for "what is still generating?"
- Use the playback queue in `speak://runtime/overview` for "what is waiting to be heard?"
- Read `speak://playback/guide` when the user wants help choosing the least destructive queue or playback action.
- Use `speak://requests/{request_id}` after any accepted request or cancellation so the user can see the retained state directly.
- When multiple similar requests exist, confirm the exact `request_id` from the resource before cancelling anything.

## Control Operations

- Use `pause_playback` or `resume_playback` only after confirming current playback state when that matters to the user.
- Use `clear_generation_queue` when the user wants to drop waiting generation work without stopping active generation.
- Use `clear_playback_queue` when the user wants to drop queued audible work without stopping active playback.
- Use `cancel_generation` or `cancel_playback` when the user wants one specific request stopped in one queue.
- Use `cancel_request` only when the user explicitly wants the broad compatibility cancel behavior.
- Use `switch_speech_backend` for an immediate backend flip on the running runtime.
- Use `set_staged_config` when the user wants a different backend on the next restart without changing the current one.
- Use `reload_models` or `unload_models` only when the user is explicitly asking about model residency or memory pressure.

## Verification

- After any mutation, read `speak://runtime/overview` again so the response is grounded in the post-change state.
- Use `draft_queue_playback_notice` when the user wants a short spoken-safe acknowledgement for accepted queued playback work.
- When a control path fails, cite the actual runtime or request snapshot instead of paraphrasing vaguely.
- The playback and queue workflow guidance embedded in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift) is the best repo-local explanation of intended operator flow.
