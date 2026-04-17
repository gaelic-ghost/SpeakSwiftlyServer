---
name: speak-swiftly-launchagent-setup
description: Use when a user wants to set up SpeakSwiftlyServer on their machine as a per-user LaunchAgent, or needs to install, refresh, promote, inspect, validate, troubleshoot, or remove that background service. This skill covers the supported launch-agent CLI workflow, plugin-aware Codex access expectations, required config-file checks, staged-artifact expectations, and end-to-end HTTP plus MCP health verification.
---

# SpeakSwiftly LaunchAgent Setup

Use this skill when the user wants the standalone `SpeakSwiftlyServer` to run as a per-user background service managed by `launchd`.

## Start Here

- Use the supported `SpeakSwiftlyServerTool launch-agent ...` commands instead of hand-editing property lists or calling `launchctl` directly.
- Read the repo operator guidance in [README.md](../../README.md) first, then [LaunchAgent-Workflow.md](../../Sources/SpeakSwiftlyServer/SpeakSwiftlyServer.docc/Articles/LaunchAgent-Workflow.md) when the user needs the full setup model.
- If the user is asking about Codex access to the running service, remember that the installed plugin already handles the Codex-side MCP registration through [`.mcp.json`](../../.mcp.json). The setup work here is about getting the live server healthy at `http://127.0.0.1:7337/mcp`, not about hand-editing Codex config files.
- Phrase the setup outcome in user terms like "set up SpeakSwiftly on this machine," "install the background service," "make the local service reachable from Codex," or "fix the LaunchAgent install," because those are the kinds of requests this skill should trigger on.

## Normal Setup Flow

1. Print the property list first with `xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist`.
2. Confirm the config file the service should use. The standard live-service path is `~/Library/Application Support/SpeakSwiftlyServer/server.yaml` unless the user explicitly wants another file.
3. If the staged live artifact is already the intended executable, run `xcrun swift run SpeakSwiftlyServerTool launch-agent install --config-file /absolute/path/to/server.yaml`.
4. If the user wants the current checkout to become the live service now, run `xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live --config-file /absolute/path/to/server.yaml`.
5. Verify the result with `xcrun swift run SpeakSwiftlyServerTool healthcheck`.

## When To Use Each Command

- `launch-agent print-plist`:
  Use before install work or when the user wants to inspect exactly what will be staged into `~/Library/LaunchAgents`.
- `launch-agent install --config-file ...`:
  Use when the staged release artifact under `.release-artifacts/current` is already the executable the user wants `launchd` to boot.
- `launch-agent promote-live --config-file ...`:
  Use when the intent is "make this checkout become the live service now." This rebuilds and stages the release artifact first, then refreshes the LaunchAgent install.
- `launch-agent status`:
  Use when the user wants to inspect the installed state, label, plist location, or staged executable details.
- `launch-agent uninstall`:
  Use when the user explicitly wants the per-user background service removed.
- `healthcheck`:
  Use after install, promotion, config changes, or troubleshooting. It is the supported end-to-end probe for both HTTP and MCP.

## Validation And Troubleshooting

- Treat `healthcheck` as the primary verification path because it probes `GET /healthz`, reads `GET /runtime/host`, and sends a real MCP `initialize` request to `/mcp`.
- If the HTTP process is healthy but Codex still cannot use the MCP surface, do not jump straight to telling the user to edit Codex config. First check whether the server is actually exposing `/mcp`. The plugin install should already handle the Codex-side connection; the remaining failure is usually that MCP is disabled in the server config or environment. The MCP endpoint exists only when `APP_MCP_ENABLED=true` or the config file enables MCP.
- If the user wants to understand whether the live background service is using the staged artifact or a different executable, rely on `launch-agent status`, install output, and the printed plist rather than inferring from filesystem timestamps alone.
- If the user needs queue, playback, or backend control after the service is already installed, switch to `$speak-swiftly-runtime-operator` instead of stretching this skill into runtime operations.
- If the question is about using the live MCP surface from Codex after setup, switch to `$speak-swiftly-mcp`.
