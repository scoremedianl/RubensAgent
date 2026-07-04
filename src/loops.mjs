// Two kinds of "loops":
//   1. cron  — a scheduled prompt that spins up a headless one-shot session
//              in a project on a cron schedule (runs even with the app closed).
//   2. auto-continue — keep a live session working by auto-sending a follow-up
//              after each turn until a max iteration count or a stop marker.
//
// Cron loops are persisted to disk so they survive restarts.

import fs from "node:fs";
import cron from "node-cron";
import crypto from "node:crypto";
import { config } from "./config.mjs";
import { ClaudeSession } from "./claude.mjs";

/** @type {Map<string, {def:object, task:import('node-cron').ScheduledTask}>} */
const scheduled = new Map();

function load() {
  try {
    return JSON.parse(fs.readFileSync(config.loopsFile, "utf8"));
  } catch {
    return [];
  }
}
function save(list) {
  fs.writeFileSync(config.loopsFile, JSON.stringify(list, null, 2), { mode: 0o600 });
}

export function listLoops() {
  return load();
}

export function addLoop(def) {
  if (def.type !== "cron") throw new Error("only 'cron' loops are persisted");
  if (!cron.validate(def.schedule)) throw new Error(`invalid cron schedule: ${def.schedule}`);
  if (!def.cwd || !def.prompt) throw new Error("cwd and prompt are required");
  const list = load();
  const loop = {
    id: crypto.randomUUID(),
    type: "cron",
    schedule: def.schedule,
    project: def.project || null,
    cwd: def.cwd,
    prompt: def.prompt,
    autoApprove: def.autoApprove !== false,
    model: def.model || null,
    enabled: def.enabled !== false,
    createdAt: new Date().toISOString(),
    lastRun: null,
    lastSummary: null,
    lastSessionId: null,
  };
  list.push(loop);
  save(list);
  if (loop.enabled) schedule(loop);
  return loop;
}

export function removeLoop(id) {
  const list = load().filter((l) => l.id !== id);
  save(list);
  const s = scheduled.get(id);
  if (s) { s.task.stop(); scheduled.delete(id); }
  return { removed: true };
}

export function setLoopEnabled(id, enabled) {
  const list = load();
  const loop = list.find((l) => l.id === id);
  if (!loop) throw new Error("loop not found");
  loop.enabled = enabled;
  save(list);
  const s = scheduled.get(id);
  if (enabled && !s) schedule(loop);
  if (!enabled && s) { s.task.stop(); scheduled.delete(id); }
  return loop;
}

// Register all enabled cron loops on startup.
export function startScheduler() {
  for (const loop of load()) {
    if (loop.enabled) schedule(loop);
  }
}

function schedule(loop) {
  const task = cron.schedule(loop.schedule, () => runCronLoop(loop.id));
  scheduled.set(loop.id, { def: loop, task });
}

// Run one scheduled loop as a headless one-shot session and record a summary.
export function runCronLoop(id) {
  const list = load();
  const loop = list.find((l) => l.id === id);
  if (!loop) return;

  const claude = new ClaudeSession({
    cwd: loop.cwd,
    autoApprove: loop.autoApprove,
    model: loop.model,
  });
  let text = "";
  let sessionId = null;

  claude.on("session", (sid) => { sessionId = sid; });
  claude.on("event", (event) => {
    if (event.type === "assistant") {
      for (const block of event.message?.content || []) {
        if (block.type === "text") text += block.text;
      }
    }
    if (event.type === "result") {
      finalize(event.subtype === "success" ? "success" : "error");
    }
  });
  claude.on("exit", () => finalize("exited"));
  claude.on("error", () => finalize("error"));

  let finalized = false;
  function finalize(status) {
    if (finalized) return;
    finalized = true;
    const fresh = load();
    const l = fresh.find((x) => x.id === id);
    if (l) {
      l.lastRun = new Date().toISOString();
      l.lastStatus = status;
      l.lastSessionId = sessionId;
      l.lastSummary = text.slice(-2000); // keep tail; full log is in the transcript
      save(fresh);
    }
    claude.stop();
  }

  claude.start();
  claude.once("session", () => claude.send(loop.prompt));
  // Safety timeout so a stuck loop can't run forever.
  setTimeout(() => finalize("timeout"), 30 * 60 * 1000);
}

// --- Auto-continue on a live session --------------------------------------

// Attach to a live session object (from sessions.mjs). After each `result`
// event it sends `continuePrompt` again, up to maxIterations, unless the
// assistant output contained `stopMarker`.
export function attachAutoContinue(session, {
  maxIterations = 10,
  continuePrompt = "Continue.",
  stopMarker = null,
} = {}) {
  let iterations = 0;
  session.autoContinue = (result) => {
    if (iterations >= maxIterations) { session.autoContinue = null; return; }
    if (stopMarker && result?.result && String(result.result).includes(stopMarker)) {
      session.autoContinue = null;
      return;
    }
    iterations += 1;
    try {
      session.send(continuePrompt);
    } catch {
      session.autoContinue = null;
    }
  };
  return { attached: true, maxIterations };
}
