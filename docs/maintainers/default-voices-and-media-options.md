# Default Voices And Media Options

## Purpose

This note frames the branch discussion for package-owned default voices and repository-hosted audio
samples.

The goal is to give new `SpeakSwiftlyServer` users a couple of usable baseline voices without mixing
those package defaults with Gale's personal saved voice profiles. The related docs goal is to keep
short preview audio in `docs/media/` so the public repository can show what the defaults sound like
without requiring a local runtime first.

## Current Shape

- `SpeakSwiftly` owns stored voice-profile creation, profile manifests, canonical reference audio,
  and reroll behavior.
- `SpeakSwiftlyServer` owns the local HTTP, MCP, embedded, LaunchAgent, and operator-facing default
  profile selection surfaces.
- `Package.swift` already processes `Sources/SpeakSwiftlyServer/Resources` into the
  `SpeakSwiftlyServer` target bundle.
- The live user profile root stays outside the package and is selected through the runtime profile-root path.
- `docs/media/` is documentation content, not a SwiftPM module resource.

SwiftPM resources are scoped to a target, and resources that should be available through
`Bundle.module` must live under the owning target directory and be declared on that target. The
package manifest already uses that supported shape with `.process("Resources")`, so package-owned
seed metadata belongs under `Sources/SpeakSwiftlyServer/Resources`, while public preview audio
belongs under `docs/media/`.

Reference: [Swift Package Manager PackageDescription resources][swiftpm-resources].

## Settled Initial Direction

The first two package-owned default voices are:

- `swift-signal`: a bright, clear, responsive voice with crisp articulation, quick but controlled
  pacing, and an accessible technical-assistant tone.
- `swift-anchor`: a grounded, steady, warm voice with strong articulation, calm pacing, and a
  reassuring technical-narrator tone.

The package treats these as built-in seed profiles, not Gale's personal default profiles. When the
runtime first reports resident-model readiness, the server installs missing seeds from package-owned
metadata into the user's profile store, then exposes them as normal selectable voice names.

If an existing user profile already occupies a preferred built-in name, startup should try a
`-builtin` fallback for the package seed. For example, if `swift-signal` already exists and is not
recognized as the same package seed, install the package voice as `swift-signal-builtin`. If both
names are occupied, skip that seed and print a clear message that names both occupied profile names.

The startup installer should not change the active default voice unless the operator explicitly asks
for that behavior.

## Built-In Profile Identity

The user-facing profile name is not enough to support future refresh behavior. Each built-in seed
needs stable package identity metadata from the beginning:

- seed id, such as `swift.signal` or `swift.anchor`
- seed version
- intended profile name
- fallback profile name
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
need them to make good decisions. Contributor-facing docs can describe the seed catalog and
immutability policy without forcing those details into every end-user response payload.

## System Voice Mutation Policy

System-authored built-ins should not be renamed, deleted, or rerolled in place by ordinary user
flows. If a user asks to reroll a system voice, the runtime should create a user-owned copy instead:

- `swift-signal` reroll creates or targets a `.user` copy named `swift-signal` when the installed
  system profile had to use `swift-signal-builtin`.
- `swift-signal` reroll creates or targets a `.user` copy with a clear conflict-safe name when the
  system profile already owns `swift-signal`.
- the original `.system` profile remains intact.

That behavior keeps built-ins refreshable while still letting users personalize them without losing
the package-owned baseline.

## Option 1: Seed Profiles From Package Resources

Add package-owned seed profile definitions under
`Sources/SpeakSwiftlyServer/Resources/DefaultVoiceProfiles/`, then add an explicit install or seed
operation that copies missing defaults into the active runtime profile root.

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

- decide whether the resource is a compact server-owned seed manifest that calls the normal
  `SpeakSwiftly` create/import APIs, or a complete stored-profile directory that gets validated and
  copied into the runtime profile root.

I would start with a compact seed manifest plus generated preview media, then add stored-profile
import support only if the normal runtime creation path is too slow or too nondeterministic for
first-run setup.

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

This is a broader architecture change. It may be right if non-server consumers such as app
embeddings should get the same defaults without depending on server-specific resources. It also
moves the default-voice catalog closer to the profile store format and generation APIs.

Practical consequence:

- `SpeakSwiftlyServer` becomes a consumer of upstream package defaults rather than the owner of the seed catalog.
- the release order changes because `SpeakSwiftly` must tag the default catalog before this server can depend on it.

I would only choose this first if SayBar or another direct `SpeakSwiftly` consumer needs the same defaults immediately.

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

## Suggested First Pass

1. Add upstream `SpeakSwiftly` support for profile author metadata, system immutability, and
   reroll-as-user-copy behavior.
2. Add a server-owned seed manifest under `Sources/SpeakSwiftlyServer/Resources/DefaultVoiceProfiles/`. Done.
3. Install `swift-signal` and `swift-anchor` from the seed catalog with `-builtin` fallback behavior. Done at startup after the runtime first reports resident-model readiness.
4. Generate short preview audio for each installed candidate and place it under
   `docs/media/default-voices/`.
5. Add transcript and provenance notes beside the samples.
6. Add an explicit operator install command that copies or creates missing package defaults in the
   active runtime profile root.
7. Add focused tests for seed discovery, no-overwrite behavior, default/user profile separation,
   and system-profile mutation behavior.

The first implementation should not silently mutate existing user profiles. The safe behavior is to
install package defaults only when missing, emit a clear message for every skipped existing profile,
and require an explicit replace or reroll command for any destructive refresh.

[swiftpm-resources]: https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#Resource
