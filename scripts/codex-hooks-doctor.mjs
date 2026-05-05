#!/usr/bin/env node

import { readdir, readFile, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), "..");
const codexHome = process.env.CODEX_HOME ?? path.join(os.homedir(), ".codex");
const runtimeBaseUrl = process.env.CODEX_HOOK_TTS_BASE_URL ?? "http://127.0.0.1:7337";
const expectedProfileName = process.env.CODEX_HOOK_TTS_PROFILE_NAME ?? "default-femme";
const canonicalPluginName = "speak-swiftly";
const legacyPluginName = "speak-swiftly-server";
const pluginNames = [canonicalPluginName, legacyPluginName];
const preferredPluginKey = `${canonicalPluginName}@socket`;
const pluginMarketplaces = ["socket", "SpeakSwiftlyServer"];
const knownPluginKeys = pluginNames.flatMap((name) => pluginMarketplaces.map((marketplace) => `${name}@${marketplace}`));
const socketCachedHookPath = "~/.codex/plugins/cache/socket/speak-swiftly/5.0.5/hooks";
const standaloneCachedHookPath = "~/.codex/plugins/cache/SpeakSwiftlyServer/speak-swiftly/hooks";
const expectedStopHookCommands = [
  `node ${socketCachedHookPath}/stop-tts.mjs`,
  `node ${standaloneCachedHookPath}/stop-tts.mjs`,
];
const expectedPermissionHookCommands = [
  `node ${socketCachedHookPath}/permission-request-log.mjs`,
  `node ${standaloneCachedHookPath}/permission-request-log.mjs`,
];
const repairMode = process.argv.includes("--repair") || process.argv.includes("--repair-plan");

const checks = [];

function addCheck(status, title, detail = "") {
  checks.push({ status, title, detail });
}

function marker(status) {
  switch (status) {
    case "ok": return "OK";
    case "warn": return "WARN";
    case "fail": return "FAIL";
    default: return "INFO";
  }
}

async function pathExists(filePath) {
  try {
    await stat(filePath);
    return true;
  } catch {
    return false;
  }
}

async function readText(filePath) {
  try {
    return await readFile(filePath, "utf8");
  } catch {
    return null;
  }
}

async function readJSON(filePath) {
  const text = await readText(filePath);
  if (text === null) return null;
  try {
    return JSON.parse(text);
  } catch (error) {
    addCheck("fail", `Could not parse JSON at ${filePath}`, error instanceof Error ? error.message : String(error));
    return null;
  }
}

function eventHookCommands(hooksJSON, eventName) {
  const eventGroups = hooksJSON?.hooks?.[eventName];
  if (!Array.isArray(eventGroups)) return [];
  return eventGroups.flatMap((group) => Array.isArray(group.hooks) ? group.hooks : [])
    .filter((hook) => hook?.type === "command")
    .map((hook) => String(hook.command ?? ""));
}

function isSpeakSwiftlyHookCommand(command) {
  return command.includes("SpeakSwiftlyServer") || command.includes("stop-tts.mjs");
}

function isGlobalSpeakSwiftlyStopCommand(command) {
  return command.includes("hooks/stop-tts.mjs")
    && !command.includes("CODEX_HOOK_TTS_DATA_DIR")
    && !command.includes(".codex/hooks/stop-tts.mjs");
}

function commandSetIncludesAll(commands, expectedCommands) {
  return expectedCommands.every((expectedCommand) => commands.includes(expectedCommand));
}

export function classifyGlobalHookCommands(commands) {
  const speakSwiftlyCommands = commands.filter(isSpeakSwiftlyHookCommand);
  const globalStopCommands = speakSwiftlyCommands.filter(isGlobalSpeakSwiftlyStopCommand);
  const legacyOrDevCommands = speakSwiftlyCommands.filter((command) => !isGlobalSpeakSwiftlyStopCommand(command));

  if (speakSwiftlyCommands.length === 0) {
    return {
      status: "absent",
      speakSwiftlyCommands,
      globalStopCommands,
      legacyOrDevCommands,
      message: "Plugin-bundled hooks may still provide TTS when Codex dispatches installed plugin lifecycle config.",
    };
  }

  if (legacyOrDevCommands.length === 0) {
    return {
      status: "global-duplicate",
      speakSwiftlyCommands,
      globalStopCommands,
      legacyOrDevCommands,
      message: "User-level Speak Swiftly Stop hook duplicates the plugin-managed Stop hook; remove the global Stop hook when plugin-managed hooks are intended.",
    };
  }

  return {
    status: "legacy-or-dev",
    speakSwiftlyCommands,
    globalStopCommands,
    legacyOrDevCommands,
    message: `Remove legacy or dev-only global Speak Swiftly hook commands; plugin-managed hooks own final-reply TTS: ${legacyOrDevCommands.join(" | ")}`,
  };
}

