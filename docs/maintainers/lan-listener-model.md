# LAN Listener Model

`SpeakSwiftlyServer` should expose local and LAN HTTP access as separate listener modes instead of overloading one `host` and `port` setting.

## Decision

- Keep the localhost listener enabled by default on a stable port.
- Keep the LAN listener disabled by default.
- When enabled, bind the LAN listener to all interfaces and use port `0` so the OS chooses an available port.
- Advertise the LAN listener with Bonjour so callers discover the actual endpoint instead of relying on a fixed port.
- Require explicit remote-generation and LAN-audio tokens for sensitive LAN workflows.
- Keep runtime enable/disable controls independent for localhost and LAN listeners, with active-request behavior documented before those controls ship.

## Rationale

Local tools need a predictable address such as `127.0.0.1:7337`. Codex hooks, local MCP clients, and same-machine apps should not need Bonjour or a dynamic port.

Other Macs on the LAN should not need to know a port. Bonjour is the right discovery mechanism for a server that moves between Wi-Fi, Ethernet, random ports, and machine names. The LAN listener can bind to `0.0.0.0:0`, then advertise the chosen endpoint.

A single `host: 0.0.0.0` HTTP setting works for testing, but it exposes the whole HTTP surface wherever the local listener would have been enough. Keeping localhost and LAN listeners separate makes LAN exposure intentional and easier to explain.

## Implementation Shape

The startup split should come first:

- `app.listeners.localhost.enabled`
- `app.listeners.localhost.host`
- `app.listeners.localhost.port`
- `app.listeners.lan.enabled`
- `app.listeners.lan.host`
- `app.listeners.lan.port`
- `app.listeners.lan.advertiseBonjour`
- `app.listeners.lan.serviceName`

The current `app.http` keys can remain as the localhost listener source until the config shape fully migrates. New LAN listener keys should not make existing localhost installs LAN-reachable by default.

Runtime toggles need a listener owner that can start and stop Hummingbird listener services after process startup. Do not fake this by writing config and telling operators to restart. The runtime control should either bind or close the listener in the current process, or return a clear unsupported-operation response until the listener owner exists.

## Preflight

LAN enablement should include an operator-facing preflight that:

- starts or verifies the LAN listener;
- advertises Bonjour;
- triggers macOS Local Network permission when possible;
- reports whether Bonjour discovery can see the service;
- sends a token-safe smoke request from the caller side;
- reports the selected service name, advertised port, bind host, and any Local Network privacy block without exposing tokens.

## Current Live Lesson

The Mac mini to MacBook workflow failed in three distinct ways during the first live setup:

- Local Network permission prompts on the mini were hidden behind screen sharing and made Network.framework report an unhelpful network failure.
- The mini HTTP listener was bound to `127.0.0.1`, so the MacBook could not call `/speech/stream`.
- The caller requested a voice profile that existed on the MacBook but not on the mini.

The split listener setup should catch the first two before a real generation request starts. Profile alignment remains a remote-generation workflow concern.
