// Shared "memory" MD files that every Claude Code session loads.
// The global ~/.claude/CLAUDE.md @imports the files in ~/.claude/memory/.
// The app only views/edits these; they live on the Mac, not in the app.

import fs from "node:fs";
import path from "node:path";
import { config } from "./config.mjs";

const claudeDir = path.join(config.home, ".claude");
const memoryDir = path.join(claudeDir, "memory");

// A memory "name" is either the special "CLAUDE.md" (the global root file) or a
// bare *.md filename inside the memory dir. Reject anything path-y.
function resolve(name) {
  if (name === "CLAUDE.md") return path.join(claudeDir, "CLAUDE.md");
  if (!/^[A-Za-z0-9._-]+\.md$/.test(name) || name.includes("..")) {
    throw new Error("invalid memory name");
  }
  return path.join(memoryDir, name);
}

export function listMemory() {
  fs.mkdirSync(memoryDir, { recursive: true });
  const files = [];
  const root = path.join(claudeDir, "CLAUDE.md");
  if (fs.existsSync(root)) {
    files.push({ name: "CLAUDE.md", root: true, sizeBytes: fs.statSync(root).size });
  }
  for (const f of fs.readdirSync(memoryDir)) {
    if (!f.endsWith(".md")) continue;
    files.push({ name: f, root: false, sizeBytes: fs.statSync(path.join(memoryDir, f)).size });
  }
  return files;
}

export function readMemory(name) {
  return fs.readFileSync(resolve(name), "utf8");
}

export function writeMemory(name, content) {
  const p = resolve(name);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, String(content ?? ""));
  return { name, sizeBytes: Buffer.byteLength(String(content ?? "")) };
}

export function deleteMemory(name) {
  if (name === "CLAUDE.md") throw new Error("cannot delete the root file");
  fs.rmSync(resolve(name));
  return { deleted: name };
}
