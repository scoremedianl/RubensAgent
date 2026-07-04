// Interactive Claude terminal sessions backed by tmux, mirrored to the app.
// The daemon (running in the GUI/login-keychain context) creates a tmux
// session that runs `claude` interactively in full-auto. The app shows a live
// mirror via `tmux capture-pane` and types via `send-keys`. Because the
// session lives in tmux, it survives app close AND daemon restart, and is
// always the true live state — no event replay to get out of sync.
//
// Safety: execFile only (no shell string building). cwd/model validated; the
// launch command is written to a script file, never interpolated into a shell.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.mjs";

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

export async function startTerm({ cwd, model = null, name = null }) {
  if (!cwd || !fs.existsSync(cwd)) throw new Error("cwd does not exist");
  const runName = (name && valid(name)) ? name : `cc-term-${slug(cwd)}-${crypto.randomBytes(3).toString("hex")}`;
  const scriptFile = path.join(TERM_DIR, `${runName}.sh`);
  const modelArg = model ? `--model ${JSON.stringify(model)}` : "";
  const script = `#!/bin/zsh
source "$HOME/.zprofile" 2>/dev/null
[ -f "$HOME/.claude-bridge/env" ] && source "$HOME/.claude-bridge/env"
unset ANTHROPIC_API_KEY
cd ${JSON.stringify(cwd)} || exit 1
exec claude --dangerously-skip-permissions ${modelArg}
`;
  fs.writeFileSync(scriptFile, script, { mode: 0o700 });

  await tmux(["new-session", "-d", "-s", runName, "-x", "130", "-y", "42", "zsh", scriptFile]);
  await tmux(["set-option", "-t", runName, "remain-on-exit", "on"]);

  const m = { name: runName, cwd, model, startedAt: new Date().toISOString(), attach: `tmux attach -t ${runName}` };
  fs.writeFileSync(metaPath(runName), JSON.stringify(m, null, 2));
  return m;
}

async function liveNames() {
  const out = await tmux(["list-sessions", "-F", "#{session_name}"]);
  return new Set(out.split("\n").map((s) => s.trim()).filter(Boolean));
}

export async function listTerms() {
  const live = await liveNames();
  const terms = [];
  for (const f of fs.readdirSync(TERM_DIR)) {
    if (!f.endsWith(".json")) continue;
    try {
      const m = JSON.parse(fs.readFileSync(path.join(TERM_DIR, f), "utf8"));
      m.running = live.has(m.name);
      terms.push(m);
    } catch { /* skip */ }
  }
  terms.sort((a, b) => (b.startedAt || "").localeCompare(a.startedAt || ""));
  return terms;
}

// Live mirror of the current pane (visible screen + a little scrollback).
export async function captureTerm(name, { lines = 60 } = {}) {
  if (!valid(name)) throw new Error("invalid name");
  const content = await tmux(["capture-pane", "-t", name, "-p", "-S", `-${lines}`]);
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
  return { killed: name };
}
