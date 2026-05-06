# Using The Command-Line Tool

## Overview

Use the standalone `SpeakSwiftlyServerTool` executable when the server should be owned by an operator workflow instead of by an app process.

This is the right lane when you need to:

- start the shared host directly from a terminal
- inspect the command surface before installing anything
- render or manage the LaunchAgent property list

Stay in the library-first docs when an app owns the process through ``EmbeddedServer``. Switch to this article when the executable itself becomes the thing you are operating.

## Start With The Help Surface

The shortest safe operator entrypoint is the tool's help command:

```bash
xcrun swift run SpeakSwiftlyServerTool help
```

That output shows the two top-level roles the executable currently serves:

- `serve` starts the shared host in the foreground
- `launch-agent` renders, installs, promotes, inspects, or removes the per-user LaunchAgent property list

Running the executable without arguments defaults to `serve`, but the help output is the clearer first stop when you are orienting yourself or checking what a staged release currently exposes.

## Know The Two Execution Modes

### Foreground Server

Use the foreground entrypoint when you want the process attached to the current shell:

```bash
xcrun swift run SpeakSwiftlyServerTool serve
```

This is the simplest path for local operator checks, debugging, and temporary runs where you do not want launchd to own the process lifecycle. The foreground executable uses the server-owned Application Support config by default, seeding it from the bundled package resource when needed.

If the foreground run should own a specific persisted config and runtime profile root, pass both paths:

```bash
xcrun swift run SpeakSwiftlyServerTool serve \
  --config-file ./config/server.yaml \
  --profile-root ./runtime/profiles
```

Those flags are explicit inputs to the server bootstrap path. The config file stores server, transport, and runtime startup choices; the profile root points generated profiles and artifacts at one explicit runtime state tree.

### LaunchAgent Maintenance

Use the `launch-agent` subcommands when the server should become a user-owned background service:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent print-plist
```

That subcommand renders the property list the package would install, including the staged executable path, working directory, `serve --default-profile launch-agent --config-file ... --profile-root ...` invocation, and stdout and stderr log paths. The LaunchAgent-owned persisted config defaults to `127.0.0.1:7337`; use an explicit config file for foreground runs that should avoid the shared installed-service port.

For the install, promotion, status, and uninstall flow, continue with <doc:LaunchAgent-Workflow>.

## Know When To Leave DocC

This companion article is intentionally small. It explains where the executable fits, not every transport payload or maintenance edge case.

For the full operator contract:

- use <doc:Operator-Surfaces> when you need the relationship between the executable, HTTP, and MCP
- use the repository `README.md` and `API.md` when you need the route inventory, exact request and response payloads, or the fuller LaunchAgent command reference
