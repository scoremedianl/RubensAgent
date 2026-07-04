// In-memory registry of live Claude sessions plus helpers to read the
// persisted transcripts Claude Code writes to disk (for "look back at" history).

import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
import { ClaudeSession } from "./claude.mjs";
import { claudeProjectsDir, transcriptSlug } from "./config.mjs";

/** @type {Map<string, LiveSession>} keyed by Claude session id (or a temp id until assigned) */
const live = new Map();
let tempCounter = 0;

class LiveSession {
  constructor(claude, meta) {
    this.claude = claude;
    this.meta = meta; // { project, cwd, autoApprove, startedAt }
    this.subscribers = new Set(); // ws clients
    this.key = claude.sessionId || `pending-${++tempCounter}`;
    this.lastResult = null;
    this.autoContinue = null; // set by loops.mjs when a session is in auto-continue

    claude.on("session", (id) => {
      // Re-key under the real session id once Claude assigns it.
      live.delete(this.key);
      this.key = id;
      live.set(id, this);
      this._broadcast({ type: "session", id });
    });
    claude.on("event", (event) => {
      if (event.type === "result") this.lastResult = event;
      this._broadcast({ type: "event", data: event });
      if (event.type === "result") this.emit_result(event);
    });
    claude.on("stderr", (d) => this._broadcast({ type: "stderr", data: d }));
    claude.on("exit", (info) => {
      this._broadcast({ type: "exit", data: info });
      live.delete(this.key);
    });
    claude.on("error", (err) =>
      this._broadcast({ type: "error", data: String(err?.message || err) })
    );
  }

  emit_result(event) {
    // Hook for auto-continue loops (loops.mjs assigns this.autoContinue).
    if (this.autoContinue) this.autoContinue(event);
  }

  subscribe(ws) {
    this.subscribers.add(ws);
    // Replay the assigned session id immediately so a late joiner is in sync.
    if (this.claude.sessionId) {
      this._sendTo(ws, { type: "session", id: this.claude.sessionId });
    }
  }
  unsubscribe(ws) {
    this.subscribers.delete(ws);
  }
  send(text) {
    this.claude.send(text);
  }
  _sendTo(ws, obj) {
    if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(obj));
  }
  _broadcast(obj) {
    const payload = JSON.stringify(obj);
    for (const ws of this.subscribers) {
      if (ws.readyState === ws.OPEN) ws.send(payload);
    }
  }
}

export function startSession({ project, cwd, resumeId = null, autoApprove = true, model = null }) {
  const claude = new ClaudeSession({ cwd, resumeId, autoApprove, model });
  const session = new LiveSession(claude, {
    project,
    cwd,
    autoApprove,
    startedAt: new Date().toISOString(),
  });
  live.set(session.key, session);
  claude.start();
  return session;
}

export function getSession(id) {
  return live.get(id) || null;
}

export function listLiveSessions() {
  return [...live.values()].map((s) => ({
    id: s.claude.sessionId || s.key,
    project: s.meta.project,
    cwd: s.meta.cwd,
    autoApprove: s.meta.autoApprove,
    startedAt: s.meta.startedAt,
    alive: s.claude.alive,
    subscribers: s.subscribers.size,
  }));
}

// --- Persisted transcripts -------------------------------------------------

// List past sessions recorded on disk for a given project directory.
export function listPersistedSessions(cwd) {
  const dir = path.join(claudeProjectsDir, transcriptSlug(cwd));
  let files = [];
  try {
    files = fs.readdirSync(dir).filter((f) => f.endsWith(".jsonl"));
  } catch {
    return [];
  }
  return files
    .map((f) => {
      const full = path.join(dir, f);
      const stat = fs.statSync(full);
      return {
        id: f.replace(/\.jsonl$/, ""),
        file: full,
        modified: stat.mtime.toISOString(),
        sizeBytes: stat.size,
      };
    })
    .sort((a, b) => b.modified.localeCompare(a.modified));
}

// Stream the messages of one persisted transcript (newline-delimited JSON).
export async function readTranscript(cwd, sessionId) {
  const file = path.join(claudeProjectsDir, transcriptSlug(cwd), `${sessionId}.jsonl`);
  const out = [];
  const rl = readline.createInterface({
    input: fs.createReadStream(file, { encoding: "utf8" }),
    crlfDelay: Infinity,
  });
  for await (const line of rl) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch { /* skip malformed */ }
  }
  return out;
}
