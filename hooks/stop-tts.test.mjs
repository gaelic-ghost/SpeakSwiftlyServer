#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import { speakableMessageProjection, speechRequestBody } from "./stop-tts.mjs";

test("speakableMessageProjection skips Evidence and Details by default", () => {
  const projection = speakableMessageProjection(
    [
      "**Answer**",
      "",
      "Done.",
      "",
      "**Evidence**",
      "",
      "Dense command output.",
      "",
      "**Details**",
      "",
      "Extra file inventory.",
    ].join("\n"),
  );

  assert.deepEqual(projection.presentSections, ["Answer", "Evidence", "Details"]);
  assert.deepEqual(projection.spokenSections, ["Answer"]);
  assert.deepEqual(projection.skippedSections, ["Evidence", "Details"]);
  assert.doesNotMatch(projection.text, /Dense command output/);
  assert.doesNotMatch(projection.text, /Extra file inventory/);
});

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

test("speechRequestBody labels Stop hook speech with Codex Hook source", () => {
  const body = speechRequestBody(
    "Answer\n\nDone.",
    {
      session_id: "session-1",
      turn_id: "turn-1",
      transcript_path: "/tmp/transcript.jsonl",
      cwd: "/tmp/project",
      model: "gpt-test",
      hook_event_name: "Stop",
    },
    "default-femme",
  );

  assert.equal(body.cwd, "/tmp/project");
  assert.equal(body.request_context.source, "Codex Hook");
  assert.equal(body.request_context.topic, "assistant-final-reply");
  assert.deepEqual(body.request_context.attributes, {
    session_id: "session-1",
    turn_id: "turn-1",
    transcript_path: "/tmp/transcript.jsonl",
    model: "gpt-test",
    hook_event_name: "Stop",
  });
});
