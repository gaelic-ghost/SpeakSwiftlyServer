# SpeakSwiftlyServer

Local speech for Codex and Apple-platform tools, packaged as a small server plus the `Speak Swiftly` plugin payload.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Development](#development)
- [Repo Structure](#repo-structure)
- [Release Notes](#release-notes)
- [License](#license)

## Overview

### Status

This project is actively available and stable enough to try.

### What This Project Is

TBD

### Motivation

TBD

## Quick Start

Install or update the Socket marketplace entry, then restart Codex and enable `Speak Swiftly` in the Plugin Directory.

```bash
codex plugin marketplace add gaelic-ghost/socket
codex plugin marketplace upgrade socket
```

After the plugin is enabled, install or refresh the local speech service:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

The plugin and the local service are separate on purpose. The plugin gives Codex the skills, MCP connection, and speech hooks. The local service is the native Swift process that actually speaks.

## Usage

Once the service is healthy, agents can use `Speak Swiftly` to:

- speak final replies through the local voice service
- inspect the runtime, voice profiles, text profiles, and recent requests
- queue speech, cancel queued work, clear completed work, and control playback
- choose between the built-in `swift-signal` and `swift-anchor` voices

The normal end-user path is plugin-managed. Do not copy repo-local hook files into a Codex home directory for ordinary setup.

For the detailed HTTP and MCP contract, see [API.md](./API.md).

## Development

For local setup, validation, contribution workflow, release workflow, LaunchAgent details, embedding notes, plugin-maintainer guidance, and repo-specific maintainer rules, see [CONTRIBUTING.md](./CONTRIBUTING.md) and [AGENTS.md](./AGENTS.md).

## Repo Structure

```text
.
├── Sources/
├── Tests/
├── docs/
├── hooks/
├── skills/
├── .codex-plugin/
├── API.md
├── CONTRIBUTING.md
└── Package.swift
```

## Release Notes

Tagged release notes live in [GitHub Releases](https://github.com/gaelic-ghost/SpeakSwiftlyServer/releases). Historical release notes and checklists live under [docs/releases](./docs/releases/).

## License

See [LICENSE](./LICENSE).
