#!/usr/bin/env node

import { mkdir, appendFile } from "node:fs/promises";
import path from "node:path";

const hookRoot = path.resolve(process.cwd(), ".codex");
const logDir = path.join(hookRoot, "logs");
const logPath = path.join(logDir, "notify-events.jsonl");

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) {
    chunks.push(typeof chunk === "string" ? chunk : chunk.toString("utf8"));
  }
  return chunks.join("");
}

async function main() {
  await mkdir(logDir, { recursive: true });
  const rawArg = process.argv[2] ?? "";
  const rawStdin = await readStdin();

  let parsedArg = null;
  if (rawArg.trim().length > 0) {
    try {
      parsedArg = JSON.parse(rawArg);
    } catch {
      parsedArg = rawArg;
    }
  }

  let parsedStdin = null;
  if (rawStdin.trim().length > 0) {
    try {
      parsedStdin = JSON.parse(rawStdin);
    } catch {
      parsedStdin = rawStdin;
    }
  }

  const entry = {
    timestamp: new Date().toISOString(),
    argv: process.argv,
    cwd: process.cwd(),
    arg: parsedArg,
    stdin: parsedStdin,
    event: parsedArg ?? parsedStdin,
    env: {
      TERM_PROGRAM: process.env.TERM_PROGRAM ?? null,
      TMUX: process.env.TMUX ?? null,
      CODEX_HOME: process.env.CODEX_HOME ?? null,
    },
  };

  await appendFile(logPath, `${JSON.stringify(entry)}\n`, "utf8");
}

main().catch(async (error) => {
  try {
    await mkdir(logDir, { recursive: true });
    await appendFile(
      logPath,
      `${JSON.stringify({
        timestamp: new Date().toISOString(),
        error: error instanceof Error ? { message: error.message, stack: error.stack } : String(error),
      })}\n`,
      "utf8",
    );
  } catch {}
  process.exitCode = 0;
});
