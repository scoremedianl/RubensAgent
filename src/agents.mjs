// Registry of the coding agents the bridge can run in a tmux terminal.
//
// Every agent is a full-screen TUI that we drive exactly the same way (see
// term.mjs): launch it in a detached tmux session, mirror the pane with
// capture-pane, type into it with send-keys. The only things that differ per
// agent are the launch flags, how "busy" looks in its footer, and how you
// check whether it is logged in — so that is all this file describes.
//
// Availability (installed / logged in) is probed on a timer, never inside an
// HTTP request handler: spawning these binaries straight from a request has
// been seen to exit immediately (see CLAUDE.md), and a login probe should
// never make the app wait.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

// Models are passed through to a CLI flag, so keep them to a safe charset.
export function validModel(m) {
  return typeof m === "string" && /^[A-Za-z0-9._\/@:-]{1,120}$/.test(m);
}

// Run a command through a login shell so it sees the same PATH the user has
// (nvm, homebrew). Returns { ok, out } and never throws.
//
// stdout AND stderr, always: `codex login status` prints "Logged in using
// ChatGPT" on *stderr*, so reading stdout alone made a signed-in account look
// unreadable while a signed-out one (which also exits non-zero) parsed fine.
async function shell(command, timeout = 20000) {
  try {
    const { stdout, stderr } = await run("/bin/zsh", ["-lc", command], { timeout });
    return { ok: true, out: `${stdout}\n${stderr}`.trim() };
  } catch (e) {
    return { ok: false, out: `${e.stdout || ""}\n${e.stderr || e.message || ""}`.trim() };
  }
}

