---
name: speak-swiftly-voice-workflows
description: Use when a user wants SpeakSwiftly voice-profile or speech-generation help, including voice creation from text or audio over HTTP, profile listing over slim MCP or HTTP, immediate spoken playback over MCP, retained audio artifacts over HTTP, retained batch jobs over HTTP, and generation artifact tracking over HTTP.
---

# SpeakSwiftly Voice Workflows

Use this skill for voice selection, voice creation, and speech-generation work. The local `speak_swiftly` MCP surface owns live speech playback and guidance; HTTP owns voice-profile mutation and retained generation.

## Start Here

- Read `speak-swiftly://voices` or `GET /voices` before creating, renaming, rerolling, deleting, or choosing a profile.
- Use `GET /voices` for detailed HTTP workflows; the slim MCP surface no longer exposes one-profile detail resources.
- If the user wants help designing a voice rather than executing immediately, prefer the `draft_profile_voice_description`, `draft_profile_source_text`, and `draft_voice_design_instruction` prompts plus the guide flow documented in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift).

## Creation And Editing

- Use `POST /voices/from-description` when the user has target sound qualities and source text.
- Use `POST /voices/from-audio` when the user has reference audio. Provide `transcript` whenever the spoken words are already known.
- Use `PUT /voices/{profile_name}/name` for a pure rename.
- Use `POST /voices/{profile_name}/reroll` when the user wants the same stored name rebuilt from its original inputs.
- Use `DELETE /voices/{profile_name}` only after confirming the exact stored `profile_name`.
- The package-owned built-in defaults are `swift-signal` and `swift-anchor` when installed by upstream `SpeakSwiftly` bundled system-profile resources. Treat them as system voices, not user-authored example names. Normal users should list and select them.
- When a user wants broad-appeal user-authored example profiles, suggest names and voice directions such as:
  - `swift-lumen`: luminous, clean, gentle, and polished
  - `swift-arc`: compact, focused, modern, and precise
  - `swift-melody`: warm, expressive, friendly, and persona-ready
  - `swift-foundry`: grounded, maker-like, textured, and steady

## Qwen Voice-Design Prompting

- Treat Qwen3-TTS VoiceDesign prompts as standalone voice designs. The model receives the current spoken text plus the current natural-language instruction, not an audio memory of a previous generated profile.
- When a user wants a change to an existing synthetic voice, rewrite the full intended voice description with both the preserved traits and the requested change. Avoid relative instructions like "same as before, but warmer" or "this voice with less edge"; they leave the model without the original target voice.
- Make instructions concrete across timbre, age or gender presentation when explicitly requested, pace, pitch range, affect, accent or dialect only when requested, breath/texture, and performance style. Prefer stable acoustic language over brand names, celebrity names, or vague vibe labels.
- Keep source text aligned with the desired voice. A reusable profile source passage should exercise the cadence, emotion, and phonetic range the user wants, because Qwen's own design-then-clone workflow starts by creating a short reference clip from a matching text and instruction pair.
- For consistency across many lines, create or reroll a profile from a strong self-contained design first, then reuse that stored profile for generation. Do not try to get long-term voice identity by sending incremental VoiceDesign instructions line by line.

## Speech And Artifacts

- Use `generate_speech` when the user wants audible playback now.
- Use `POST /speech/files` when the user wants a saved retained artifact instead of immediate playback.
- Use `POST /speech/batches` when the user wants multiple retained artifacts generated under one voice profile.
- Pass `text_profile_id` only when the user explicitly wants a stored normalization profile on that request.
- HTTP and MCP speech requests get transport provenance in `request_context` by default; pass `cwd`, `repo_root`, or explicit `request_context` only when path or caller metadata needs to be more specific. Do not pass a separate `source_format`; SpeakSwiftly now lets TextForSpeech infer text and source structure from request text plus path context.
- Pass `qwen_pre_model_text_chunking` only when the user explicitly wants Qwen live playback to chunk before model generation; omitted requests keep the runtime's normal single-pass live path.

## Tracking

- After `generate_speech`, read `speak-swiftly://requests/{request_id}` or `speak-swiftly://overview`.
- After retained-file or batch requests, follow `GET /requests/{request_id}` first, then inspect `GET /generation/jobs`, `GET /generation/jobs/{job_id}`, `GET /generation/artifacts`, or `GET /generation/artifacts/{artifact_id}`.
- Use generation jobs and artifacts to inspect retained outputs; the older generated-file and generated-batch read tools are not carried forward.
- Use `DELETE /generation/jobs/{job_id}` only when the user explicitly wants one retained generation job removed.
