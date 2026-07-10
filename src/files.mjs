// Project file browser. All operations are confined to the projects directory
// so the app can browse/open files the AI creates and drop files into a folder.

import fs from "node:fs";
import path from "node:path";
import { config } from "./config.mjs";

const ROOT = path.resolve(config.projectsDir);

// Resolve a path and refuse anything outside the projects root.
function safe(p) {
  const resolved = path.resolve(p || ROOT);
  if (resolved !== ROOT && !resolved.startsWith(ROOT + path.sep)) {
    throw new Error("path outside projects");
  }
  return resolved;
}

const IMAGE_EXT = new Set([".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".heic"]);

export function listDir(dirPath) {
  const dir = safe(dirPath);
  const items = [];
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === ".git") continue; // skip the huge git dir
    const full = path.join(dir, e.name);
    let size = 0, modified = null;
    try { const st = fs.statSync(full); size = st.size; modified = st.mtime.toISOString(); } catch { /* ignore */ }
    items.push({ name: e.name, path: full, isDir: e.isDirectory(), size, modified });
  }
  items.sort((a, b) => (a.isDir === b.isDir ? a.name.localeCompare(b.name) : (a.isDir ? -1 : 1)));
  return { path: dir, parent: dir === ROOT ? null : path.dirname(dir), items };
}

export function readFile(filePath, { maxBytes = 400000 } = {}) {
  const p = safe(filePath);
  const st = fs.statSync(p);
  const ext = path.extname(p).toLowerCase();
  if (IMAGE_EXT.has(ext)) {
    if (st.size > 6 * 1024 * 1024) return { path: p, kind: "image", tooLarge: true, size: st.size };
    return { path: p, kind: "image", ext, size: st.size, dataBase64: fs.readFileSync(p).toString("base64") };
  }
  const buf = fs.readFileSync(p);
  const truncated = buf.length > maxBytes;
  return { path: p, kind: "text", size: st.size, truncated, content: buf.slice(0, maxBytes).toString("utf8") };
}

export function writeInto(dirPath, filename, dataBase64) {
  const dir = safe(dirPath);
  if (!fs.statSync(dir).isDirectory()) throw new Error("not a directory");
  const name = (String(filename || "file").split(/[\\/]/).pop() || "file")
    .replace(/[^A-Za-z0-9._ -]/g, "_").slice(-80) || "file";
  const dest = path.join(dir, name);
  fs.writeFileSync(dest, Buffer.from(String(dataBase64), "base64"));
  return { path: dest, name };
}

export function makeDir(dirPath, name) {
  const dir = safe(dirPath);
  const clean = String(name || "").replace(/[^A-Za-z0-9._ -]/g, "_").trim();
  if (!clean) throw new Error("invalid name");
  const dest = safe(path.join(dir, clean));
  fs.mkdirSync(dest, { recursive: true });
  return { path: dest };
}
