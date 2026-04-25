#!/usr/bin/env node

import { mkdir, readFile, writeFile, appendFile, rm } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const hookRoot = path.resolve(path.dirname(scriptPath), "..");
const stateDir = path.join(hookRoot, "state");
const logDir = path.join(hookRoot, "logs");
const seenTurnsPath = path.join(stateDir, "stop-tts-seen-turns.json");
const logPath = path.join(logDir, "stop-tts.jsonl");

const runtimeBaseUrl = process.env.CODEX_HOOK_TTS_BASE_URL ?? "http://127.0.0.1:7337";
const liveSpeechEndpoint = new URL("/speech/live", runtimeBaseUrl).toString();
const defaultProfileName = process.env.CODEX_HOOK_TTS_PROFILE_NAME ?? "default-femme";
const skipContinuedTurns = (process.env.CODEX_HOOK_TTS_SKIP_CONTINUATIONS ?? "true") !== "false";
const skipStructuredMessages = (process.env.CODEX_HOOK_TTS_SKIP_STRUCTURED_MESSAGES ?? "true") !== "false";
const logFullPayload = (process.env.CODEX_HOOK_TTS_LOG_FULL_PAYLOAD ?? "false") === "true";
const maxSeenTurns = Number.parseInt(process.env.CODEX_HOOK_TTS_MAX_SEEN_TURNS ?? "200", 10);
const stateLockDir = path.join(stateDir, "stop-tts-seen-turns.lock");
const stateLockTimeoutMs = Number.parseInt(process.env.CODEX_HOOK_TTS_STATE_LOCK_TIMEOUT_MS ?? "3000", 10);
const stateLockPollMs = Number.parseInt(process.env.CODEX_HOOK_TTS_STATE_LOCK_POLL_MS ?? "50", 10);

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

async function removeDirectoryIfExists(directoryPath) {
  try {
    await rm(directoryPath, { recursive: true, force: true });
  } catch {}
}

async function sleep(milliseconds) {
  await new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function withStateLock(operation) {
  const deadline = Date.now() + stateLockTimeoutMs;
  while (true) {
    try {
      await mkdir(stateLockDir);
      break;
    } catch (error) {
      if (
        error
        && typeof error === "object"
        && "code" in error
        && error.code === "EEXIST"
        && Date.now() < deadline
      ) {
        await sleep(stateLockPollMs);
        continue;
      }
      throw error;
    }
  }

  try {
    return await operation();
  } finally {
    await removeDirectoryIfExists(stateLockDir);
  }
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

function payloadLogFields(rawInput, payload) {
  if (!logFullPayload) return {};
  return {
    rawPayload: rawInput,
    payload,
  };
}

function structuredMessageReason(message) {
  if (!skipStructuredMessages) return null;
  const trimmed = message.trim();
  if (!trimmed.startsWith("{") && !trimmed.startsWith("[")) return null;

  let parsed = null;
  try {
    parsed = JSON.parse(trimmed);
  } catch {
    return null;
  }

  if (Array.isArray(parsed)) return null;
  if (!parsed || typeof parsed !== "object") return null;

  const keys = Object.keys(parsed);
  const compactMetadataKeys = new Set(["title", "suggestions", "exclude"]);
  if (keys.length > 0 && keys.every((key) => compactMetadataKeys.has(key))) {
    return "structured-assistant-metadata";
  }

  return null;
}

function stringAttribute(value) {
  if (typeof value === "string" && value.length > 0) return value;
  if (typeof value === "boolean" || typeof value === "number") return String(value);
  return null;
}

function speechRequestBody(message, payload, profileName) {
  const {
    session_id: sessionId = null,
    turn_id: turnId = null,
    transcript_path: transcriptPath = null,
    cwd = null,
    model = null,
    permission_mode: permissionMode = null,
    hook_event_name: hookEventName = null,
  } = payload;

  const attributes = Object.fromEntries(
    Object.entries({
      session_id: sessionId,
      turn_id: turnId,
      transcript_path: transcriptPath,
      model,
      permission_mode: permissionMode,
      hook_event_name: hookEventName,
    })
      .map(([key, value]) => [key, stringAttribute(value)])
      .filter(([, value]) => value !== null),
  );

  return {
    text: message,
    profile_name: profileName,
    cwd: typeof cwd === "string" && cwd.length > 0 ? cwd : undefined,
    request_context: {
      source: "codex-stop-hook",
      app: "Codex",
      agent: model,
      project: typeof cwd === "string" && cwd.length > 0 ? path.basename(cwd) : undefined,
      topic: "assistant-final-reply",
      attributes,
    },
  };
}

async function main() {
  await ensureRuntimePaths();

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

  const {
    session_id: sessionId = null,
    turn_id: turnId = null,
    stop_hook_active: stopHookActive = false,
    last_assistant_message: lastAssistantMessage = null,
    transcript_path: transcriptPath = null,
    cwd = process.cwd(),
    model = null,
  } = payload;
  const fullPayloadLog = payloadLogFields(rawInput, payload);

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
      ...fullPayloadLog,
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
      ...fullPayloadLog,
    });
    return;
  }

  const structuredReason = structuredMessageReason(message);
  if (structuredReason) {
    await appendLog({
      outcome: "skipped",
      reason: structuredReason,
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
      preview: message.slice(0, 160),
      ...fullPayloadLog,
    });
    return;
  }

  if (dedupeKey) {
    const reservedTurn = await withStateLock(async () => {
      const seenTurns = await loadSeenTurns();
      if (seenTurns.includes(dedupeKey)) {
        return false;
      }
      seenTurns.push(dedupeKey);
      await saveSeenTurns(seenTurns);
      return true;
    });

    if (!reservedTurn) {
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
        ...fullPayloadLog,
      });
      return;
    }
  }

  let response = null;
  try {
    response = await fetch(liveSpeechEndpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
      },
      body: JSON.stringify(speechRequestBody(message, payload, defaultProfileName)),
    });
  } catch (error) {
    await appendLog({
      outcome: "error",
      reason: "speech-route-unreachable",
      sessionId,
      turnId,
      stopHookActive,
      transcriptPath,
      cwd,
      model,
      profileName: defaultProfileName,
      endpoint: liveSpeechEndpoint,
      preview: message.slice(0, 160),
      error: error instanceof Error ? { message: error.message, cause: String(error.cause ?? "") } : String(error),
      ...fullPayloadLog,
    });
    return;
  }

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
      ...fullPayloadLog,
    });
    return;
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
    ...fullPayloadLog,
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