async function inspectHookFile(label, filePath, eventName, options = {}) {
  const hooksJSON = await readJSON(filePath);
  if (!hooksJSON) {
    addCheck(options.missingSeverity ?? "warn", `${label} hooks file is not present`, filePath);
    return [];
  }

  const commands = eventHookCommands(hooksJSON, eventName);
  if (commands.length === 0) {
    addCheck(options.missingEventSeverity ?? "warn", `${label} hooks file has no ${eventName} command hook`, filePath);
  } else {
    addCheck("ok", `${label} ${eventName} hook command count: ${commands.length}`, commands.join(" | "));
  }
  return commands;
}

async function findInstalledPluginManifests(root) {
  const matches = [];
  async function walk(directory, depth) {
    if (depth > 7) return;
    let entries = [];
    try {
      entries = await readdir(directory, { withFileTypes: true });
    } catch {
      return;
    }

    for (const entry of entries) {
      const fullPath = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        if (entry.name === ".git" || entry.name === "node_modules") continue;
        await walk(fullPath, depth + 1);
      } else if (entry.name === "plugin.json" && path.basename(path.dirname(fullPath)) === ".codex-plugin") {
        const manifest = await readJSON(fullPath);
        if (pluginNames.includes(manifest?.name)) matches.push({ manifestPath: fullPath, manifest });
      }
    }
  }

  await walk(root, 0);
  return matches;
}

export function pluginConfigEntries(configText) {
  if (!configText) return [];

  return knownPluginKeys.map((key) => {
    const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    const sectionPattern = new RegExp(`\\[plugins\\."${escapedKey}"\\]([\\s\\S]*?)(?=\\n\\[|$)`);
    const match = configText.match(sectionPattern);
    const body = match?.[1] ?? "";
    const enabled = match ? /^\s*enabled\s*=\s*true\s*$/m.test(body) : false;
    return {
      key,
      pluginName: key.slice(0, key.indexOf("@")),
      marketplace: key.slice(key.indexOf("@") + 1),
      present: Boolean(match),
      enabled,
    };
  });
}

function summarizePluginConfig(configText) {
  const entries = pluginConfigEntries(configText);
  const presentEntries = entries.filter((entry) => entry.present);
  const enabledEntries = entries.filter((entry) => entry.enabled);

  if (presentEntries.length === 0) {
    addCheck("warn", "No Speak Swiftly plugin config entries found in config.toml");
    return { entries, presentEntries, enabledEntries };
  }

  addCheck(
    "info",
    "Speak Swiftly plugin config entries",
    presentEntries.map((entry) => `${entry.key}${entry.enabled ? ":enabled" : ":disabled"}`).join(", "),
  );

  if (enabledEntries.some((entry) => entry.key === preferredPluginKey)) {
    addCheck("ok", `${preferredPluginKey} appears enabled in config.toml`);
  } else if (enabledEntries.some((entry) => entry.pluginName === canonicalPluginName)) {
    addCheck(
      "ok",
      "Canonical Speak Swiftly plugin id appears enabled in config.toml",
      enabledEntries.map((entry) => entry.key).join(", "),
    );
  } else if (enabledEntries.length > 0) {
    addCheck(
      "warn",
      "Only legacy Speak Swiftly plugin ids appear enabled in config.toml",
      enabledEntries.map((entry) => entry.key).join(", "),
    );
  } else {
    addCheck("warn", "Speak Swiftly plugin entries exist but none appear enabled in config.toml");
  }

  if (enabledEntries.length > 1) {
    addCheck(
      "warn",
      "Duplicate Speak Swiftly plugin enablement detected",
      enabledEntries.map((entry) => entry.key).join(", "),
    );
  } else {
    addCheck("ok", "No duplicate enabled Speak Swiftly plugin entries detected");
  }

  return { entries, presentEntries, enabledEntries };
}

