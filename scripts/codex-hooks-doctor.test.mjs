#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRepairPlan,
  classifyGlobalHookCommands,
  expectedHookReviewStateKeys,
  hookReviewStateEntries,
  pluginConfigEntries,
} from "./codex-hooks-doctor.mjs";

function summarize(configText) {
  const entries = pluginConfigEntries(configText);
  return {
    entries,
    presentEntries: entries.filter((entry) => entry.present),
    enabledEntries: entries.filter((entry) => entry.enabled),
  };
}

test("pluginConfigEntries detects current and legacy marketplace entries", () => {
  const config = `
hooks = true

[plugins."speak-swiftly@socket"]
enabled = true

[plugins."speak-swiftly@SpeakSwiftlyServer"]
enabled = false

[plugins."speak-swiftly-server@socket"]
enabled = true
`;

  const entries = pluginConfigEntries(config);
  assert.deepEqual(
    entries.filter((entry) => entry.present).map((entry) => [entry.key, entry.enabled]),
    [
      ["speak-swiftly@socket", true],
      ["speak-swiftly@SpeakSwiftlyServer", false],
      ["speak-swiftly-server@socket", true],
    ],
  );
});

test("buildRepairPlan prefers canonical Socket entry over duplicate legacy entries", () => {
  const plan = buildRepairPlan(summarize(`
[plugins."speak-swiftly@socket"]
enabled = true

[plugins."speak-swiftly@SpeakSwiftlyServer"]
enabled = true

[plugins."speak-swiftly-server@socket"]
enabled = true

[plugins."speak-swiftly-server@SpeakSwiftlyServer"]
enabled = false
`));

  assert.equal(plan.status, "duplicates");
  assert.equal(plan.preferredEntry.key, "speak-swiftly@socket");
  assert.deepEqual(
    plan.duplicateEntries.map((entry) => entry.key),
    [
      "speak-swiftly@SpeakSwiftlyServer",
      "speak-swiftly-server@socket",
      "speak-swiftly-server@SpeakSwiftlyServer",
    ],
  );
});

test("buildRepairPlan refuses mutation when only legacy entries exist", () => {
  const plan = buildRepairPlan(summarize(`
[plugins."speak-swiftly-server@socket"]
enabled = true
`));

  assert.equal(plan.status, "missing-canonical");
  assert.equal(plan.preferredEntry, null);
  assert.equal(plan.duplicateEntries.length, 0);
});

test("buildRepairPlan keeps a single canonical standalone entry when Socket is absent", () => {
  const plan = buildRepairPlan(summarize(`
[plugins."speak-swiftly@SpeakSwiftlyServer"]
enabled = true
`));

  assert.equal(plan.status, "clean");
  assert.equal(plan.preferredEntry.key, "speak-swiftly@SpeakSwiftlyServer");
  assert.equal(plan.duplicateEntries.length, 0);
});

test("classifyGlobalHookCommands warns on user-level duplicate Stop hook", () => {
  const classification = classifyGlobalHookCommands([
    "node ~/.codex/plugins/cache/SpeakSwiftlyServer/speak-swiftly/hooks/stop-tts.mjs",
  ]);

  assert.equal(classification.status, "global-duplicate");
  assert.equal(classification.globalStopCommands.length, 1);
  assert.equal(classification.legacyOrDevCommands.length, 0);
});

test("classifyGlobalHookCommands warns on repo-local dev harness commands", () => {
  const classification = classifyGlobalHookCommands([
    "CODEX_HOOK_TTS_DATA_DIR=\"$(git rev-parse --show-toplevel)/.codex\" node \"$(git rev-parse --show-toplevel)/hooks/stop-tts.mjs\"",
  ]);

  assert.equal(classification.status, "legacy-or-dev");
  assert.equal(classification.globalStopCommands.length, 0);
  assert.equal(classification.legacyOrDevCommands.length, 1);
});

test("classifyGlobalHookCommands treats absent Speak Swiftly hook as plugin-only", () => {
  const classification = classifyGlobalHookCommands([
    "node /Users/example/other-hook.mjs",
  ]);

  assert.equal(classification.status, "absent");
  assert.equal(classification.speakSwiftlyCommands.length, 0);
});

test("hookReviewStateEntries reads trusted hook hashes from config.toml", () => {
  const entries = hookReviewStateEntries(`
[hooks.state]

[hooks.state."/repo/.codex/hooks.json:stop:0:0"]
trusted_hash = "sha256:abc123"

[hooks.state."speak-swiftly@socket:hooks/hooks.json:permission_request:0:0"]
trusted_hash = "sha256:def456"

[plugins."speak-swiftly@socket"]
enabled = true
`);

  assert.deepEqual(entries, [
    {
      key: "/repo/.codex/hooks.json:stop:0:0",
      trustedHash: "sha256:abc123",
    },
    {
      key: "speak-swiftly@socket:hooks/hooks.json:permission_request:0:0",
      trustedHash: "sha256:def456",
    },
  ]);
});

test("expectedHookReviewStateKeys includes repo and Socket hook identities", () => {
  assert.deepEqual(
    expectedHookReviewStateKeys("/repo").map((entry) => entry.key),
    [
      "/repo/.codex/hooks.json:permission_request:0:0",
      "/repo/.codex/hooks.json:stop:0:0",
      "speak-swiftly@socket:hooks/hooks.json:permission_request:0:0",
      "speak-swiftly@socket:hooks/hooks.json:stop:0:0",
    ],
  );
});
