# LaunchAgent Workflow

## Overview

Use the LaunchAgent workflow when the standalone server should run as a per-user background service managed by `launchd`.

In this package, that workflow is intentionally explicit:

1. render the property list you are about to install
2. install the default staged artifact from the current checkout, or intentionally pin the install to a caller-provided executable
3. inspect status or remove it later through the same executable surface
4. verify the live HTTP and MCP transports through one repo-owned health-check command

This article covers the shape of that workflow. It does not replace the repository operator docs, which remain the source of truth for the full command inventory and release-process details.

## Render The Property List First

Start by printing the property list:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist
```

That gives you the exact LaunchAgent payload the package currently wants to stage, including:

- the label
- the `ProgramArguments` path and `serve` invocation
- the working directory
- the `--config-file` path for the canonical Application Support config
- the `--profile-root` path for runtime-owned profile storage
- the stdout and stderr log files

Those paths are passed as explicit server bootstrap inputs. The config file stores server, transport, and runtime startup choices; the profile root points generated profiles and artifacts at the LaunchAgent-owned runtime state tree.

## Install Or Refresh The Background Service

Once the property list looks right, install it. If no config file is supplied, the install path uses
`~/Library/Application Support/SpeakSwiftlyServer/server.yaml` and seeds that file from the bundled
default config when it is missing:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install
```

If you pass `--config-file`, custom paths must already exist. The default Application Support path is
the only path that install and refresh flows seed automatically.

This package's LaunchAgent path is designed around the staged release artifact, not around whichever debug binary happened to run the command. That keeps the installed service pointed at the package's maintained release surface instead of at a transient local build product.

On the default staged executable path, `install` builds and stages the current checkout before it writes and bootstraps the LaunchAgent. Explicit `--tool-executable-path` installs are different: they stay pinned to the executable path the caller provided and do not overwrite it.

Use the explicit promotion command when an operator or release script wants to name the build-and-stage operation directly:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent promote-live \
  --config-file ./server.yaml
```

That command rebuilds the release executable, stages the executable and sibling `SpeakSwiftly` metallib into `.release-artifacts/current`, refreshes the staged executable's ad-hoc code signature explicitly, and then reruns the LaunchAgent install flow without staging a second time.

## Inspect Or Remove The Installed Service

Use the same executable to check the installed state or remove it:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent status
xcrun swift run SpeakSwiftlyServerTool launch-agent uninstall
```

`uninstall` now waits for `launchctl` to stop reporting the job as loaded before it returns. That
keeps a plain remove flow aligned with the install and promote-live refresh flows, which already
wait for launchd teardown before they try to bootstrap the next job incarnation.
It also removes the staged LaunchAgent config alias copy from the managed install layout, so the
remove flow now clears legacy launch-agent-owned config shims instead of leaving stale alias state
behind after the job is gone.

`status` now reports an explicit `load_state` field. A normal absent job shows `load_state: not_loaded`.
If `launchctl print` fails for some other reason, the command now surfaces that failure directly
instead of flattening it into `loaded: no`.

For one explicit live-service verification pass, run:

```bash
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

That command probes the HTTP health route, reads the shared runtime host snapshot, and sends a real MCP `initialize` request to the live `/mcp` endpoint so the result distinguishes "the process is up" from "both transports are actually healthy."

Treat those commands as the stable maintenance surface for the per-user service. If the install layout or staged release artifact path changes in the package, those commands should keep reflecting the package's current contract without requiring operators to re-derive launchd details by hand.

## Related Reading

- Continue with <doc:Using-The-Command-Line-Tool> if you need the broader role of the executable.
- Use the repository docs for the full command reference and the transport-level operator inventory.
