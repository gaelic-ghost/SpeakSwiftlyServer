#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import { speakableMessageProjection } from "./stop-tts.mjs";

test("speakableMessageProjection skips configured sections and keeps a brief notice", () => {
  const projection = speakableMessageProjection(
    [
      "**Answer**",
      "",
      "Yes.",
      "",
      "**Meaning**",
      "",
      "The hook reads the concise sections.",
      "",
      "**Evidence**",
      "",
      "Dense command output.",
      "",
      "**Details**",
      "",
      "A long file list.",
      "",
      "**Risk**",
      "",
      "No blocker.",
    ].join("\n"),
    {
      skippedSectionNames: new Set(["evidence", "details"]),
      sectionNoticeMode: "brief",
    },
  );

  assert.deepEqual(projection.presentSections, ["Answer", "Meaning", "Evidence", "Details", "Risk"]);
  assert.deepEqual(projection.spokenSections, ["Answer", "Meaning", "Risk"]);
  assert.deepEqual(projection.skippedSections, ["Evidence", "Details"]);
  assert.match(projection.text, /\*\*Answer\*\*/);
  assert.match(projection.text, /Yes\./);
  assert.doesNotMatch(projection.text, /Dense command output/);
  assert.doesNotMatch(projection.text, /A long file list/);
  assert.match(projection.text, /Skipped sections present: Evidence and Details\./);
});

test("speakableMessageProjection supports verbose section notices", () => {
  const projection = speakableMessageProjection("## Answer\n\nDone.\n\n## Evidence\n\nValidated.", {
    skippedSectionNames: new Set(["evidence"]),
    sectionNoticeMode: "verbose",
  });

  assert.equal(
    projection.text,
    "## Answer\n\nDone.\n\nEvidence section is present in the written reply but skipped for speech.",
  );
});

test("speakableMessageProjection preserves unsectioned messages", () => {
  const message = "A tiny ordinary reply.";
  const projection = speakableMessageProjection(message, {
    skippedSectionNames: new Set(["evidence"]),
    sectionNoticeMode: "brief",
  });

  assert.equal(projection.text, message);
  assert.deepEqual(projection.presentSections, []);
  assert.deepEqual(projection.spokenSections, []);
  assert.deepEqual(projection.skippedSections, []);
});

test("speakableMessageProjection can skip all sections without a spoken notice", () => {
  const projection = speakableMessageProjection("Answer\n\nHidden.", {
    skippedSectionNames: new Set(["answer"]),
    sectionNoticeMode: "none",
  });

  assert.equal(projection.text, "");
  assert.deepEqual(projection.presentSections, ["Answer"]);
  assert.deepEqual(projection.spokenSections, []);
  assert.deepEqual(projection.skippedSections, ["Answer"]);
});
