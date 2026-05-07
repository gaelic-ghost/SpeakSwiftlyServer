# Default Voices And Media Options

## Purpose

This note records the package-owned default voice direction and repository-hosted audio sample
policy.

The goal is to give new `SpeakSwiftlyServer` users a couple of usable baseline voices without mixing
those package defaults with Gale's personal saved voice profiles. The related docs goal is to keep
short preview audio in `docs/media/` so the public repository can show what the defaults sound like
without requiring a local runtime first.

## Current Shape

- `SpeakSwiftly` owns stored voice-profile creation, system-profile resource installation, profile
  manifests, canonical reference audio, and reroll behavior.
- `SpeakSwiftlyServer` owns the local HTTP, MCP, embedded, LaunchAgent, and operator-facing default
  profile selection surfaces.
- `SpeakSwiftlyServer` can ship server-owned generated system-profile resources under
  `Sources/SpeakSwiftlyServer/Resources/SystemProfiles/`.
- The live user profile root stays outside the package and is selected through the runtime profile-root path.
- `docs/media/` is documentation content, not a SwiftPM module resource.

SwiftPM resources are scoped to a target, and resources that should be available through
`Bundle.module` must live under the owning target directory and be declared on that target. The
upstream `SpeakSwiftly` package owns the resource shape and seeding behavior. This server can bundle
its own generated system-profile resources in its target resources, while public preview audio
belongs under this repository's `docs/media/`.

Reference: [Swift Package Manager PackageDescription resources][swiftpm-resources].

## Settled Initial Direction

The first two package-owned default voices are:

- `swift-signal`: a bright, clear, responsive voice with crisp articulation, quick but controlled
  pacing, and an accessible technical-assistant tone.
- `swift-anchor`: a grounded, steady, warm voice with strong articulation, calm pacing, and a
  reassuring technical-narrator tone.

The package treats these as built-in system profiles, not Gale's personal default profiles. During
runtime startup, `SpeakSwiftly` seeds configured system-profile resources into the user's profile
store. `SpeakSwiftlyServer` passes its bundled `SystemProfiles` resource root through the
`SpeakSwiftly.Configuration` it uses for liftoff. After the runtime first reports resident-model
readiness, the server refreshes its profile cache and exposes installed built-ins as normal
selectable voice names.

If an existing user profile already occupies a preferred built-in name, `SpeakSwiftly` decides
whether to skip, refresh, or otherwise handle the conflict. The server should report the installed
profile cache truth instead of re-implementing package seed conflict policy.

The startup installer should not change the active default voice unless the operator explicitly asks
for that behavior.

## Built-In Profile Identity

The user-facing profile name is not enough to support future refresh behavior. Each built-in system
profile needs stable package identity metadata from the beginning:

- seed id, such as `swift.signal` or `swift.anchor`
- seed version
- intended profile name
- fallback profile name when the upstream resource workflow supports one
- author, where normal creation flows produce `.user` and package-owned defaults use `.system`
- created or installed timestamp
- voice description
- source text or transcript
- source kind
- sample media path when a docs preview exists

The author field belongs in the underlying voice-profile type owned by `SpeakSwiftly`. User-created
profiles should default to `.user`. Package-owned defaults should be `.system`. A `.system` profile
should be immutable to ordinary user mutation wherever the runtime can enforce that cleanly.

The server should not add extra public HTTP, MCP, or embedded fields unless application consumers
need them to make good decisions. Ordinary user-facing profile reads should expose enough metadata to
list and choose a built-in, such as author and seed identity, while redacting system seed source text
and voice-design prompts. Contributor-facing upstream docs can describe or expose the resource
workflow and immutability policy without forcing those details into every end-user response payload.

## System Voice Mutation Policy

System-authored built-ins should not be renamed, deleted, or rerolled in place by ordinary user
flows. If a user asks to reroll a system voice, the runtime should create a user-owned copy instead:

- `swift-signal` reroll creates or targets a `.user` copy with a clear conflict-safe name when the
  system profile owns `swift-signal`.
- the original `.system` profile remains intact.

That behavior keeps built-ins refreshable while still letting users personalize them without losing
the package-owned baseline.

## Option 1: Seed Profiles From Package Resources

Add package-owned seed profile definitions under package resources, then add an explicit install or
seed operation that copies missing defaults into the active runtime profile root.