// These CLIs colour their output; match on the text, not the escape codes.
function plain(s) { return String(s).replace(/\x1b\[[0-9;]*[A-Za-z]/g, ""); }

export const AGENTS = {
  claude: {
    id: "claude",
    label: "Claude Code",
    bin: "claude",
    // `claude --continue` resumes the most recent conversation in this cwd.
    argv: ({ model, resume }) => [
      "--dangerously-skip-permissions",
      ...(resume ? ["--continue"] : []),
      ...(model ? ["--model", model] : []),
    ],
    // Claude's TUI only shows this hint while it is actually working.
    busy: /esc to interrupt/i,
    busyByChange: false,
    // Claude submits reliably on the Enter that follows the typed text.
    submitNeedsVerify: false,
    // Auth lives in the macOS keychain; a plain `claude auth status` over SSH
    // is keychain-blind and lies, so we don't probe it (see CLAUDE.md).
    checkAuth: null,
    models: null, // static list, supplied by the app
  },

  opencode: {
    id: "opencode",
    label: "OpenCode",
    bin: "opencode",
    argv: ({ model, resume }) => [
      "--auto", // auto-approve permissions that aren't explicitly denied
      ...(resume ? ["--continue"] : []),
      ...(model ? ["-m", model] : []),
    ],
    busy: /esc to interrupt|esc interrupt/i,
    // OpenCode's composer sits several lines above its status bar, so the
    // "is it still unsent?" check can't see it — and OpenCode submitted
    // reliably in testing anyway. Leave it off rather than pretend to verify.
    submitNeedsVerify: false,
    // The footer wording while OpenCode works hasn't been confirmed against a
    // live provider yet, so we also treat a changing pane as "working" rather
    // than guess a string and silently never show the spinner.
    busyByChange: true,
    checkAuth: async () => {
      const { out } = await shell("opencode auth list");
      // `auth list` ends with "N credentials" — 0 means nothing is connected,
      // and the TUI will just show "Connect provider". If that line is absent
      // the command didn't do what we expect, which is NOT the same as being
      // logged out — say so rather than accusing the user of not signing in.
      const m = plain(out).match(/(\d+)\s+credentials?/i);
      if (!m) return { known: false, detail: "Could not read `opencode auth list`." };
      return {
        known: true,
        authenticated: Number(m[1]) > 0,
        detail: Number(m[1]) > 0 ? null : "No provider connected — run `opencode auth login` on the Mac.",
      };
    },
    // `opencode models` also lists the free Zen models when nothing is
    // connected, so this is only consulted once a provider exists.
    listModels: async () => {
      const { ok, out } = await shell("opencode models", 30000);
      if (!ok) return [];
      return plain(out)
        .split("\n")
        .map((l) => l.trim())
        .filter((l) => /^[A-Za-z0-9._-]+\/[A-Za-z0-9._\/-]+$/.test(l))
        .slice(0, 1000); // the app filters locally, so send them all
    },
  },

  codex: {
    id: "codex",
    label: "Codex",
    bin: "codex",
    // `resume --last` is a subcommand and must come before the flags.
    argv: ({ model, resume }) => [
      ...(resume ? ["resume", "--last"] : []),
      "--dangerously-bypass-approvals-and-sandbox",
      ...(model ? ["-m", model] : []),
    ],
    busy: /esc to interrupt|esc again to interrupt/i,
    busyByChange: true, // footer wording unconfirmed until an account is signed in
    // Codex intermittently swallows the Enter that immediately follows typed
    // text, leaving the message sitting unsent in the composer. Verified: a
    // second Enter submits it, and an Enter on an empty composer does nothing.
    submitNeedsVerify: true,
    checkAuth: async () => {
      // `codex login status` exits 1 when signed out, so the exit code alone
      // can't tell "signed out" from "the command broke" — match the text.
      const text = plain((await shell("codex login status")).out);
      if (/not logged in|logged out/i.test(text)) {
        return { known: true, authenticated: false, detail: "Not logged in — run `codex login` on the Mac." };
      }
      if (/logged in/i.test(text)) return { known: true, authenticated: true, detail: null };
      return { known: false, detail: "Could not read `codex login status`." };
    },
    // Codex has no "list models" command; the model is switched inside the TUI
    // with /model, so we only offer the account default.
    listModels: null,
  },
};

export const DEFAULT_AGENT = "claude";

export function getAgent(id) {
  return AGENTS[id] || AGENTS[DEFAULT_AGENT];
}

// Remember the last pane we saw per session. Two uses:
//  - agents whose "working" footer we haven't confirmed are judged by whether
//    their screen is moving (a TUI at a prompt is static; a working one isn't);
//  - a pane that changed is the only honest "last active" signal we have.
//    tmux's own #{session_activity} only advances while a client is attached,
//    and nothing is ever attached here, so it stays equal to session_created.
const lastPane = new Map();
const lastChange = new Map();   // session name -> epoch ms of last pane change

export function isBusy(agentId, sessionName, pane) {
  const spec = getAgent(agentId);
  const previous = lastPane.get(sessionName);
  const changed = previous !== undefined && previous !== pane;
  if (changed) lastChange.set(sessionName, Date.now());
  lastPane.set(sessionName, pane);

  if (spec.busy.test(pane)) return true;
  if (!spec.busyByChange) return false;
  return changed;
}

/// Epoch ms when this session's screen last changed, or undefined if it hasn't
/// changed since the daemon started.
export function lastActivityAt(sessionName) { return lastChange.get(sessionName); }

/// Seed from persisted metadata so a daemon restart doesn't reset every
/// session's "last active" back to when it was started.
export function seedActivity(sessionName, epochMs) {
  if (!epochMs) return;
  const known = lastChange.get(sessionName) || 0;
  if (epochMs > known) lastChange.set(sessionName, epochMs);
}

export function forgetPane(sessionName) {
  lastPane.delete(sessionName);
  lastChange.delete(sessionName);
}

// --- availability probe ----------------------------------------------------

let cache = null;
let probing = null;

async function probeOne(a) {
  const { ok, out } = await shell(`command -v ${a.bin}`, 10000);
  if (!ok || !out) {
    return { id: a.id, label: a.label, installed: false, authenticated: false, authKnown: true, models: [], detail: `${a.bin} not installed` };
  }
  const entry = {
    id: a.id, label: a.label, installed: true, path: out,
    authenticated: true, authKnown: true, models: [], detail: null,
  };
  if (a.checkAuth) {
    const r = await a.checkAuth();
    // known:false means the probe itself failed. We still let you start a
    // session — the agent may well be fine — but we don't claim it's signed in.
    entry.authKnown = r.known !== false;
    entry.authenticated = entry.authKnown ? r.authenticated : true;
    entry.detail = r.detail || null;
  }
  if (a.listModels && entry.authenticated) {
    entry.models = await a.listModels();
  }
  return entry;
}

export async function probeAgents() {
  if (probing) return probing;
  probing = (async () => {
    const out = {};
    for (const a of Object.values(AGENTS)) {
      try { out[a.id] = await probeOne(a); }
      catch (e) { out[a.id] = { id: a.id, label: a.label, installed: false, authenticated: false, authKnown: false, models: [], detail: String(e.message || e) }; }
    }
    cache = { agents: Object.values(out), checkedAt: new Date().toISOString() };
    return cache;
  })();
  try { return await probing; } finally { probing = null; }
}

// Served instantly from cache; the first call kicks off a probe in the
// background and returns "unknown yet" rather than blocking the app.
export function agentStatus() {
  if (!cache) {
    probeAgents();
    return {
      agents: Object.values(AGENTS).map((a) => ({
        id: a.id, label: a.label, installed: false, authenticated: false, authKnown: true, models: [], detail: "checking…",
      })),
      checkedAt: null,
      pending: true,
    };
  }
  return { ...cache, pending: false };
}

export function startAgentProbing() {
  probeAgents();
  const t = setInterval(() => probeAgents(), 5 * 60 * 1000);
  t.unref?.();
}
