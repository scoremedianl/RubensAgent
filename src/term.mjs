// Interactive coding-agent terminal sessions backed by tmux, mirrored to the
// app. The daemon (running in the GUI/login-keychain context) creates a tmux
// session that runs an agent TUI — Claude Code, OpenCode or Codex — in
// full-auto. The app shows a live mirror via `tmux capture-pane` and types via
// `send-keys`. Because the session lives in tmux, it survives app close AND
// daemon restart, and is always the true live state — no event replay to get
// out of sync.
//
// Which binary and which flags each agent needs lives in agents.mjs; this file
// only knows how to put one in a tmux session and mirror it.
//
// Safety: execFile only (no shell string building) for tmux itself. The launch
// command goes into a script file with every argument single-quoted, so agent
// names, cwds and model ids can never break out into the shell.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config, claudeProjectsDir, transcriptSlug } from "./config.mjs";
import {
  getAgent, isBusy, forgetPane, validModel, DEFAULT_AGENT, AGENTS,
  lastActivityAt, seedActivity,
} from "./agents.mjs";
import { ensureAgentTrusted } from "./trust.mjs";

const runProcess = promisify(execFile);
const TERM_DIR = path.join(config.stateDir, "terms");
fs.mkdirSync(TERM_DIR, { recursive: true });

async function tmux(args) {
  try {
    const { stdout } = await runProcess("tmux", args, { timeout: 15000 });
    return stdout;
  } catch (e) {
    return e.stdout || "";
  }
}

// Same, but the failure is not swallowed. Sending input must never report
// success when tmux refused it — `send-keys -l` rejects a large paste with
// "command too long" and the app used to be told the message went through.
async function tmuxStrict(args) {
  const { stdout } = await runProcess("tmux", args, { timeout: 30000, maxBuffer: 8 * 1024 * 1024 });
  return stdout;
}

function metaPath(name) { return path.join(TERM_DIR, `${name}.json`); }
function slug(cwd) {
  return path.basename(cwd).replace(/[^A-Za-z0-9]+/g, "-").toLowerCase().slice(0, 20);
}
function valid(name) { return /^[A-Za-z0-9_-]+$/.test(name); }

