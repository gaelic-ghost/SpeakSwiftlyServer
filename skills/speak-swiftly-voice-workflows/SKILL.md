---
name: speak-swiftly-voice-workflows
description: Use when a user wants SpeakSwiftly voice-profile or speech-generation help through the MCP surface, including voice creation from text or audio, profile listing, renaming, rerolling, deletion, immediate spoken playback, retained audio artifacts, retained batch jobs, and generation artifact tracking.
---

# SpeakSwiftly Voice Workflows

Use this skill for voice selection, voice creation, and speech-generation work on the local `speak_swiftly` MCP surface.

## Start Here

- Read `speak-swiftly://voices` before creating, renaming, rerolling, deleting, or choosing a profile. Use `list_voice_profiles` only for compatibility clients that cannot read MCP resources cleanly.
- Use `speak-swiftly://voices/{profile_name}` when the user is choosing or inspecting one specific stored voice. System-authored built-ins redact seed source text and voice-design prompts from this ordinary read path.
- If the user wants help designing a voice rather than executing immediately, prefer the `draft_profile_voice_description`, `draft_profile_source_text`, and `draft_voice_design_instruction` prompts plus the guide flow documented in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift).

## Creation And Editing

- Use `create_voice_profile_from_description` when the user has target sound qualities and source text.
- Use `create_voice_profile_from_audio` when the user has reference audio. Provide `transcript` whenever the spoken words are already known.
- Use `update_voice_profile_name` for a pure rename.
- Use `reroll_voice_profile` when the user wants the same stored name rebuilt from its original inputs.
- Use `delete_voice_profile` only after confirming the exact stored `profile_name`.
- The package-owned built-in defaults are `swift-signal` and `swift-anchor`. Treat them as system seed voices, not user-authored example names. Normal users should list and select them; use `inspect_builtin_voice_seed` only for maintainer or development work that truly needs the built-in seed source text, voice-design prompt, or provenance.
- When a user wants broad-appeal user-authored example profiles, suggest names and voice directions such as:
  - `swift-lumen`: luminous, clean, gentle, and polished
  - `swift-arc`: compact, focused, modern, and precise
  - `swift-melody`: warm, expressive, friendly, and persona-ready
  - `swift-foundry`: grounded, maker-like, textured, and steady

## Speech And Artifacts

- Use `generate_speech` when the user wants audible playback now.
- Use `generate_audio_file` when the user wants a saved retained artifact instead of immediate playback.
- Use `generate_batch` when the user wants multiple retained artifacts generated under one voice profile.
- Pass `text_profile_id` only when the user explicitly wants a stored normalization profile on that request.
- Pass `source_format` when source-like input needs explicit format-aware normalization. HTTP and MCP speech requests get transport provenance in `request_context` by default; pass `cwd`, `repo_root`, or explicit `request_context` only when path or caller metadata needs to be more specific.
- Pass `qwen_pre_model_text_chunking` only when the user explicitly wants Qwen live playback to chunk before model generation; omitted requests keep the runtime's normal single-pass live path.

## Tracking

- After `generate_speech`, read `speak-swiftly://requests/{request_id}` or `speak-swiftly://overview`.
- After retained-file or batch requests, follow `speak-swiftly://requests/{request_id}` first, then inspect `speak-swiftly://generation/jobs`, `speak-swiftly://generation/jobs/{job_id}`, `speak-swiftly://generation/artifacts`, or `speak-swiftly://generation/artifacts/{artifact_id}`.
- Use generation jobs and artifacts to inspect retained outputs; the older generated-file and generated-batch read tools are not carried forward.
- Use `expire_generation_job` only when the user explicitly wants one retained generation job removed.
