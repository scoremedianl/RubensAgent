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
import { config } from "./config.mjs";
import { getAgent, isBusy, forgetPane, validModel, DEFAULT_AGENT, AGENTS } from "./agents.mjs";
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
      terms.push(m);
    } catch { /* skip */ }
  }
  terms.sort((a, b) => (b.startedAt || "").localeCompare(a.startedAt || ""));
  return terms;
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

// Type a line: literal text, then Enter (two calls so text is never parsed).
export async function sendTerm(name, text) {
  if (!valid(name)) throw new Error("invalid name");
  await tmux(["send-keys", "-t", name, "-l", String(text)]);
  await tmux(["send-keys", "-t", name, "Enter"]);
  return { sent: true };
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
