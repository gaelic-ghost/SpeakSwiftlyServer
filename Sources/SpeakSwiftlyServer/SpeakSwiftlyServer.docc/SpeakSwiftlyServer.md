# ``SpeakSwiftlyServer``

Embed the shared SpeakSwiftly speech runtime in an app, or package the same host behind HTTP, MCP, and command-line operator surfaces.

## Overview

`SpeakSwiftlyServer` is the library layer for the standalone SpeakSwiftly server package. It owns the embedded host session, the app-facing observable state model, and the HTTP and MCP server surfaces that can run inside an app process or behind the companion tool.

Use `import SpeakSwiftlyServer` for app integration. The package is internally split into core, HTTP, and MCP implementation targets, but those target module names are not supported public documentation or consumer import surfaces.

The package also ships the `SpeakSwiftlyServerTool` executable, but the executable is an operator surface built on top of this library rather than the main story of the hosted package docs. Start here when you need to:

- start the shared server inside an app process
- read the current host, queue, transport, and runtime snapshots from SwiftUI-friendly state
- decide when a consuming app should embed the host directly instead of launching the bundled tool helper

When you need transport-level route inventories, request and response payload examples, LaunchAgent management, bundled-helper layout, or command-line usage details, use the repository operator docs in the README and API reference:

- [README](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/README.md)
- [API Reference](https://github.com/gaelic-ghost/SpeakSwiftlyServer/blob/main/API.md)

## Topics

### Embedding The Shared Host

- ``EmbeddedServer``

### Articles

- <doc:First-Embedded-Session>
- <doc:Embedding-The-Server>
- <doc:Operator-Surfaces>
- <doc:Using-The-Command-Line-Tool>
- <doc:LaunchAgent-Workflow>
