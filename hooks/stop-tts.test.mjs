#!/usr/bin/env node

import assert from "node:assert/strict";
import test from "node:test";

import { normalizeMarkdownTablesForSpeech, speakableMessageProjection, speechRequestBody } from "./stop-tts.mjs";

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
  assert.match(projection.text, /Note: The following sections were present, but skipped\. Evidence and Details\./);
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

test("speakableMessageProjection converts Markdown tables into speech-safe rows", () => {
  const projection = speakableMessageProjection(
    [
      "## Answer",
      "",
      "| Scenario | Expected speech |",
      "|---|---|",
      "| Simple table | Headers then values |",
      '| Inline code | `status = "ready"` |',
    ].join("\n"),
  );

  assert.match(projection.text, /Table columns: Scenario, Expected speech\./);
  assert.match(projection.text, /Scenario: Simple table; Expected speech: Headers then values/);
  assert.match(projection.text, /Scenario: Inline code; Expected speech: `status = "ready"`/);
  assert.doesNotMatch(projection.text, /\|---\|/);
  assert.doesNotMatch(projection.text, /\| Scenario \|/);
});

test("normalizeMarkdownTablesForSpeech preserves ordinary inline pipes", () => {
  const message = "The transport choice is HTTP | MCP | CLI, based on the caller.";

  assert.equal(normalizeMarkdownTablesForSpeech(message), message);
});

test("normalizeMarkdownTablesForSpeech keeps escaped table pipes as cell content", () => {
  const normalized = normalizeMarkdownTablesForSpeech(
    [
      "| Surface | Value |",
      "|---|---|",
      "| Transport | HTTP \\| MCP |",
    ].join("\n"),
  );

  assert.equal(normalized, "Table columns: Surface, Value.\nSurface: Transport; Value: HTTP | MCP");
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
  );

  assert.equal(body.profile_name, undefined);
  assert.equal(body.cwd, "/tmp/project");
  assert.equal(body.request_context.source, "Codex Hook");
  assert.equal(body.request_context.topic, "project");
  assert.deepEqual(body.request_context.attributes, {
    session_id: "session-1",
    turn_id: "turn-1",
    transcript_path: "/tmp/transcript.jsonl",
    model: "gpt-test",
    hook_event_name: "Stop",
  });
});

test("speechRequestBody includes a configured voice profile override", () => {
  const body = speechRequestBody("Answer\n\nDone.", { cwd: "/tmp/project" }, " swift-signal ");

  assert.equal(body.profile_name, "swift-signal");
});

test("speechRequestBody labels Codex document workspaces as Codex Chat", () => {
  const body = speechRequestBody(
    "Answer\n\nDone.",
    {
      cwd: "/Users/gale/Documents/Codex/heya-codex",
    }
  );

  assert.equal(body.request_context.source, "Codex");
  assert.equal(body.request_context.topic, "Chat");
});

test("speechRequestBody labels dated Codex document workspaces as Codex Chat", () => {
  const body = speechRequestBody(
    "Answer\n\nDone.",
    {
      cwd: "/Users/gale/Documents/Codex/2026-05-04/heya-codex",
    }
  );

  assert.equal(body.request_context.source, "Codex");
  assert.equal(body.request_context.topic, "Chat");
});

test("speechRequestBody falls back to assistant final reply topic when cwd has no basename", () => {
  const body = speechRequestBody("Answer\n\nDone.", { cwd: "/" });

  assert.equal(body.request_context.topic, "assistant-final-reply");
});
