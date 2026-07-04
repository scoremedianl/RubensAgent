// Central configuration for the bridge daemon.
// Everything is overridable via environment variables so the launchd plist
// (or a local .env sourced by the wrapper) can tune it without code changes.

import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import crypto from "node:crypto";

const HOME = os.homedir();
const STATE_DIR = path.join(HOME, ".claude-bridge");
fs.mkdirSync(STATE_DIR, { recursive: true });

// Persisted auth token: generated once on first run, reused afterwards.
// The SwiftUI client stores this token and sends it as a Bearer credential.
function loadOrCreateToken() {
  if (process.env.BRIDGE_TOKEN) return process.env.BRIDGE_TOKEN;
  const tokenFile = path.join(STATE_DIR, "token");
  try {
    return fs.readFileSync(tokenFile, "utf8").trim();
  } catch {
    const token = crypto.randomBytes(32).toString("base64url");
    fs.writeFileSync(tokenFile, token, { mode: 0o600 });
    return token;
  }
}

export const config = {
  host: process.env.BRIDGE_HOST || "0.0.0.0", // reachable over the Tailscale interface
  port: Number(process.env.BRIDGE_PORT || 8787),
  token: loadOrCreateToken(),
  projectsDir: process.env.BRIDGE_PROJECTS_DIR || path.join(HOME, "Projects"),
  githubOrg: process.env.BRIDGE_GITHUB_ORG || "Score-Media-B-V",
  claudeBin: process.env.BRIDGE_CLAUDE_BIN || "claude",
  stateDir: STATE_DIR,
  loopsFile: path.join(STATE_DIR, "loops.json"),
  home: HOME,
};

// Claude Code stores per-project transcripts under ~/.claude/projects/<slug>,
// where <slug> is the absolute cwd with every "/" and "." replaced by "-".
export function transcriptSlug(cwd) {
  return cwd.replace(/[/.]/g, "-");
}

export const claudeProjectsDir = path.join(HOME, ".claude", "projects");
