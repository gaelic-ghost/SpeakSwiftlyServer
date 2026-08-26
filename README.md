# SpeakSwiftlyServer

*A local speech platform for Apple systems and developer workflows.*

![Speak Swiftly neon banner](./assets/speak-swiftly-banner.jpg)

Listen to the short Speak Swiftly Codex plugin promo:

<audio controls src="./docs/media/speakswiftlyserver-codex-plugin-promo.mp3">
  <a href="./docs/media/speakswiftlyserver-codex-plugin-promo.mp3">Download the Speak Swiftly Codex plugin promo audio.</a>
</audio>

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

`SpeakSwiftlyServer` is actively maintained and supported by Gale.

Redesigning this for improved performance in the future. Frankly, the neural TTS niche continues moving so fast that it doesn't make sense for me to do the full rework this needs until the dust settles. Eventually, though. Probably once OS 27 and Core AI hit stable and I can be maximally efficient with my time investments.

### What This Project Is

SpeakSwiftlyServer (*Speak Swiftly*) is a high-quality, local-first speech runtime built for macOS. Custom voices, batch jobs, easy integrations, and more.

### Motivation

This project was borne of my own need for affordable, customizable, high-quality text-to-speech, with easy integration into the apps I already used. I'm quite proud of this one already, and tbh we're just getting started~

## Quick Start

Add or upgrade the Socket marketplace entry to your Codex. Then, restart Codex and enable `Speak Swiftly` in the Plugin Directory under Socket.

Add Socket:
```bash
codex plugin marketplace add gaelic-ghost/socket
```

Upgrade Socket and Enabled Plugins:
```bash
codex plugin marketplace upgrade socket
```

After the plugin is enabled, install or refresh the local speech service:

```bash
xcrun swift run SpeakSwiftlyServerTool launch-agent install
xcrun swift run SpeakSwiftlyServerTool healthcheck
```

If using Codex Hooks, review and trust the stop hook from Speak Swiftly to have all replies automatically spoken in the order they arrive.

The plugin and the local service are separate on purpose. The plugin gives Codex the skills, MCP connection, and speech hooks. The local service is the native Swift process that actually speaks.

## Usage

Once the service is healthy, agents can use `Speak Swiftly` to:

- speak "final assistant replies" through `Speak Swiftly`
- queue speech, create new voice profiles, adjust how words are spoken, and control playback
- inspect the runtime, voice profiles, text profiles, and recent requests
- set default voice and model preferences

Operators can also open the local control panel at `http://127.0.0.1:7338/control-panel/` when running the foreground tool, or at the configured local HTTP listener port for an installed service.

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
