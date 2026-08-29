// Browse every GitHub repo the authenticated user can access (own +
// collaborator + org member) via gh, and clone one into the projects dir.
//
// The gh call pages through the whole API and takes 10-45s, so the result is
// cached: the app gets the full list at once and filters it locally while you
// type. Passing refresh:true re-fetches.

import fs from "node:fs";
import path from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { config } from "./config.mjs";

const run = promisify(execFile);

const TTL_MS = 5 * 60 * 1000;
let cache = null;        // { repos, ghAuthenticated, fetchedAt }
let inFlight = null;     // dedupe concurrent fetches

async function fetchRepos() {
  try {
    const { stdout } = await run(
      "gh",
      ["api", "--paginate",
       "/user/repos?per_page=100&affiliation=owner,collaborator,organization_member&sort=pushed",
       "--jq", ".[] | {fullName: .full_name, name: .name, owner: .owner.login, sshUrl: .ssh_url, pushedAt: .pushed_at, description: .description, private: .private}"],
      { timeout: 90000, maxBuffer: 20 * 1024 * 1024 }
    );
    // --jq streams one JSON object per line.
    const repos = stdout.split("\n").filter(Boolean).map((l) => JSON.parse(l));
    // Dedup (a repo can appear under multiple affiliations) and sort by activity.
    const seen = new Set();
    const deduped = repos.filter((r) => (seen.has(r.fullName) ? false : seen.add(r.fullName)));
    deduped.sort((a, b) => (b.pushedAt || "").localeCompare(a.pushedAt || ""));
    return { repos: deduped, ghAuthenticated: true, fetchedAt: Date.now() };
  } catch {
    return { repos: [], ghAuthenticated: false, fetchedAt: Date.now() };
  }
}

function annotate(repos) {
  const localNames = new Set(
    (fs.existsSync(config.projectsDir) ? fs.readdirSync(config.projectsDir) : []).map((n) => n.toLowerCase())
  );
  return repos.map((r) => ({ ...r, cloned: localNames.has(r.name.toLowerCase()) }));
}

// Returns the full accessible-repo list. `search` still filters server-side so
// the endpoint stays usable directly, but the app fetches once and filters
// locally, which is what makes typing feel instant.
export async function listAccessibleRepos({ search = "", refresh = false } = {}) {
  const stale = !cache || Date.now() - cache.fetchedAt > TTL_MS;
  if (refresh || stale) {
    inFlight ||= fetchRepos().finally(() => { inFlight = null; });
    const fresh = await inFlight;
    // Keep a good cache rather than replacing it with a failed lookup.
    if (fresh.ghAuthenticated || !cache) cache = fresh;
  }
  const q = search.trim().toLowerCase();
  const filtered = q
    ? cache.repos.filter((r) =>
        r.fullName.toLowerCase().includes(q) || (r.description || "").toLowerCase().includes(q))
    : cache.repos;
  return {
    repos: annotate(filtered),
    ghAuthenticated: cache.ghAuthenticated,
    fetchedAt: new Date(cache.fetchedAt).toISOString(),
  };
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
