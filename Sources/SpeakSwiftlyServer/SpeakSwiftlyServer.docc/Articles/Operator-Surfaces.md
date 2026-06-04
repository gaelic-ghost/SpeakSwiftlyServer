# Operator Surfaces

## Overview

The package exposes one shared host through three operator-oriented surfaces:

- the embedded Swift library surface in this DocC catalog
- the standalone `SpeakSwiftlyServerTool` executable
- the HTTP, MCP, and opt-in LAN audio receiver transports that the standalone server can publish

These surfaces share the same underlying host model, but they answer different ownership questions.

## Surface Roles

### Embedded Library

Use ``EmbeddedServer`` when an app owns the process and wants direct state observation on the main
actor.

Internally, the embedded path now keeps package-owned lifecycle concerns explicit: one outer
service-owned group coordinates host startup and shutdown, optional config watching, optional MCP
readiness and drain, and the wrapped Hummingbird application. App code should treat the
`EmbeddedServer` instance itself as the lifecycle boundary and the UI-facing projection rather than
as a transport owner.

### Command-Line Tool

`SpeakSwiftlyServerTool` is the operator entrypoint for starting the server directly or managing the LaunchAgent property list workflow.

The companion executable walkthrough starts at <doc:Using-The-Command-Line-Tool>.

### HTTP, MCP, And LAN Audio

The HTTP and MCP surfaces are transport adapters around the same host state and runtime operations. They are the right choice when another process, a local service manager, or an external client should own the session.

The server-to-server generated-audio stream route is disabled by default. Enable `app.remoteGeneration.allowRemoteStreamRequests` and provide `app.remoteGeneration.sharedToken` only when this machine should generate speech for another SpeakSwiftlyServer over `/speech/stream`; callers must send that token in `X-SpeakSwiftly-Remote-Generation-Token`. Shared host snapshots expose this as `remote_generation`, including whether stream requests are enabled, whether a shared token is configured, the expected token header name, the active outbound remote-generation request count, and token-safe active stream records. Active stream records include request ID, remote service, remote base URL, profile name, submitted and started timestamps, latest stage, and output destination details. The snapshot intentionally does not expose token values or request text.

The LAN audio receiver is also a transport adapter, but it is intentionally receiver-only in this release. Enable `app.networkAudioReceiver` when this machine should advertise itself over Bonjour, accept generated-audio chunk streams from another SpeakSwiftly host after the shared-token handshake, and play those chunks locally. The transport appears in shared host snapshots as `network_audio_receiver`, including listener state and active inbound stream count. The sender-side `network_audio_receiver_selection` snapshot reports whether the selected receiver is ready for LAN output, whether the local sender token is configured, whether the selected endpoint can be used, and token-safe blocked reason codes. Use `POST /network-audio/selection/smoke-test` to send a short silent stream to the selected ready receiver before running full remote-generation playback.

This DocC catalog intentionally stays library-first. For the transport inventory, request and response payloads, and command reference, use the repository docs:

- [README](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/README.md)
- [API Reference](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/API.md)

## Next Reading

If you are embedding the host in an app, continue with <doc:Embedding-The-Server>.

If you are operating the executable directly, continue with <doc:Using-The-Command-Line-Tool>.