export function buildRepairPlan(pluginConfig) {
  const { presentEntries, enabledEntries } = pluginConfig;
  const preferredEntry = enabledEntries.find((entry) => entry.key === preferredPluginKey)
    ?? enabledEntries.find((entry) => entry.pluginName === canonicalPluginName)
    ?? presentEntries.find((entry) => entry.key === preferredPluginKey)
    ?? presentEntries.find((entry) => entry.pluginName === canonicalPluginName)
    ?? null;

  if (!preferredEntry) {
    return {
      status: "missing-canonical",
      preferredEntry: null,
      duplicateEntries: [],
      message: "Install or enable speak-swiftly from the Socket or SpeakSwiftlyServer marketplace first.",
    };
  }

  const duplicateEntries = presentEntries.filter((entry) => entry.key !== preferredEntry.key && (entry.enabled || entry.pluginName === legacyPluginName));
  return {
    status: duplicateEntries.length === 0 ? "clean" : "duplicates",
    preferredEntry,
    duplicateEntries,
    message: duplicateEntries.length === 0
      ? `keep ${preferredEntry.key}`
      : `keep ${preferredEntry.key}; disable or remove ${duplicateEntries.map((entry) => entry.key).join(", ")} after confirmation. No config was changed.`,
  };
}

function reportRepairPlan(pluginConfig) {
  if (!repairMode) {
    addCheck("info", "Repair mode is dry-run only and was not requested", "Run with --repair-plan to print the duplicate-enable repair plan.");
    return;
  }

  const repairPlan = buildRepairPlan(pluginConfig);
  if (repairPlan.status === "missing-canonical") {
    addCheck(
      "warn",
      "Dry-run repair plan could not choose a canonical Speak Swiftly entry",
      repairPlan.message,
    );
    return;
  }

  if (repairPlan.status === "clean") {
    addCheck("ok", "Dry-run repair plan has nothing to disable", repairPlan.message);
    return;
  }

  addCheck("info", "Dry-run repair plan", repairPlan.message);
}

async function fetchJSON(route) {
  const url = new URL(route, runtimeBaseUrl).toString();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 2500);
  try {
    const response = await fetch(url, { signal: controller.signal });
    const text = await response.text();
    if (!response.ok) {
      return { ok: false, url, status: response.status, text };
    }
    return { ok: true, url, value: JSON.parse(text) };
  } catch (error) {
    return { ok: false, url, error: error instanceof Error ? error.message : String(error) };
  } finally {
    clearTimeout(timeout);
  }
}

async function readRecentHookLog(logPath) {
  const text = await readText(logPath);
  if (text === null) return null;
  const entries = text.trim().split("\n").filter(Boolean).slice(-12).map((line) => {
    try {
      return JSON.parse(line);
    } catch {
      return { outcome: "unparseable", raw: line.slice(0, 120) };
    }
  });
  return entries;
}

function summarizeHookLog(label, entries) {
  if (!entries) {
    addCheck("info", `${label} hook log is not present yet`);
    return;
  }

  const outcomes = new Map();
  const profiles = new Set();
  for (const entry of entries) {
    outcomes.set(entry.outcome ?? "unknown", (outcomes.get(entry.outcome ?? "unknown") ?? 0) + 1);
    if (entry.profileName) profiles.add(entry.profileName);
  }

  const outcomeText = Array.from(outcomes.entries()).map(([key, value]) => `${key}:${value}`).join(", ");
  const profileText = profiles.size > 0 ? ` profiles: ${Array.from(profiles).join(", ")}` : "";
  addCheck("info", `${label} recent hook log`, `${outcomeText}${profileText}`);
}

