# Media

This directory holds public documentation media for `SpeakSwiftlyServer`.

Use it for short preview audio, transcripts, captions, and provenance notes that help users inspect
package behavior without running a local server. Runtime-loaded SwiftPM resources belong under
`Sources/SSSCore/Resources` instead, because SwiftPM target resources must live under the
target that owns them.

## Layout

```text
docs/media/
  speakswiftlyserver-codex-plugin-promo.mp3
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

## Promo Clips

### SpeakSwiftlyServer Codex Plugin Promo

- File: [`speakswiftlyserver-codex-plugin-promo.mp3`](./speakswiftlyserver-codex-plugin-promo.mp3)
- Format: MPEG Layer III audio, 256 kbps, 44.1 kHz, mono
- Purpose: public README preview for the Speak Swiftly Codex plugin
- Provenance: user-authored promo audio provided for this repository
- Consent and license: provided by the repository owner for public documentation use
