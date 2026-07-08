// Save an attachment/photo sent from the app to a file on the Mac, so a message
// to Claude can reference its path (Claude Code reads files, including images).

import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { config } from "./config.mjs";

const UPLOAD_DIR = path.join(config.stateDir, "uploads");
fs.mkdirSync(UPLOAD_DIR, { recursive: true });

export function saveUpload(filename, dataBase64) {
  if (!dataBase64) throw new Error("no data");
  const safe = (String(filename || "file").split(/[\\/]/).pop() || "file")
    .replace(/[^A-Za-z0-9._-]/g, "_")
    .slice(-60) || "file";
  const name = `${Date.now()}-${crypto.randomBytes(3).toString("hex")}-${safe}`;
  const dest = path.join(UPLOAD_DIR, name);
  const buf = Buffer.from(String(dataBase64), "base64");
  fs.writeFileSync(dest, buf);
  return { path: dest, filename: safe, bytes: buf.length };
}
