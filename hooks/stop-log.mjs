#!/usr/bin/env node

import { appendFile, mkdir } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

const codexHome = process.env.CODEX_HOME ?? path.join(os.homedir(), ".codex");
const dataRoot = process.env.CODEX_HOOK_TTS_DATA_DIR
  ? path.resolve(process.env.CODEX_HOOK_TTS_DATA_DIR)
  : path.join(codexHome, "speak-swiftly-server", "hooks");
const logDir = path.join(dataRoot, "logs");
const logPath = path.join(logDir, "stop-log.jsonl");
const logFullPayload = (process.env.CODEX_HOOK_TTS_LOG_FULL_PAYLOAD ?? "false") === "true";

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(typeof chunk === "string" ? chunk : chunk.toString("utf8"));
  }
  return chunks.join("");
}

async function appendLog(entry) {
  await mkdir(logDir, { recursive: true });
  const serialized = `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`;
  await appendFile(logPath, serialized, "utf8");
}

function stringField(payload, key) {
  const value = payload?.[key];
  return typeof value === "string" && value.length > 0 ? value : null;
}

function payloadLogFields(rawInput, payload) {
  if (!logFullPayload) return {};
  return {
    rawPayload: rawInput,
    payload,
  };
}

async function main() {
  const rawInput = await readStdin();
  let payload = {};
  try {
    payload = rawInput.trim().length > 0 ? JSON.parse(rawInput) : {};
  } catch (error) {
    await appendLog({
      outcome: "skipped",
      reason: "invalid-json-payload",
      rawPayloadPreview: rawInput.slice(0, 500),
      error: error instanceof Error ? { message: error.message } : String(error),
    });
    return;
  }

  const lastAssistantMessage = stringField(payload, "last_assistant_message");
  await appendLog({
    outcome: "logged",
    hookEventName: stringField(payload, "hook_event_name"),
    sessionId: stringField(payload, "session_id"),
    turnId: stringField(payload, "turn_id"),
    stopHookActive: payload?.stop_hook_active === true,
    transcriptPath: stringField(payload, "transcript_path"),
    cwd: stringField(payload, "cwd") ?? process.cwd(),
    model: stringField(payload, "model"),
    permissionMode: stringField(payload, "permission_mode"),
    hasLastAssistantMessage: lastAssistantMessage !== null,
    lastAssistantMessagePreview: lastAssistantMessage?.slice(0, 500) ?? null,
    ...payloadLogFields(rawInput, payload),
  });
}

main().catch(async (error) => {
  try {
    await appendLog({
      outcome: "error",
      reason: "unexpected-hook-failure",
      error: error instanceof Error ? { message: error.message, stack: error.stack } : String(error),
    });
  } catch {}
  process.exitCode = 0;
});
