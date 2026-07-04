// Project discovery and on-demand cloning from the configured GitHub org.

import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.mjs";

const pexecFile = promisify(execFile);

async function git(args, cwd) {
  const { stdout } = await pexecFile("git", args, { cwd, timeout: 20000 });
  return stdout.trim();
}

// List every git repository directly under the projects directory,
// with a bit of metadata for the picker in the app.
export async function listProjects() {
  let entries = [];
  try {
    entries = fs.readdirSync(config.projectsDir, { withFileTypes: true });
  } catch {
    return [];
  }
  const projects = [];
  for (const e of entries) {
    if (!e.isDirectory()) continue;
    const dir = path.join(config.projectsDir, e.name);
    if (!fs.existsSync(path.join(dir, ".git"))) continue;
    const p = { name: e.name, path: dir };
    try {
      p.branch = await git(["rev-parse", "--abbrev-ref", "HEAD"], dir);
      p.remote = await git(["remote", "get-url", "origin"], dir).catch(() => null);
      p.lastCommit = await git(
        ["log", "-1", "--format=%h %s (%cr)"],
        dir
      ).catch(() => null);
    } catch {
      /* keep partial metadata */
    }
    projects.push(p);
  }
  projects.sort((a, b) => a.name.localeCompare(b.name));
  return projects;
}

// Clone `<org>/<name>` over SSH into the projects directory. Idempotent.
export async function cloneRepo(name) {
  if (!/^[A-Za-z0-9._-]+$/.test(name)) {
    throw new Error(`invalid repo name: ${name}`);
  }
  const dest = path.join(config.projectsDir, name);
  if (fs.existsSync(dest)) {
    return { name, path: dest, cloned: false, reason: "already present" };
  }
  const url = `git@github.com:${config.githubOrg}/${name}.git`;
  await pexecFile("git", ["clone", url, dest], { timeout: 300000 });
  return { name, path: dest, cloned: true };
}

// List repos in the org that are NOT yet cloned locally, using gh if it is
// authenticated. Returns [] (not an error) when gh is unavailable, so the app
// can still function with explicit clone-by-name.
export async function listAvailableRepos() {
  let json;
  try {
    const { stdout } = await pexecFile(
      "gh",
      ["repo", "list", config.githubOrg, "--limit", "200", "--no-archived",
       "--json", "name,sshUrl,pushedAt,description"],
      { timeout: 30000 }
    );
    json = JSON.parse(stdout);
  } catch {
    return { available: [], ghAuthenticated: false };
  }
  const local = new Set(
    (await listProjects()).map((p) => p.name.toLowerCase())
  );
  const available = json
    .filter((r) => !local.has(r.name.toLowerCase()))
    .sort((a, b) => (b.pushedAt || "").localeCompare(a.pushedAt || ""));
  return { available, ghAuthenticated: true };
}
