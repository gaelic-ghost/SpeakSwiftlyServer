#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile } from "node:fs/promises";
import path from "node:path";

const hookRoot = path.resolve(process.cwd(), ".codex");
const stateDir = path.join(hookRoot, "state");
const logDir = path.join(hookRoot, "logs");
const seenTurnsPath = path.join(stateDir, "stop-tts-seen-turns.json");
const logPath = path.join(logDir, "stop-tts.jsonl");

const runtimeBaseUrl = process.env.CODEX_HOOK_TTS_BASE_URL ?? "http://127.0.0.1:7337";
const liveSpeechEndpoint = new URL("/speech/live", runtimeBaseUrl).toString();
const defaultProfileName = process.env.CODEX_HOOK_TTS_PROFILE_NAME ?? "default-femme";
const skipContinuedTurns = (process.env.CODEX_HOOK_TTS_SKIP_CONTINUATIONS ?? "true") !== "false";
const maxSeenTurns = Number.parseInt(process.env.CODEX_HOOK_TTS_MAX_SEEN_TURNS ?? "200", 10);

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(typeof chunk === "string" ? chunk : chunk.toString("utf8"));
  }
  return chunks.join("");
}

async function ensureRuntimePaths() {
  await mkdir(stateDir, { recursive: true });
  await mkdir(logDir, { recursive: true });
}

async function loadSeenTurns() {
  try {
    const raw = await readFile(seenTurnsPath, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed.filter((item) => typeof item === "string") : [];
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "ENOENT") {
      return [];
    }
    throw error;
  }
}

async function saveSeenTurns(turns) {
  await writeFile(seenTurnsPath, `${JSON.stringify(turns.slice(-maxSeenTurns), null, 2)}\n`, "utf8");
}

async function appendLog(entry) {
  const serialized = `${JSON.stringify({ timestamp: new Date().toISOString(), ...entry })}\n`;
  await appendFile(logPath, serialized, "utf8");
}

function normalizeMessage(input) {
  if (typeof input !== "string") return null;
  const trimmed = input.trim();
  return trimmed.length > 0 ? trimmed : null;
}

async function main() {
  await ensureRuntimePaths();

  const rawInput = await readStdin();
  const payload = rawInput.trim().length > 0 ? JSON.parse(rawInput) : {};
  const {
    session_id: sessionId = null,
    turn_id: turnId = null,
    stop_hook_active: stopHookActive = false,
    last_assistant_message: lastAssistantMessage = null,
    transcript_path: transcriptPath = null,
    cwd = process.cwd(),
    model = null,
  } = payload;

  const message = normalizeMessage(lastAssistantMessage);
  const dedupeKey = sessionId && turnId ? `${sessionId}:${turnId}` : null;

  if (!message) {
    await appendLog({
      outcome: "skipped",
      reason: "missing-last-assistant-message",
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
    });
    return;
  }

  if (skipContinuedTurns && stopHookActive) {
    await appendLog({
      outcome: "skipped",
      reason: "continued-stop-turn",
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
      preview: message.slice(0, 160),
    });
    return;
  }

  const seenTurns = await loadSeenTurns();
  if (dedupeKey && seenTurns.includes(dedupeKey)) {
    await appendLog({
      outcome: "skipped",
      reason: "duplicate-turn",
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
      preview: message.slice(0, 160),
    });
    return;
  }

  const response = await fetch(liveSpeechEndpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
    },
    body: JSON.stringify({
      text: message,
      profile_name: defaultProfileName,
    }),
  });

  const responseBody = await response.text();
  if (!response.ok) {
    await appendLog({
      outcome: "error",
      reason: "speech-route-rejected-request",
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
      status: response.status,
      statusText: response.statusText,
      responseBody,
      profileName: defaultProfileName,
      endpoint: liveSpeechEndpoint,
      preview: message.slice(0, 160),
    });
    return;
  }

  if (dedupeKey) {
    seenTurns.push(dedupeKey);
    await saveSeenTurns(seenTurns);
  }

  let parsedResponse = null;
  try {
    parsedResponse = JSON.parse(responseBody);
  } catch {
    parsedResponse = responseBody;
  }

  await appendLog({
    outcome: "queued",
    sessionId,
    turnId,
    stopHookActive,
    transcriptPath,
    cwd,
    model,
    endpoint: liveSpeechEndpoint,
    profileName: defaultProfileName,
    request: parsedResponse,
    preview: message.slice(0, 160),
  });
}

main().catch(async (error) => {
  try {
    await ensureRuntimePaths();
    await appendLog({
      outcome: "error",
      reason: "unexpected-hook-failure",
      error: error instanceof Error ? { message: error.message, stack: error.stack } : String(error),
    });
  } catch {}
  process.exitCode = 0;
});
