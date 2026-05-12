# SpeakSwiftlyServer Repo-Wide Security Audit - 2026-05-12

## Summary

This audit reviewed the `SpeakSwiftlyServer` repository at commit `ac0e469ba950` on branch `security/repo-wide-audit` using the `codex-security` repo-wide scan workflow.

The package intentionally exposes unauthenticated local HTTP and MCP surfaces for trusted local apps and agents. The findings below are therefore scoped to local API access unless noted otherwise. Default loopback binding lowers remote risk, but any non-loopback deployment would make the same issues materially more serious.

## Findings

| ID | Severity | Status | Area | Summary |
| --- | --- | --- | --- | --- |
| SS-2026-05-12-01 | Medium | Validated | Voice profiles | `reference_audio_path` can make the service read and transcribe arbitrary readable local audio. |
| SS-2026-05-12-02 | Medium | Validated | Config persistence | Default voice profile names are interpolated into YAML without scalar escaping. |
| SS-2026-05-12-03 | Low | Validated | Voice profiles | `output_path` can export generated profile audio to an arbitrary new filesystem path. |
| SS-2026-05-12-04 | Low | Validated | MCP sessions | MCP `initialize` can create unbounded live sessions. |
| SS-2026-05-12-05 | Low | Validated | MCP subscriptions | MCP resource subscriptions are unbounded and accept arbitrary dynamic URI suffixes. |
| SS-2026-05-12-06 | Low | Validated | Codex hooks | Stop-hook diagnostic logs can persist sensitive message and path previews. |
| SS-2026-05-12-07 | Low | Validated | Retained requests | Any local client can enumerate retained request snapshots and read another client's retained history. |
| SS-2026-05-12-08 | Low | Validated | Host snapshots | Runtime overview/configuration snapshots expose local paths and retained error text to any local client. |
| SS-2026-05-12-09 | Hardening | Conditional | Transport binding | If HTTP or MCP is bound to a non-loopback interface, the unauthenticated local-control model becomes remotely reachable. |

## SS-2026-05-12-01: Voice Clone Audio Path Disclosure

`POST /voices/from-audio` accepts `reference_audio_path` and passes it through to the runtime. The upstream voice-profile creation path opens that file, and when no transcript is supplied it can transcribe the audio before storing source text in the profile model. A local HTTP or MCP client could therefore read the spoken contents of any audio file readable by the service account by creating a clone profile and then reading profile details.

Affected code:

- `Sources/SpeakSwiftlyServer/HTTP/HTTPVoiceRoutes.swift:25`
- `Sources/SpeakSwiftlyServer/Host/SpeakSwiftlyRuntimeAdapter.swift:153`
- `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Generation/VoiceProfileCreation.swift:193`
- `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Generation/VoiceProfileAudioSupport.swift:95`
- `Sources/SpeakSwiftlyServer/Host/ProfileModels.swift:52`

Recommended follow-up:

- Restrict HTTP and MCP clone imports to a server-owned import directory, or make arbitrary local-file imports operator-only through the CLI or embedded API.
- Require an explicit transcript on transport-facing clone requests when the source is a path.
- Add tests proving disallowed absolute paths and parent traversal are rejected.

## SS-2026-05-12-02: Manual YAML Scalar Injection

`ServerConfigPersistence.renderYAML` wraps `defaultVoiceProfileName` in single quotes with direct interpolation. `RuntimeStartupConfiguration` trims the name but does not reject quotes, newlines, or YAML metacharacters before persistence. A crafted default profile name can corrupt or inject persisted YAML keys that take effect on next startup.

Affected code:

