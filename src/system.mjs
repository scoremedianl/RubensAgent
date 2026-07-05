// System stats for the app: hardware specs + live CPU / RAM / thermal.
// All read-only, no sudo. Temperature on Apple Silicon needs sudo (powermetrics),
// so we report CPU thermal-throttle level from `pmset -g therm` instead — a
// non-sudo signal for "how hot / is it throttling".

import { execFile } from "node:child_process";
import { promisify } from "node:util";
import os from "node:os";

const run = promisify(execFile);

async function sysctl(key) {
  try { return (await run("sysctl", ["-n", key])).stdout.trim(); } catch { return null; }
}

let specsCache = null;
async function specs() {
  if (specsCache) return specsCache;
  const [chip, model, ncpu, memsize, perfCores, effCores] = await Promise.all([
    sysctl("machdep.cpu.brand_string"),
    sysctl("hw.model"),
    sysctl("hw.ncpu"),
    sysctl("hw.memsize"),
    sysctl("hw.perflevel0.physicalcpu"),
    sysctl("hw.perflevel1.physicalcpu"),
  ]);
  let macos = null;
  try { macos = (await run("sw_vers", ["-productVersion"])).stdout.trim(); } catch { /* ignore */ }
  specsCache = {
    chip: chip || "Unknown",
    model: model || "Mac",
    hostname: os.hostname(),
    cores: Number(ncpu) || os.cpus().length,
    performanceCores: perfCores ? Number(perfCores) : null,
    efficiencyCores: effCores ? Number(effCores) : null,
    totalRamBytes: Number(memsize) || os.totalmem(),
    macos,
  };
  return specsCache;
}

function toBytes(str) {
  const m = String(str).match(/([\d.]+)\s*([KMGT]?)/i);
  if (!m) return 0;
  const n = parseFloat(m[1]);
  const mult = { "": 1, K: 1024, M: 1024 ** 2, G: 1024 ** 3, T: 1024 ** 4 }[(m[2] || "").toUpperCase()];
  return Math.round(n * mult);
}

async function cpuAndMem() {
  // Two samples so the CPU figure reflects the current interval, not since boot.
  let cpuPercent = null, memUsedBytes = null;
  try {
    const { stdout } = await run("top", ["-l", "2", "-s", "1", "-n", "0"], { timeout: 8000 });
    const cpuLines = [...stdout.matchAll(/CPU usage:.*?([\d.]+)%\s*idle/g)];
    if (cpuLines.length) {
      const idle = parseFloat(cpuLines[cpuLines.length - 1][1]);
      cpuPercent = Math.max(0, Math.min(100, +(100 - idle).toFixed(1)));
    }
    const mem = stdout.match(/PhysMem:\s*([\d.]+\s*[KMGT]?)\s*used/i);
    if (mem) memUsedBytes = toBytes(mem[1]);
  } catch { /* leave nulls */ }
  return { cpuPercent, memUsedBytes };
}

async function thermal() {
  try {
    const { stdout } = await run("pmset", ["-g", "therm"], { timeout: 5000 });
    const limit = stdout.match(/CPU_Speed_Limit\s*=\s*(\d+)/);
    if (limit) {
      const pct = Number(limit[1]);
      return { cpuSpeedLimit: pct, throttling: pct < 100 };
    }
  } catch { /* ignore */ }
  return { cpuSpeedLimit: null, throttling: false };
}

export async function systemStats() {
  const [s, cm, th] = await Promise.all([specs(), cpuAndMem(), thermal()]);
  const loadavg = os.loadavg();
  return {
    ...s,
    cpuPercent: cm.cpuPercent,
    load1: +loadavg[0].toFixed(2),
    memUsedBytes: cm.memUsedBytes,
    memPercent: cm.memUsedBytes ? +((cm.memUsedBytes / s.totalRamBytes) * 100).toFixed(1) : null,
    uptimeSeconds: Math.round(os.uptime()),
    thermal: th,
  };
}