This is the most durable building-block change. The package owns a small catalog of public defaults,
and the runtime profile root still owns the user's mutable installed copies. Personal profiles stay
separate because package seeds only install named defaults when the active profile root is missing
them or when the operator explicitly refreshes package defaults.

Near-term work this unlocks:

- `SpeakSwiftlyServerTool` can offer an operator command such as `voice-defaults install`.
- the LaunchAgent setup path can optionally seed public defaults after install without touching
  personal profiles.
- HTTP, MCP, and embedded consumers can list package defaults separately from user-created profiles
  if we expose that surface later.
- docs can link the package default names directly to preview samples in `docs/media/`.

Main design choice:

- keep the resource as a complete upstream stored-profile directory that gets validated and copied
  into the runtime profile root.

This is the current server path, backed by upstream `SpeakSwiftly` resource-root seeding. The server
bundles generated profile resources; `SpeakSwiftly` validates and installs them into the writable
runtime profile store.

## Option 2: Keep Defaults As Documentation Samples First

Add short audio samples and transcripts under `docs/media/`, document the intended profile names,
and leave runtime installation manual for now.

This is a conscious stopgap. It gives us public examples and lets us compare voice direction before
changing runtime behavior, but it does not make the package friendlier on first run.

Near-term work this unlocks:

- README and API docs can demonstrate the intended voice palette.
- reviewers can listen to candidate voices without installing anything.
- the branch can settle naming, licensing, transcript text, and accessibility captions before code changes.

Main limitation:

- users still have to create or import profiles themselves, so the package does not actually ship
  operational defaults yet.

## Option 3: Move Built-In Defaults Down To SpeakSwiftly

Teach the `SpeakSwiftly` package to expose built-in voice seeds directly, then let
`SpeakSwiftlyServer` surface them through existing HTTP, MCP, embedded, and operator commands.

This is the current upstream architecture for the resource workflow. Non-server consumers can bundle
their own generated system profiles without depending on server-specific resources. This server still
owns its own default voice resource payload when it wants server-specific built-ins.

Practical consequence:

- `SpeakSwiftlyServer` becomes a consumer of upstream system-profile resource seeding rather than
  the owner of profile-store installation behavior.
- the release order changes because `SpeakSwiftly` must tag the bundled profile workflow before this
  server can depend on it.

## Media Layout

Use `docs/media/` for public preview assets:

```text
docs/media/
  README.md
  default-voices/
    README.md
    swift-signal.wav
    swift-anchor.wav
```

Recommended companion metadata for each sample:

- profile name
- transcript
- voice description
- source kind: generated design, imported clone, or other
- generation command or request ID when available
- license and consent/provenance note
- date generated
- package version or commit used to generate it

Keep sample files short. A public docs preview only needs enough speech to identify tone,
pronunciation, pacing, and noise floor.

## Current Follow-Through

1. Add upstream `SpeakSwiftly` support for profile author metadata, system immutability, and
   reroll-as-user-copy behavior. Done in `SpeakSwiftly` `v4.2.0`.
2. Add upstream `SpeakSwiftly` command-plugin support for creating system-profile resources into
   bundled consumer package resources. Done in `SpeakSwiftly` `v7.2.5`; this server should invoke
   it with `xcrun swift package plugin --allow-writing-to-package-directory
   upsert-system-voice-profile --target SpeakSwiftlyServer ...`.
3. Let `SpeakSwiftly` seed bundled system profiles during runtime startup, then let
   `SpeakSwiftlyServer` refresh and expose the installed profile cache. Done in the server after
   adopting `SpeakSwiftly` `v7.2.5`.
4. Generate short preview audio for each installed candidate and place it under
   `docs/media/default-voices/`. Done for `swift-signal.wav` and `swift-anchor.wav`.
5. Add transcript and provenance notes beside the samples. Done in
   `docs/media/default-voices/README.md`.
6. Keep system profile authorship metadata visible in installed profile summaries while leaving
   system-profile resource authoring to the upstream `SpeakSwiftly` command plugin.
7. Decide whether this server needs an explicit operator refresh command beyond upstream startup
   seeding.
8. Add focused tests for startup profile-cache refresh, default/user profile separation, and
   system-profile mutation behavior.

The first implementation should not silently mutate existing user profiles. The safe behavior is to
install package defaults only when missing, emit a clear message for every skipped existing profile,
and require an explicit replace or reroll command for any destructive refresh.

[swiftpm-resources]: https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#Resource
