// Git operations exposed to the app: inspect branches, pull, switch branch.
// All run over the project's existing origin (SSH key on the mini).

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import fs from "node:fs";
import path from "node:path";

const pexecFile = promisify(execFile);

function assertRepo(cwd) {
  if (!cwd || !fs.existsSync(path.join(cwd, ".git"))) {
    throw new Error("not a git repository");
  }
}

async function git(args, cwd) {
  const { stdout } = await pexecFile("git", args, { cwd, timeout: 120000 });
  return stdout;
}

export async function branchInfo(cwd) {
  assertRepo(cwd);
  const current = (await git(["rev-parse", "--abbrev-ref", "HEAD"], cwd)).trim();
  // Local + remote branches, de-duplicated and cleaned.
  const raw = await git(
    ["for-each-ref", "--format=%(refname:short)", "refs/heads", "refs/remotes"],
    cwd
  );
  const branches = [...new Set(
    raw.split("\n").map((b) => b.trim())
      .filter((b) => b && !b.endsWith("/HEAD"))
      .map((b) => b.replace(/^origin\//, ""))
  )].filter((b) => b !== "HEAD").sort();
  return { current, branches };
}

export async function pull(cwd) {
  assertRepo(cwd);
  const out = await git(["pull", "--ff-only"], cwd);
  return { ok: true, output: out.trim() };
}

export async function checkout(cwd, branch, { hard = false } = {}) {
  assertRepo(cwd);
  if (!/^[A-Za-z0-9._\/-]+$/.test(branch)) throw new Error("invalid branch name");
  if (hard) {
    // Force-switch, discarding local (uncommitted) changes to tracked files.
    try {
      const out = await git(["checkout", "-f", branch], cwd);
      return { ok: true, branch, hard: true, output: out.trim() };
    } catch (first) {
      const out = await git(["checkout", "-f", "-B", branch, `origin/${branch}`], cwd);
      return { ok: true, branch, hard: true, output: out.trim() };
    }
  }
  try {
    // Local branch, or git's own guess of a unique origin/<branch>.
    const out = await git(["checkout", branch], cwd);
    return { ok: true, branch, output: out.trim() };
  } catch (first) {
    // Explicit fallback: create a local tracking branch from origin/<branch>.
    try {
      const out = await git(["checkout", "-b", branch, `origin/${branch}`], cwd);
      return { ok: true, branch, output: out.trim() };
    } catch (second) {
      const msg = (second.stderr || first.stderr || first.message || "").trim();
      throw new Error(msg || `cannot switch to ${branch}`);
    }
  }
}