// Single-quote for /bin/zsh: everything is literal inside '…', and a literal
// quote is written by closing, escaping, reopening.
function q(s) { return `'${String(s).replace(/'/g, `'\\''`)}'`; }

export async function startTerm({ cwd, model = null, name = null, resume = false, agent = DEFAULT_AGENT }) {
  if (!cwd || !fs.existsSync(cwd)) throw new Error("cwd does not exist");
  if (!AGENTS[agent]) throw new Error(`unknown agent: ${agent}`);
  if (model && !validModel(model)) throw new Error("invalid model");
  const spec = getAgent(agent);

  // Pre-accept the agent's own "do you trust this folder?" prompt, which would
  // otherwise block the session behind a dialog the app can't see.
  try { ensureAgentTrusted(spec.id, cwd); } catch { /* best effort */ }

  const runName = (name && valid(name))
    ? name
    : `cc-${spec.id}-${slug(cwd)}-${crypto.randomBytes(3).toString("hex")}`;
  const scriptFile = path.join(TERM_DIR, `${runName}.sh`);
  const argv = spec.argv({ model, resume }).map(q).join(" ");
  const script = `#!/bin/zsh
source "$HOME/.zprofile" 2>/dev/null
[ -f "$HOME/.claude-bridge/env" ] && source "$HOME/.claude-bridge/env"
unset ANTHROPIC_API_KEY
cd ${q(cwd)} || exit 1
exec ${q(spec.bin)} ${argv}
`;
  fs.writeFileSync(scriptFile, script, { mode: 0o700 });

  await tmux(["new-session", "-d", "-s", runName, "-x", "130", "-y", "42", "zsh", scriptFile]);
  await tmux(["set-option", "-t", runName, "remain-on-exit", "on"]);

  const m = {
    name: runName, cwd, model, agent: spec.id, agentLabel: spec.label,
    startedAt: new Date().toISOString(), attach: `tmux attach -t ${runName}`,
  };
  fs.writeFileSync(metaPath(runName), JSON.stringify(m, null, 2));
  return m;
}

async function liveNames() {
  const out = await tmux(["list-sessions", "-F", "#{session_name}"]);
  return new Set(out.split("\n").map((s) => s.trim()).filter(Boolean));
}

function cleanupFiles(base) {
  for (const ext of [".json", ".sh"]) {
    try { fs.rmSync(path.join(TERM_DIR, `${base}${ext}`)); } catch { /* ignore */ }
  }
}

// Claude writes a transcript per project, so its mtime tells us when a project
// was last worked in — including before this daemon ever ran. That's the only
// retroactive activity signal available, and it's what stops every pre-existing
// session from claiming it was last used the day it started.
function claudeTranscriptActivity(cwd) {
  const dir = path.join(claudeProjectsDir, transcriptSlug(cwd));
  let newest = 0;
  try {
    for (const f of fs.readdirSync(dir)) {
      if (!f.endsWith(".jsonl")) continue;
      const m = fs.statSync(path.join(dir, f)).mtimeMs;
      if (m > newest) newest = m;
    }
  } catch { /* never used */ }
  return newest;
}

// Persisting "last active" on every poll would rewrite a busy session's
// metadata every couple of seconds, so only write it through occasionally.
const PERSIST_EVERY_MS = 60000;
const lastPersisted = new Map();

function persistActivity(meta, epochMs) {
  const previous = lastPersisted.get(meta.name) || 0;
  if (epochMs - previous < PERSIST_EVERY_MS) return;
  lastPersisted.set(meta.name, epochMs);
  try {
    const onDisk = JSON.parse(fs.readFileSync(metaPath(meta.name), "utf8"));
    onDisk.lastActivity = new Date(epochMs).toISOString();
    fs.writeFileSync(metaPath(meta.name), JSON.stringify(onDisk, null, 2));
  } catch { /* the session may have just been killed */ }
}

export async function listTerms() {
  const live = await liveNames();
  const terms = [];
  for (const f of fs.readdirSync(TERM_DIR)) {
    if (!f.endsWith(".json")) continue;
    try {
      const m = JSON.parse(fs.readFileSync(path.join(TERM_DIR, f), "utf8"));
      // Sessions created before agents existed are Claude Code sessions.
      m.agent ||= DEFAULT_AGENT;
      m.agentLabel ||= getAgent(m.agent).label;
      // Carry a restart over: without this every session's "last active"
      // would collapse back to when it was started.
      seedActivity(m.name, Date.parse(m.lastActivity || m.startedAt || 0) || 0);
      if (m.agent === "claude") seedActivity(m.name, claudeTranscriptActivity(m.cwd));
      // Keep dead sessions listed (running:false) so they survive a reboot and
      // can be resumed, instead of vanishing.
      m.running = live.has(m.name);
      m.busy = false;
      if (m.running) {
        // Each TUI advertises "working" differently; agents.mjs knows how.
        try {
          const pane = await tmux(["capture-pane", "-t", m.name, "-p"]);
          m.busy = isBusy(m.agent, m.name, pane);
        } catch { /* ignore */ }
      }
      const active = lastActivityAt(m.name);
      if (active) {
        m.lastActivity = new Date(active).toISOString();
        persistActivity(m, active);
      } else {
        m.lastActivity ||= m.startedAt;
      }
      terms.push(m);
    } catch { /* skip */ }
  }
  // Most recently *used* first — start time says nothing about which session
  // you were just working in.
  terms.sort((a, b) =>
    (b.lastActivity || b.startedAt || "").localeCompare(a.lastActivity || a.startedAt || ""));
  return terms;
}

// Newest activity per project directory, so the project list can be ordered by
// real use across all three agents rather than Claude's transcripts alone.
export function termActivityByCwd() {
  const byCwd = new Map();
  let files = [];
  try { files = fs.readdirSync(TERM_DIR); } catch { return byCwd; }
  for (const f of files) {
    if (!f.endsWith(".json")) continue;
    try {
      const m = JSON.parse(fs.readFileSync(path.join(TERM_DIR, f), "utf8"));
      const when = lastActivityAt(m.name) || Date.parse(m.lastActivity || m.startedAt || 0) || 0;
      if (!when) continue;
      if (when > (byCwd.get(m.cwd) || 0)) byCwd.set(m.cwd, when);
    } catch { /* skip */ }
  }
  return byCwd;
}

// Live mirror of the current pane. We capture just the VISIBLE screen (no
// scrollback) so the content is a fixed-size snapshot of the terminal — it
// doesn't grow, which keeps the app's scroll position stable (no jumping).
export async function captureTerm(name, { lines = 0 } = {}) {
  if (!valid(name)) throw new Error("invalid name");
  const args = ["capture-pane", "-t", name, "-p"];
  if (lines > 0) args.push("-S", `-${lines}`);   // opt-in scrollback
  const content = await tmux(args);
  return { name, content };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Is the text we just typed still sitting unsent in the composer? Once a TUI
// accepts a message it moves it into the transcript above the input, so the
// tail of the pane is where an unsent line shows up.
function stillInComposer(pane, text) {
  const probe = String(text).trim();
  if (!probe) return false;
  const tail = pane.split("\n").filter((l) => l.trim()).slice(-3);
  return tail.some((l) => l.includes(probe));
}

// Anything longer than this, or containing a newline, goes in as a paste.
const PASTE_THRESHOLD = 400;

// A bracketed paste leaves a placeholder in the composer rather than the text
// itself — Claude shows "[Pasted text #1 +39 lines]", Codex "[Pasted Content
// N chars]", OpenCode "[Pasted ~40 lines]".
const PASTE_PLACEHOLDER = /\[pasted/i;

// Deliver the message body to the composer, without submitting it.
//
// `send-keys -l` is fine for a short single line, but it is the wrong tool for
// anything larger: tmux refuses the command outright past roughly 16KB
// ("command too long"), and every newline in the text arrives as a Return,
// which submits the message early and shreds a multi-line paste into one
// message per line. Loading the text into a tmux buffer and pasting it has
// neither problem — measured byte-identical at 2MB in well under a tenth of a
// second — and `-p` wraps it in bracketed-paste markers, which all three TUIs
// recognise and collapse to a single tidy placeholder line.
async function deliver(name, body) {
  if (body.length <= PASTE_THRESHOLD && !body.includes("\n")) {
    await tmuxStrict(["send-keys", "-t", name, "-l", body]);
    return false;
  }
  const file = path.join(TERM_DIR, `.paste-${name}`);
  const buffer = `bridge-${name}`;
  fs.writeFileSync(file, body);
  try {
    await tmuxStrict(["load-buffer", "-b", buffer, file]);
    await tmuxStrict(["paste-buffer", "-d", "-p", "-b", buffer, "-t", name]);
  } finally {
    try { fs.rmSync(file, { force: true }); } catch { /* ignore */ }
  }
  return true;
}

// Put the message in the composer, then press Enter (separate calls, so the
// text is never parsed as keys).
//
// Some TUIs intermittently swallow the Enter that arrives right behind the
// text, leaving the message unsent — observed with Codex. For those agents we
// check the pane and press Enter again; an extra Enter on an empty composer is
// a no-op, so this can't double-send.
export async function sendTerm(name, text) {
  if (!valid(name)) throw new Error("invalid name");
  const body = String(text);
  if (!body) return { sent: false, reason: "empty" };

  const pasted = await deliver(name, body);
  await tmuxStrict(["send-keys", "-t", name, "Enter"]);

  let agent = DEFAULT_AGENT;
  try { agent = JSON.parse(fs.readFileSync(metaPath(name), "utf8")).agent || DEFAULT_AGENT; }
  catch { /* pre-agent session */ }
  if (!getAgent(agent).submitNeedsVerify) return { sent: true, pasted };

  for (let attempt = 0; attempt < 2; attempt++) {
    await sleep(350);
    const pane = await tmux(["capture-pane", "-t", name, "-p"]);
    // After a paste the composer holds a placeholder, not the text we sent.
    const unsent = pasted ? PASTE_PLACEHOLDER.test(tail(pane)) : stillInComposer(pane, body);
    if (!unsent) return { sent: true, pasted, retries: attempt };
    await tmuxStrict(["send-keys", "-t", name, "Enter"]);
  }
  return { sent: true, pasted, retries: 2 };
}

function tail(pane) {
  return pane.split("\n").filter((l) => l.trim()).slice(-3).join("\n");
}

// Send a special key/chord (Enter, Escape, C-c, Up, Down, "S-Tab", …).
export async function sendKey(name, key) {
  if (!valid(name)) throw new Error("invalid name");
  if (!/^[A-Za-z0-9_-]+$/.test(key)) throw new Error("invalid key");
  await tmux(["send-keys", "-t", name, key]);
  return { sent: true };
}

export async function killTerm(name) {
  if (!valid(name)) throw new Error("invalid name");
  await tmux(["kill-session", "-t", name]);
  cleanupFiles(name);   // remove metadata so it doesn't linger in the list
  forgetPane(name);
  return { killed: name };
}

// Resume a stopped session: start a fresh tmux terminal in the same project
// with the agent's own "continue last conversation" flag. Reuses the name and
// the agent so the sidebar entry is continuous.
export async function restoreTerm(name) {
  if (!valid(name)) throw new Error("invalid name");
  let meta;
  try { meta = JSON.parse(fs.readFileSync(metaPath(name), "utf8")); }
  catch { throw new Error("session not found"); }
  return startTerm({
    cwd: meta.cwd, model: meta.model, name,
    agent: meta.agent || DEFAULT_AGENT, resume: true,
  });
}
