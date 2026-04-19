---
name: speak-swiftly-voice-workflows
description: Use when a user wants SpeakSwiftly voice-profile or speech-generation help through the MCP surface, including voice creation from text or audio, profile listing, renaming, rerolling, deletion, immediate spoken playback, retained audio files, retained batches, and generation artifact tracking.
---

# SpeakSwiftly Voice Workflows

Use this skill for voice selection, voice creation, and speech-generation work on the local `speak_swiftly` MCP surface.

## Start Here

- Read `list_voice_profiles` or `speak://voices` before creating, renaming, rerolling, deleting, or choosing a profile.
- Use `speak://voices/{profile_name}` when the user is working on one specific stored voice.
- If the user wants help designing a voice rather than executing immediately, prefer the `draft_profile_voice_description`, `draft_profile_source_text`, and `draft_voice_design_instruction` prompts plus the guide flow documented in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift).

## Creation And Editing

- Use `create_voice_profile_from_description` when the user has target sound qualities and source text.
- Use `create_voice_profile_from_audio` when the user has reference audio. Provide `transcript` whenever the spoken words are already known.
- Use `update_voice_profile_name` for a pure rename.
- Use `reroll_voice_profile` when the user wants the same stored name rebuilt from its original inputs.
- Use `delete_voice_profile` only after confirming the exact stored `profile_name`.

## Speech And Artifacts

- Use `generate_speech` when the user wants audible playback now.
- Use `generate_audio_file` when the user wants a saved retained artifact instead of immediate playback.
- Use `generate_batch` when the user wants multiple generated files under one voice profile.
- Pass `text_profile_id` only when the user explicitly wants a stored normalization profile on that request.
- Pass `text_format`, `nested_source_format`, or `source_format` when the input is code, structured output, or other content where automatic detection is likely to misread intent.

## Tracking

- After `generate_speech`, read `speak://requests/{request_id}` or `get_runtime_overview`.
- After retained-file or batch requests, follow the returned job or artifact resource instead of assuming completion.
- Use `list_generation_jobs`, `get_generation_job`, `list_generated_files`, `get_generated_file`, `list_generated_batches`, and `get_generated_batch` to inspect retained outputs.
- Use `expire_generation_job` only when the user explicitly wants one retained generation job removed.
