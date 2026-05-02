#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import {
  buildRepairPlan,
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
codex_hooks = true

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