async function main() {
  console.log("SpeakSwiftlyServer Codex hooks doctor");
  console.log(`repo: ${repoRoot}`);
  console.log(`codex home: ${codexHome}`);
  console.log(`runtime: ${runtimeBaseUrl}`);
  console.log("");

  const pluginManifestPath = path.join(repoRoot, ".codex-plugin", "plugin.json");
  const pluginManifest = await readJSON(pluginManifestPath);
  if (pluginManifest?.hooks === "./hooks/hooks.json") {
    addCheck("ok", "Repo plugin manifest declares plugin-managed hooks", pluginManifestPath);
  } else {
    addCheck("fail", "Repo plugin manifest does not declare ./hooks/hooks.json", pluginManifestPath);
  }

  const pluginStopHookCommands = await inspectHookFile("Repo plugin", path.join(repoRoot, "hooks", "hooks.json"), "Stop");
  if (commandSetIncludesAll(pluginStopHookCommands, expectedStopHookCommands)) {
    addCheck("ok", "Repo plugin Stop hook uses the expected Codex cache command paths");
  } else {
    addCheck("fail", "Repo plugin Stop hook does not use the expected Codex cache command paths", expectedStopHookCommands.join(" | "));
  }
  const pluginPermissionHookCommands = await inspectHookFile("Repo plugin", path.join(repoRoot, "hooks", "hooks.json"), "PermissionRequest");
  if (commandSetIncludesAll(pluginPermissionHookCommands, expectedPermissionHookCommands)) {
    addCheck("ok", "Repo plugin PermissionRequest hook uses the expected Codex cache command paths");
  } else {
    addCheck("warn", "Repo plugin PermissionRequest hook does not use the expected Codex cache command paths", expectedPermissionHookCommands.join(" | "));
  }

  const devStopHookCommands = await inspectHookFile("Repo dev-only", path.join(repoRoot, ".codex", "hooks.json"), "Stop");
  if (devStopHookCommands.some((command) => command.includes("CODEX_HOOK_TTS_DATA_DIR") && command.includes("/hooks/stop-log.mjs"))) {
    addCheck("ok", "Repo dev-only Stop hook logs payloads under .codex without queueing speech");
  } else {
    addCheck("warn", "Repo dev-only Stop hook is not wired as the expected logging-only local harness");
  }
  const devPermissionHookCommands = await inspectHookFile("Repo dev-only", path.join(repoRoot, ".codex", "hooks.json"), "PermissionRequest");
  if (devPermissionHookCommands.some((command) => command.includes("CODEX_HOOK_TTS_DATA_DIR") && command.includes("/hooks/permission-request-log.mjs"))) {
    addCheck("ok", "Repo dev-only PermissionRequest hook keeps probe logs under .codex");
  } else {
    addCheck("warn", "Repo dev-only PermissionRequest hook is not wired as the expected local probe harness");
  }

  const globalStopHookCommands = await inspectHookFile("Global user", path.join(codexHome, "hooks.json"), "Stop", {
    missingSeverity: "info",
    missingEventSeverity: "info",
  });
  const globalHookClassification = classifyGlobalHookCommands(globalStopHookCommands);
  if (globalHookClassification.status === "global-duplicate") {
    addCheck("warn", "Global user Speak Swiftly Stop hook duplicates plugin-managed TTS", globalHookClassification.message);
  } else if (globalHookClassification.status === "legacy-or-dev") {
    addCheck("warn", "Global user hooks include legacy or dev-only SpeakSwiftly TTS", globalHookClassification.message);
  } else {
    addCheck("ok", "Global user Speak Swiftly Stop hook is not configured", globalHookClassification.message);
  }
  const globalPermissionHookCommands = await inspectHookFile("Global user", path.join(codexHome, "hooks.json"), "PermissionRequest");
  if (globalPermissionHookCommands.some((command) => command.includes("hooks/permission-request-log.mjs") && !command.includes("CODEX_HOOK_TTS_DATA_DIR"))) {
    addCheck("ok", "Global user PermissionRequest logging probe is centralized", "Logs default to ~/.codex/speak-swiftly-server/hooks/logs/permission-request.jsonl.");
  } else if (globalPermissionHookCommands.length > 0) {
    addCheck("warn", "Global user PermissionRequest hook is not the centralized logging probe", globalPermissionHookCommands.join(" | "));
  } else {
    addCheck("info", "Global user PermissionRequest logging probe is not configured");
  }

  const configText = await readText(path.join(codexHome, "config.toml"));
  if (configText?.includes("codex_hooks = true")) {
    addCheck("ok", "Codex hooks feature flag appears enabled in config.toml");
  } else {
    addCheck("warn", "Could not confirm codex_hooks = true in config.toml");
  }
  const pluginConfig = summarizePluginConfig(configText);
  reportRepairPlan(pluginConfig);

  const installedManifests = await findInstalledPluginManifests(path.join(codexHome, "plugins", "cache"));
  if (installedManifests.length === 0) {
    addCheck("warn", "No installed Speak Swiftly plugin manifest found under the Codex plugin cache");
  } else {
    for (const { manifestPath, manifest } of installedManifests) {
      const hookStatus = manifest.hooks === "./hooks/hooks.json" ? "ok" : "warn";
      const identityStatus = manifest.name === canonicalPluginName ? "ok" : "warn";
      addCheck(identityStatus, `Installed plugin identity ${manifest.name}`, manifestPath);
      addCheck(hookStatus, `Installed plugin ${manifest.version ?? "unknown"} hook manifest`, manifestPath);
    }
  }

  const runtime = await fetchJSON("/overview");
  if (runtime.ok) {
    const overview = runtime.value;
    const profileNames = Array.isArray(overview.cached_profiles)
      ? overview.cached_profiles.map((profile) => profile.profile_name).join(", ")
      : "unknown";
    addCheck("ok", "Runtime host endpoint is reachable", runtime.url);
    addCheck("info", "Runtime worker/server state", `worker=${overview.worker_mode ?? "unknown"} server=${overview.server_mode ?? "unknown"} backend=${overview.runtime_backend_transition?.active_speech_backend ?? overview.runtime_configuration?.active_runtime_speech_backend ?? "unknown"}`);
    addCheck(
      overview.default_voice_profile_name === expectedProfileName ? "ok" : "warn",
      "Runtime default voice profile",
      `runtime=${overview.default_voice_profile_name ?? "unset"} hook=${expectedProfileName}`,
    );
    addCheck(profileNames.includes(expectedProfileName) ? "ok" : "fail", "Expected hook voice profile is cached", profileNames);
  } else {
    addCheck("warn", "Runtime host endpoint is not reachable", runtime.error ?? `${runtime.status}: ${runtime.text}`);
  }

  const voices = await fetchJSON("/voices");
  if (voices.ok) {
    const profiles = Array.isArray(voices.value.profiles) ? voices.value.profiles : voices.value;
    const names = Array.isArray(profiles) ? profiles.map((profile) => profile.profile_name).join(", ") : "unknown";
    addCheck(names.includes(expectedProfileName) ? "ok" : "fail", "Voice profile inventory includes hook profile", names);
  } else {
    addCheck("warn", "Voice profile endpoint is not reachable", voices.error ?? `${voices.status}: ${voices.text}`);
  }

  await summarizeHookLog("Centralized user/plugin", await readRecentHookLog(path.join(codexHome, "speak-swiftly-server", "hooks", "logs", "stop-tts.jsonl")));
  await summarizeHookLog("Repo dev-only speech", await readRecentHookLog(path.join(repoRoot, ".codex", "logs", "stop-tts.jsonl")));
  await summarizeHookLog("Repo dev-only Stop probe", await readRecentHookLog(path.join(repoRoot, ".codex", "logs", "stop-log.jsonl")));
  await summarizeHookLog("Centralized permission-request", await readRecentHookLog(path.join(codexHome, "speak-swiftly-server", "hooks", "logs", "permission-request.jsonl")));
  await summarizeHookLog("Repo dev-only permission-request", await readRecentHookLog(path.join(repoRoot, ".codex", "logs", "permission-request.jsonl")));

  console.log("Checks:");
  for (const check of checks) {
    const detail = check.detail ? `\n    ${check.detail}` : "";
    console.log(`- [${marker(check.status)}] ${check.title}${detail}`);
  }

  const failures = checks.filter((check) => check.status === "fail").length;
  process.exitCode = failures > 0 ? 1 : 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error("SpeakSwiftlyServer hooks doctor failed before it could finish:");
    console.error(error instanceof Error ? error.stack ?? error.message : String(error));
    process.exitCode = 1;
  });
}
