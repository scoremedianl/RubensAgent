// Pre-accept the "do you trust this folder?" dialogs the agent TUIs show on
// first run in a directory. The app mirrors a tmux pane and types into it, so
// a modal the user never asked for just stalls the session. This is the same
// state the interactive dialog would write; it only touches the Mac's own
// config, never secrets.

import fs from "node:fs";
import path from "node:path";
import { config } from "./config.mjs";

const claudeJsonPath = path.join(config.home, ".claude.json");
const codexConfigPath = path.join(config.home, ".codex", "config.toml");

export function ensureTrusted(cwd) {
  let data;
  try {
    data = JSON.parse(fs.readFileSync(claudeJsonPath, "utf8"));
  } catch {
    return false; // no config yet; claude will create it on first run
  }
  data.projects ||= {};
  const entry = (data.projects[cwd] ||= {});
  let changed = false;
  for (const key of [
    "hasTrustDialogAccepted",
    "hasClaudeMdExternalIncludesApproved",
    "hasClaudeMdExternalIncludesWarningShown",
  ]) {
    if (entry[key] !== true) { entry[key] = true; changed = true; }
  }
  if (changed) {
    // Best-effort atomic write to reduce the chance of racing claude's writes.
    const tmp = claudeJsonPath + ".bridge.tmp";
    fs.writeFileSync(tmp, JSON.stringify(data, null, 2));
    fs.renameSync(tmp, claudeJsonPath);
  }
  return true;
}

// Codex records per-directory trust in ~/.codex/config.toml as
//   [projects."/abs/path"]
//   trust_level = "trusted"
// We append the block if this directory isn't in there yet. Appending keeps us
// out of the business of parsing and rewriting the user's whole TOML file.
export function ensureCodexTrusted(cwd) {
  const header = `[projects.${JSON.stringify(cwd)}]`;
  let existing = "";
  try { existing = fs.readFileSync(codexConfigPath, "utf8"); } catch { /* first run */ }
  if (existing.includes(header)) return false;
  fs.mkdirSync(path.dirname(codexConfigPath), { recursive: true });
  const block = `${existing.trim() ? "\n\n" : ""}${header}\ntrust_level = "trusted"\n`;
  fs.appendFileSync(codexConfigPath, block);
  return true;
}

// Dispatch by agent. OpenCode has no per-directory trust prompt.
export function ensureAgentTrusted(agentId, cwd) {
  if (agentId === "claude") return ensureTrusted(cwd);
  if (agentId === "codex") return ensureCodexTrusted(cwd);
  return false;
}
