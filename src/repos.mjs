// Browse every GitHub repo the authenticated user can access (own +
// collaborator + org member) via gh, and clone one into the projects dir.

import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.mjs";

const run = promisify(execFile);

// List accessible repos. Uses the GitHub API through gh (paginated). Returns
// [] with ghAuthenticated:false when gh isn't logged in, so the app can prompt.
export async function listAccessibleRepos({ search = "" } = {}) {
  let repos;
  try {
    const { stdout } = await run(
      "gh",
      ["api", "--paginate",
       "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member&sort=pushed",
       "--jq", ".[] | {fullName: .full_name, name: .name, owner: .owner.login, sshUrl: .ssh_url, pushedAt: .pushed_at, description: .description, private: .private}"],
      { timeout: 45000, maxBuffer: 20 * 1024 * 1024 }
    );
    // --jq streams one JSON object per line.
    repos = stdout.split("\n").filter(Boolean).map((l) => JSON.parse(l));
  } catch (e) {
    return { repos: [], ghAuthenticated: false };
  }
  const localNames = new Set(
    (fs.existsSync(config.projectsDir) ? fs.readdirSync(config.projectsDir) : []).map((n) => n.toLowerCase())
  );
  const q = search.trim().toLowerCase();
  const out = repos
    .filter((r) => !q || r.fullName.toLowerCase().includes(q) || (r.description || "").toLowerCase().includes(q))
    .map((r) => ({ ...r, cloned: localNames.has(r.name.toLowerCase()) }));
  // Dedup (a repo can appear under multiple affiliations) and sort by activity.
  const seen = new Set();
  const deduped = out.filter((r) => (seen.has(r.fullName) ? false : seen.add(r.fullName)));
  deduped.sort((a, b) => (b.pushedAt || "").localeCompare(a.pushedAt || ""));
  return { repos: deduped, ghAuthenticated: true };
}

export async function cloneAccessible(fullName) {
  if (!/^[A-Za-z0-9._-]+\/[A-Za-z0-9._-]+$/.test(fullName)) {
    throw new Error("invalid repo (expected owner/name)");
  }
  const name = fullName.split("/")[1];
  const dest = path.join(config.projectsDir, name);
  if (fs.existsSync(dest)) return { name, path: dest, cloned: false, reason: "already present" };
  const url = `git@github.com:${fullName}.git`;
  await run("git", ["clone", url, dest], { timeout: 300000 });
  return { name, path: dest, cloned: true };
}
