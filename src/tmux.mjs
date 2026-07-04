// Persistent Claude Code runs backed by tmux. Each run is a `claude` process
// living in its own named tmux session on the Mac, so it survives daemon
// restarts/crashes and can be attached from any terminal
// (`tmux attach -t <name>`). Output is tee'd to a log the app tails.
//
// Safety: we never build a shell string from user input. Commands run via
// execFile (no shell). The prompt is written to a file and read back with
// `$(cat file)`, so it needs no escaping and cannot inject.

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.mjs";

const runProcess = promisify(execFile);
const RUNS_DIR = path.join(config.stateDir, "runs");
fs.mkdirSync(RUNS_DIR, { recursive: true });

const VALID_MODE = new Set(["default", "acceptEdits", "bypassPermissions", "plan"]);

async function tmux(args) {
  try {
    const { stdout } = await runProcess("tmux", args, { timeout: 15000 });
    return stdout;
  } catch (e) {
    // tmux returns non-zero when e.g. no server is running; treat as empty.
    return e.stdout || "";
  }
}

function meta(name) { return path.join(RUNS_DIR, `${name}.json`); }
function logPath(name) { return path.join(RUNS_DIR, `${name}.log`); }

function slug(cwd) {
  return path.basename(cwd).replace(/[^A-Za-z0-9]+/g, "-").toLowerCase().slice(0, 20);
}

// Start a persistent run. The prompt is passed via a file so no shell escaping
// is ever needed. Returns the run metadata.
export async function startRun({ cwd, prompt, model = null, permissionMode = "bypassPermissions", name = null }) {
  if (!cwd || !fs.existsSync(cwd)) throw new Error("cwd does not exist");
  if (!prompt || !String(prompt).trim()) throw new Error("prompt required");
  const mode = VALID_MODE.has(permissionMode) ? permissionMode : "bypassPermissions";
  const runName = (name && /^[A-Za-z0-9_-]+$/.test(name))
    ? name
    : `cc-${slug(cwd)}-${crypto.randomBytes(3).toString("hex")}`;

  const log = logPath(runName);
  const promptFile = path.join(RUNS_DIR, `${runName}.prompt`);
  const scriptFile = path.join(RUNS_DIR, `${runName}.sh`);
  fs.writeFileSync(promptFile, String(prompt));

  const modelArg = model ? `--model ${JSON.stringify(model)}` : "";
  const script = `#!/bin/zsh
source "$HOME/.zprofile" 2>/dev/null
[ -f "$HOME/.claude-bridge/env" ] && source "$HOME/.claude-bridge/env"
unset ANTHROPIC_API_KEY
cd ${JSON.stringify(cwd)} || exit 1
claude -p "$(cat ${JSON.stringify(promptFile)})" \\
  --output-format stream-json --verbose \\
  --permission-mode ${mode} ${modelArg} 2>&1 | tee ${JSON.stringify(log)}
`;
  fs.writeFileSync(scriptFile, script, { mode: 0o700 });

  await tmux(["new-session", "-d", "-s", runName, "zsh", scriptFile]);
  // Keep the pane after the command finishes so it stays attachable and the
  // final output remains visible.
  await tmux(["set-option", "-t", runName, "remain-on-exit", "on"]);

  const m = {
    name: runName, cwd, prompt: String(prompt), model, permissionMode: mode,
    startedAt: new Date().toISOString(), log,
  };
  fs.writeFileSync(meta(runName), JSON.stringify(m, null, 2));
  return m;
}

async function liveSessionNames() {
  const out = await tmux(["list-sessions", "-F", "#{session_name}"]);
  return new Set(out.split("\n").map((s) => s.trim()).filter(Boolean));
}

export async function listRuns() {
  const live = await liveSessionNames();
  const runs = [];
  for (const f of fs.readdirSync(RUNS_DIR)) {
    if (!f.endsWith(".json")) continue;
    try {
      const m = JSON.parse(fs.readFileSync(path.join(RUNS_DIR, f), "utf8"));
      m.running = live.has(m.name);
      m.attach = `tmux attach -t ${m.name}`;
      try { m.logSize = fs.statSync(m.log).size; } catch { m.logSize = 0; }
      runs.push(m);
    } catch { /* skip */ }
  }
  runs.sort((a, b) => (b.startedAt || "").localeCompare(a.startedAt || ""));
  return runs;
}

// Read a run's log; parse the stream-json lines into events for the app, and
// also return the raw tail for terminal-style viewing.
export function readRun(name, { tailBytes = 200000 } = {}) {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error("invalid run name");
  let raw = "";
  try {
    const buf = fs.readFileSync(logPath(name));
    raw = buf.slice(-tailBytes).toString("utf8");
  } catch { /* no log yet */ }
  const events = [];
  for (const line of raw.split("\n")) {
    const t = line.trim();
    if (!t.startsWith("{")) continue;
    try { events.push(JSON.parse(t)); } catch { /* partial line */ }
  }
  return { name, raw, events };
}

export async function killRun(name) {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error("invalid run name");
  await tmux(["kill-session", "-t", name]);
  return { killed: name };
}

// Send a line of input to a running session (e.g. answer a prompt).
export async function sendKeys(name, text) {
  if (!/^[A-Za-z0-9_-]+$/.test(name)) throw new Error("invalid run name");
  await tmux(["send-keys", "-t", name, String(text), "Enter"]);
  return { sent: true };
}
