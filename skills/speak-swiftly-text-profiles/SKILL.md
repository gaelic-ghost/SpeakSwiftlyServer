---
name: speak-swiftly-text-profiles
description: Use when a user wants to inspect or change SpeakSwiftly text normalization through the MCP surface, including built-in style changes, active or stored text profiles, replacement authoring, persistence reload or save operations, and effective-profile verification before speech generation.
---

# SpeakSwiftly Text Profiles

Use this skill for text-normalization work on the local `speak_swiftly` MCP surface.

## Orientation

- Start with `get_text_normalizer_snapshot` or `speak://text-profiles` for any broad question.
- Use `get_text_profile_style` or `speak://text-profiles/style` when the user is really asking about the built-in normalization mode.
- Use `speak://text-profiles/effective/{profile_id}` before speech generation when the user wants to verify what will actually be applied after profile merging.

## Mutation Workflow

- Use `set_text_profile_style` only when the user is intentionally changing the built-in balanced, compact, or explicit mode.
- Use `create_text_profile` for a new stored reusable profile with a simple replacement list.
- Use `rename_text_profile` when the user wants to change the stored display name without recreating the profile.
- Use `set_active_text_profile` when the user wants one stored profile to become the default active custom profile.
- Use `delete_text_profile` only after confirming the exact stored `profile_id`.
- Use `factory_reset_text_profiles` when the user wants to clear the stored catalog back to the default profile set.
- Use `reset_text_profile` when the user wants one stored profile cleared back to its default replacement set without deleting it.

## Replacement Editing

- Use `add_text_replacement`, `replace_text_replacement`, and `remove_text_replacement` for targeted rule edits.
- Use the `draft_text_profile` and `draft_text_replacement` prompts when the user is still designing the normalization policy instead of applying a settled edit immediately.
- Prefer `whole_token` for identifiers and acronyms, and `exact_phrase` for multi-word substitutions.
- Be deliberate about whether a rule should run before or after built-in normalization.
- Restrict `formats` when the user only wants the rule to affect source code, CLI output, or another narrow content kind.

## Persistence

- Use `save_text_profiles` when the user wants an explicit persistence checkpoint.
- Use `load_text_profiles` when another process changed the underlying profile store and the runtime should refresh from disk.
- The best repo-local authoring guidance for these flows lives in the text-profile guide embedded in [MCPResources.swift](../../Sources/SpeakSwiftlyServer/MCP/MCPResources.swift).
