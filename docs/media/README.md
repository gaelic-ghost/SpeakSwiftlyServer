# Media

This directory holds public documentation media for `SpeakSwiftlyServer`.

Use it for short preview audio, transcripts, captions, and provenance notes that help users inspect
package behavior without running a local server. Runtime-loaded SwiftPM resources belong under
`Sources/SpeakSwiftlyServer/Resources` instead, because SwiftPM target resources must live under the
target that owns them.

## Layout

```text
docs/media/
  default-voices/
    README.md
    swift-signal.wav
    swift-anchor.wav
```

Each checked-in voice sample should include:

- a matching transcript
- the voice profile name it represents
- whether it was generated, cloned, or otherwise sourced
- a consent and license note
- the commit or release used to generate it when available

Do not place Gale's personal default voices here unless that is explicitly approved for public repository use.
