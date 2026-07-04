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

export async function checkout(cwd, branch) {
  assertRepo(cwd);
  if (!/^[A-Za-z0-9._\/-]+$/.test(branch)) throw new Error("invalid branch name");
  const out = await git(["checkout", branch], cwd);
  return { ok: true, branch, output: out.trim() };
}
