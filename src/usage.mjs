// Real Claude Code usage/limits via its `/usage` command. Uses the proven tmux
// terminal path (direct spawn from the HTTP handler exits immediately). Start a
// throwaway terminal, type /usage, read the pane, parse the TUI layout, kill.
// Cached briefly so opening the screen doesn't spin one up on every poll.

import fs from "node:fs";
import path from "node:path";
import { startTerm, sendTerm, captureTerm, killTerm } from "./term.mjs";
import { config } from "./config.mjs";

let cache = null;
let cacheAt = 0;
let inflight = null;
const TTL_MS = 60000;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function pickCwd() {
  try {
    const dirs = fs.readdirSync(config.projectsDir, { withFileTypes: true })
      .filter((e) => e.isDirectory() && !e.name.startsWith("."))
      .map((e) => path.join(config.projectsDir, e.name));
    const git = dirs.find((d) => fs.existsSync(path.join(d, ".git")));
    return git || dirs[0] || config.home;
  } catch {
    return config.home;
  }
}

// The TUI renders each limit across three lines:
//   Current session
//   ███████   22% used
//   Resets 1:50pm (Europe/Amsterdam)
function parse(text) {
  const lines = text.split("\n").map((l) => l.trim());
  const limits = [];
  for (let i = 0; i < lines.length; i++) {
    const label = lines[i].match(/^(Current (?:session|week[^%]*?))$/i);
    if (!label) continue;
    let percent = null, resets = null;
    for (let j = i + 1; j < Math.min(i + 4, lines.length); j++) {
      const pm = lines[j].match(/(\d+)%\s*used/i);
      if (pm && percent === null) percent = Number(pm[1]);
      const rm = lines[j].match(/^Resets\s+(.+)$/i);
      if (rm && !resets) resets = rm[1].trim();
    }
    if (percent !== null) limits.push({ label: label[1].trim(), percent, resets });
  }
  const start = text.search(/Current (session|week)/i);
  const raw = start >= 0 ? text.slice(start).trim() : "";
  return { limits, raw };
}

function hasUsage(text) { return /\d+%\s*used/i.test(text); }

async function fetchUsage() {
  const { name } = await startTerm({ cwd: pickCwd() });
  try {
    await sleep(6000);
    await sendTerm(name, "/usage");
    let content = "";
    for (let i = 0; i < 10; i++) {
      await sleep(1500);
      content = (await captureTerm(name, { lines: 200 })).content;
      if (hasUsage(content)) break;
    }
    return parse(content);
  } finally {
    try { await killTerm(name); } catch { /* ignore */ }
  }
}

export async function getClaudeUsage({ force = false } = {}) {
  const now = Date.now();
  if (!force && cache && now - cacheAt < TTL_MS) return { ...cache, cached: true };
  if (inflight) return inflight;
  inflight = fetchUsage().then((result) => {
    if (result.limits.length) { cache = result; cacheAt = Date.now(); }
    inflight = null;
    return { ...result, cached: false };
  }).catch((e) => { inflight = null; return { limits: [], raw: "", error: String(e) }; });
  return inflight;
}
