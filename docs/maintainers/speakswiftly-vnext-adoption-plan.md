# SpeakSwiftly v12 Adoption Record

## Purpose

This note preserves the completed `SpeakSwiftlyServer` adoption path for `SpeakSwiftly`
`v12.0.0`. It is a historical decision record, not an active migration plan.

## Current Outcome

Completed on `2026-07-19`: the server now depends on `SpeakSwiftly` from `v12.0.0`,
consumes normalization and summarization exclusively through the public `SpeakSwiftly`
product, and has no standalone `TextForSpeech` package or product dependency.

## Historical v11 Planning Snapshot

The remaining sections preserve the original v11 planning details as historical decision
context. Their dependency versions, pending steps, and future-tense instructions are not
current maintainer guidance.

Status recorded on `2026-05-31`: `SpeakSwiftlyServer` had adopted the GitHub prerelease
`SpeakSwiftly` `v11.0.0-alpha.1` and `TextForSpeech` `v0.23.0` through the public
`SpeakSwiftly` product. HTTP and MCP continued to expose local live playback for speech requests;
HTTP response streaming and LAN output remained future contract decisions.

The goal is to prepare the server for the new runtime capabilities without reaching into upstream
implementation targets. `SpeakSwiftlyServer` should integrate through the public `SpeakSwiftly`
library surface. If that public surface is not sufficient, open focused issues or follow-up changes
in `gaelic-ghost/SpeakSwiftly` instead of importing upstream internal targets here.

## Integration Rule

- Import only the public `SpeakSwiftly` product from this package.
- Do not add imports for upstream implementation modules such as `SpeakSwiftlyCore`,
  `SpeakSwiftlyPlayback`, `SpeakSwiftlyHTTPAudioOutput`, or `SpeakSwiftlyNetworkAudioOutput`.
- Keep `SSSCore` as the temporary server-core target in this package, but do not make it a second
  owner of playback, generation, audio-output routing, or profile semantics that belong upstream.
- Keep `SSSHTTP` and `SSSMCP` responsible only for transport-local request and response shaping.
- If a server feature needs a capability that is only present in an upstream implementation target,
  treat that as an upstream API gap and file an issue or patch against `SpeakSwiftly`.

## Expected Upstream Changes

The local upstream worktree pointed toward these adoption-impacting changes:

- Qwen-only backend identifiers, with Marvis and Chatterbox backend values removed.
- `TextForSpeech.RequestPurpose.audioStream` removed upstream; speech output remains request purpose
  `speech`, with file generation using `audioFile`.
- Expanded `SpeakSwiftly.Configuration` values, including Qwen conditioning strategy and default
  audio-output destination.
- `generate.speech(..., output:)` as the public request-scoped audio-output entrypoint.
- Public audio-output destination types for local playback, HTTP response streaming, and network
  streaming or service discovery.
- Split upstream implementation targets for generated audio, playback, HTTP audio output, and network
  audio output, exposed through the public `SpeakSwiftly` product for consumers.

At that time, the package was required to wait for a GitHub-visible upstream version, tag, or branch
before changing committed dependency declarations. The adopted historical integration point was the
GitHub prerelease tag `v11.0.0-alpha.1`.

## Historical Adoption Slices

### Slice 1: Dependency Baseline

The original slice updated `Package.swift` and `Package.resolved` to the published upstream
`SpeakSwiftly` version and matching `TextForSpeech` floor. The completed v12 migration subsequently
removed the standalone dependency entirely.

Run:

```bash
xcrun swift build
```

### Slice 2: Public API Compile Alignment

Compile against the public `SpeakSwiftly` product only. Update server adapter code where the public
runtime API changed, including configuration construction and live speech submission.

Prefer deleting server-local translation paths when upstream now expresses the same concept directly.
If the compile fix appears to require importing an upstream internal module, stop and open an upstream
issue or patch instead.

Run:

```bash
xcrun swift build
```

### Slice 3: Contract Cleanup

Remove stale server contract assumptions that no longer match upstream:

- Remove Marvis and Chatterbox backend examples from active API docs and tests.
- Decide whether caller-provided `request_context.reqPurpose` should continue to be ignored or should
  be rejected when it conflicts with the route-owned request purpose.
- Keep live speech defaulting to upstream local playback until this package intentionally designs an
  HTTP or LAN streaming server contract.
- Do not introduce Bonjour or LAN behavior in this adoption pass unless Gale explicitly widens the
  server contract.

Run:

```bash
xcrun swift build
xcrun swift test
```

### Slice 4: Transport Exposure Decision

Review the new public audio-output API and decide which server surfaces should expose it:

- Embedded Swift API can usually mirror public Swift types sooner because app callers already compile
  against Swift.
- HTTP and MCP need a stable wire contract, so audio-output fields should be added only when the
  request and response semantics are clear.
- If HTTP response streaming or LAN output needs upstream behavior that is not public through
  `SpeakSwiftly`, open an upstream issue instead of binding to implementation modules.

Run the narrowest route or catalog tests that cover any changed surface.

### Slice 5: Documentation And Full Gate

Update the active docs together:

- `API.md`
- `docs/maintainers/speakswiftly-api-coverage-matrix.md`
- `docs/maintainers/source-layout.md` if ownership boundaries change
- release notes for the eventual server version

Run:

```bash
sh scripts/repo-maintenance/validate-all.sh
```

Do not run live transport end-to-end tests independently unless the live-service resident-model unload
preflight is part of the command path.

## Upstream Issue Triggers

Open an upstream `SpeakSwiftly` issue or patch when:

- a needed type is public only through an implementation target, not the `SpeakSwiftly` product
- audio-output routing cannot be selected per request through the public API
- public configuration cannot represent a startup option that the server already needs to persist
- public snapshots no longer expose state the server needs for HTTP, MCP, or embedded status
- backend identifier migration leaves no public way to normalize or validate user input
- request-context or request-purpose behavior cannot be expressed without duplicating upstream logic

## Non-Goals

- Do not import upstream internal modules from this server package.
- Do not add `SSSBonjour`, `SSSDiscovery`, or LAN-specific server behavior in the compile-alignment
  pass.
- Do not widen HTTP, MCP, or embedded contracts just because upstream added public capability.
- Do not commit machine-local dependency paths for testing against sibling worktrees.
- Do not duplicate upstream playback, generated-audio, or network-output ownership inside `SSSCore`.
