// Ensure a project directory is marked trusted in ~/.claude.json before a
// non-bypass session runs there, and that the global CLAUDE.md @imports are
// approved. This is the same state the interactive trust dialog would set;
// the user explicitly opted into managing it here. Only touches their own
// machine's config, never secrets.

import fs from "node:fs";
import path from "node:path";
import { config } from "./config.mjs";

const claudeJsonPath = path.join(config.home, ".claude.json");

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