- `Sources/SpeakSwiftlyServer/Config/ServerConfigPersistence.swift:28`
- `Sources/SpeakSwiftlyServer/Config/ServerConfigPersistence.swift:116`
- `Sources/SpeakSwiftlyServer/Config/RuntimeStartupConfiguration.swift:24`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Profiles.swift:42`

Recommended follow-up:

- Replace manual YAML rendering with a structured emitter, or centralize YAML scalar escaping for every interpolated value.
- Validate persisted default profile names before saving.
- Add regression tests for names containing quotes, colons, hashes, and newlines.

## SS-2026-05-12-03: Profile Audio Export Path Write

`POST /voices/from-description` accepts `output_path` and passes it through to upstream profile generation. Upstream rejects overwrite, but it can create parent directories and write generated audio to a caller-chosen new path with service-account permissions. This is not arbitrary-content write, but it is still a transport-facing filesystem write primitive.

Affected code:

- `Sources/SpeakSwiftlyServer/HTTP/HTTPVoiceRoutes.swift:12`
- `Sources/SpeakSwiftlyServer/Host/SpeakSwiftlyRuntimeAdapter.swift:141`
- `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Generation/VoiceProfileCreation.swift:144`
- `.build/checkouts/SpeakSwiftly/Sources/SpeakSwiftly/Storage/ProfileStore.swift:846`

Recommended follow-up:

- Remove `output_path` from HTTP and MCP, or confine it to a server-owned export directory.
- Keep no-overwrite behavior and add extension/type validation for generated profile audio exports.

## SS-2026-05-12-04: Unbounded MCP Sessions

Every MCP `initialize` request creates and starts a new `MCPSession`, stores it in an in-memory dictionary, and only removes it on successful client `DELETE` or server stop. There is no session count limit, idle timeout, or oldest-session eviction.

Affected code:

- `Sources/SpeakSwiftlyServer/MCP/MCPSessionRegistry.swift:41`
- `Sources/SpeakSwiftlyServer/MCP/MCPSessionRegistry.swift:71`
- `Sources/SpeakSwiftlyServer/MCP/MCPSessionRegistry.swift:104`
- `Sources/SpeakSwiftlyServer/MCP/MCPSession.swift:28`

Recommended follow-up:

- Add maximum active sessions, idle expiration, and cleanup for failed or abandoned sessions.
- Add tests for over-budget initialization and idle-session pruning.

## SS-2026-05-12-05: Unbounded MCP Subscriptions

`resources/subscribe` inserts every accepted URI into an unbounded per-session set. Dynamic profile and request resource helpers accept arbitrary suffixes after validating the URI shape, so one client can grow subscription memory and notification filtering cost without a practical cap.

Affected code:

- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift:86`
- `Sources/SpeakSwiftlyServer/MCP/MCPSubscriptionBroker.swift:30`
- `Sources/SpeakSwiftlyServer/MCP/MCPSubscriptionBroker.swift:103`
- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift:403`
- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift:414`
- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift:425`

Recommended follow-up:

- Cap subscriptions per session and reject excessive URI lengths.
- Require dynamic resource IDs to exist before accepting subscriptions where the resource family represents stored objects.
- Normalize subscribed URIs before storage.

## SS-2026-05-12-06: Sensitive Stop-Hook Diagnostic Logs

The stop-hook loggers append JSONL entries under the hook data directory. By default they can persist transcript paths, cwd, model/session identifiers, assistant-message previews, and speech failure metadata. Full payload logging is opt-in, but the default previews can still capture sensitive user content.

Affected code:

- `hooks/stop-log.mjs:57`
- `hooks/stop-log.mjs:58`
- `hooks/stop-tts.mjs:117`
- `hooks/stop-tts.mjs:491`

Recommended follow-up:

- Redact common secret patterns before writing stop-hook previews.
- Consider making message previews opt-in diagnostics instead of default log fields.
- Create hook log directories and files with restrictive permissions where Node and platform behavior make that practical.

## SS-2026-05-12-07: Cross-Client Retained Request Disclosure

The host keeps all public jobs in one shared dictionary. Any local HTTP or MCP client can list retained jobs, fetch a retained job by request ID, or subscribe to its SSE stream. Retained completion events can include artifact data, profile paths, text-profile paths, playback state, runtime snapshots, and cancellation details.

Affected code:

- `Sources/SpeakSwiftlyServer/Host/ServerHost.swift:48`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+Requests.swift:131`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RuntimeControls.swift:60`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RequestEvents.swift:7`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RequestEvents.swift:19`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+EventMapping.swift:207`

Recommended follow-up:

- Decide whether trusted-local clients intentionally share retained request history.
- If not, attach a client or session owner to request records and filter list/detail/SSE reads by owner.
- If yes, document the shared-local visibility boundary explicitly in API and MCP guidance.

## SS-2026-05-12-08: Runtime Path And Error Disclosure

The shared host snapshot exposes profile root path, persisted configuration path, persisted configuration errors, environment override state, and recent localized error messages. These are useful operator fields, but any local HTTP or MCP client with overview/configuration access can read them.

Affected code:

- `Sources/SpeakSwiftlyServer/Host/EmbeddedServerSnapshots.swift:261`
- `Sources/SpeakSwiftlyServer/Host/EmbeddedServerSnapshots.swift:276`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+RuntimeLifecycle.swift:181`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+EventMapping.swift:58`
- `Sources/SpeakSwiftlyServer/Host/ServerHost+EventMapping.swift:104`
- `Sources/SpeakSwiftlyServer/HTTP/HTTPRuntimeRoutes.swift:18`
- `Sources/SpeakSwiftlyServer/MCP/MCPResources.swift:100`

Recommended follow-up:

- Decide which path-bearing fields are operator-only diagnostics and which belong in normal agent-readable overview resources.
- Redact or compact paths in transport-facing snapshots when full paths are not required.
- Keep detailed paths available through an explicit diagnostics surface if operators still need them.

## SS-2026-05-12-09: Conditional Non-Loopback Exposure

The current API contract says HTTP and MCP are unauthenticated and intended for localhost or trusted local apps. Defaults bind to loopback, so this is not a normal-deployment vulnerability. If an operator changes the host to a non-loopback interface, however, every control listed in the HTTP and MCP surfaces becomes reachable to the network without authentication.

Recommended follow-up:

- Warn or reject unauthenticated non-loopback binding unless an explicit unsafe flag is set.
- Add startup diagnostics that make the unauthenticated remote-control consequence obvious.
- Keep docs clear that non-loopback mode is outside the default trust model.

## Coverage

Reviewed repo-owned Swift source, HTTP and MCP transports, embedded host snapshots, LaunchAgent CLI code, Codex hook scripts and metadata, maintainer scripts, package manifest dependencies, public API docs, and relevant upstream resolved checkout paths used by profile creation.

Dependency coverage was usage-focused rather than a full software-composition analysis. No separate vulnerability database scan was recorded in this report.

Suppressed candidates:

- MCP tool/resource/prompt handlers did not expose direct command execution or path traversal beyond the shared host methods already covered above.
- Config bind-address and persistence-root controls are operator or embedded-caller configuration under the current trust model.
- LaunchAgent CLI commands use argument arrays rather than shell interpolation and are local-operator surfaces.
- Maintainer release and validation scripts execute repo-owned automation and do not expose a lower-privilege request boundary.
- Completed-job retention has TTL and max-count pruning, so the finding is cross-client visibility rather than unbounded retention.

## Follow-Up Tracking

Addressable items from this report were added to `ROADMAP.md` under `Milestone 21: Repo-Wide Security Audit Follow-Through`.
