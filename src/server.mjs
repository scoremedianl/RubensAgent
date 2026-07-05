// HTTP + WebSocket entry point for the bridge daemon.
//
// REST covers discovery and management (projects, clone, loops, history).
// A single WebSocket at /ws carries the live, bidirectional session stream.

import http from "node:http";
import { WebSocketServer } from "ws";
import { config } from "./config.mjs";
import { isAuthorized } from "./auth.mjs";
import { listProjects, cloneRepo, listAvailableRepos, createFolder } from "./projects.mjs";
import {
  startSession, getSession, listLiveSessions,
  listPersistedSessions, readTranscript, getUsage,
} from "./sessions.mjs";
import { listMemory, readMemory, writeMemory, deleteMemory } from "./memory.mjs";
import { branchInfo, pull, checkout } from "./git.mjs";
import { startRun, listRuns, readRun, killRun, sendKeys } from "./tmux.mjs";
import { startTerm, listTerms, captureTerm, sendTerm, sendKey, killTerm } from "./term.mjs";
import { systemStats } from "./system.mjs";
import { getClaudeUsage } from "./usage.mjs";
import { listAccessibleRepos, cloneAccessible } from "./repos.mjs";
import {
  listLoops, addLoop, removeLoop, setLoopEnabled, runCronLoop, startScheduler,
  attachAutoContinue,
} from "./loops.mjs";

const VERSION = "0.1.0";

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

async function readBody(req) {
  const chunks = [];
  for await (const c of req) chunks.push(c);
  if (!chunks.length) return {};
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); }
  catch { return {}; }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  const p = url.pathname;
  console.log(`[req] ${req.method} ${p}`);

  // Health is unauthenticated so the app can probe reachability.
  if (p === "/health") {
    return send(res, 200, { ok: true, version: VERSION, projectsDir: config.projectsDir });
  }
  if (!isAuthorized(req)) return send(res, 401, { error: "unauthorized" });

  try {
    if (req.method === "GET" && p === "/projects") {
      return send(res, 200, { projects: await listProjects() });
    }
    if (req.method === "GET" && p === "/projects/available") {
      return send(res, 200, await listAvailableRepos());
    }
    if (req.method === "POST" && p === "/projects/clone") {
      const { name } = await readBody(req);
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, await cloneRepo(name));
    }
    if (req.method === "POST" && p === "/projects/create") {
      const { name } = await readBody(req);
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, createFolder(name));
    }
    if (req.method === "GET" && p === "/sessions") {
      return send(res, 200, { sessions: listLiveSessions() });
    }
    if (req.method === "GET" && p === "/sessions/persisted") {
      const cwd = url.searchParams.get("cwd");
      if (!cwd) return send(res, 400, { error: "cwd required" });
      return send(res, 200, { sessions: listPersistedSessions(cwd) });
    }
    if (req.method === "GET" && p === "/transcript") {
      const cwd = url.searchParams.get("cwd");
      const id = url.searchParams.get("id");
      if (!cwd || !id) return send(res, 400, { error: "cwd and id required" });
      return send(res, 200, { messages: await readTranscript(cwd, id) });
    }
    if (req.method === "GET" && p === "/projects/git/branches") {
      const cwd = url.searchParams.get("cwd");
      if (!cwd) return send(res, 400, { error: "cwd required" });
      return send(res, 200, await branchInfo(cwd));
    }
    if (req.method === "POST" && p === "/projects/git/pull") {
      const { cwd } = await readBody(req);
      if (!cwd) return send(res, 400, { error: "cwd required" });
      return send(res, 200, await pull(cwd));
    }
    if (req.method === "POST" && p === "/projects/git/checkout") {
      const { cwd, branch, hard } = await readBody(req);
      if (!cwd || !branch) return send(res, 400, { error: "cwd and branch required" });
      return send(res, 200, await checkout(cwd, branch, { hard: hard === true }));
    }
    if (req.method === "POST" && p === "/term/start") {
      return send(res, 200, await startTerm(await readBody(req)));
    }
    if (req.method === "GET" && p === "/term/list") {
      return send(res, 200, { terms: await listTerms() });
    }
    if (req.method === "GET" && p === "/term/capture") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      const lines = Number(url.searchParams.get("lines") || 60);
      return send(res, 200, await captureTerm(name, { lines }));
    }
    if (req.method === "POST" && p === "/term/send") {
      const { name, text } = await readBody(req);
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, await sendTerm(name, text || ""));
    }
    if (req.method === "POST" && p === "/term/key") {
      const { name, key } = await readBody(req);
      if (!name || !key) return send(res, 400, { error: "name and key required" });
      return send(res, 200, await sendKey(name, key));
    }
    if (req.method === "DELETE" && p === "/term") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, await killTerm(name));
    }
    if (req.method === "GET" && p === "/runs") {
      return send(res, 200, { runs: await listRuns() });
    }
    if (req.method === "POST" && p === "/runs") {
      return send(res, 200, await startRun(await readBody(req)));
    }
    if (req.method === "GET" && p === "/runs/log") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, readRun(name));
    }
    if (req.method === "POST" && p === "/runs/send") {
      const { name, text } = await readBody(req);
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, await sendKeys(name, text || ""));
    }
    if (req.method === "DELETE" && p === "/runs") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, await killRun(name));
    }
    if (req.method === "GET" && p === "/system") {
      return send(res, 200, await systemStats());
    }
    if (req.method === "GET" && p === "/repos") {
      const search = url.searchParams.get("search") || "";
      return send(res, 200, await listAccessibleRepos({ search }));
    }
    if (req.method === "POST" && p === "/repos/clone") {
      const { fullName } = await readBody(req);
      if (!fullName) return send(res, 400, { error: "fullName required" });
      return send(res, 200, await cloneAccessible(fullName));
    }
    if (req.method === "GET" && p === "/usage") {
      return send(res, 200, getUsage());
    }
    if (req.method === "GET" && p === "/usage/claude") {
      return send(res, 200, await getClaudeUsage({ force: url.searchParams.get("force") === "1" }));
    }
    if (req.method === "GET" && p === "/memory") {
      return send(res, 200, { files: listMemory() });
    }
    if (req.method === "GET" && p === "/memory/file") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, { name, content: readMemory(name) });
    }
    if (req.method === "PUT" && p === "/memory/file") {
      const { name, content } = await readBody(req);
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, writeMemory(name, content));
    }
    if (req.method === "DELETE" && p === "/memory/file") {
      const name = url.searchParams.get("name");
      if (!name) return send(res, 400, { error: "name required" });
      return send(res, 200, deleteMemory(name));
    }
    if (req.method === "GET" && p === "/loops") {
      return send(res, 200, { loops: listLoops() });
    }
    if (req.method === "POST" && p === "/loops") {
      return send(res, 200, addLoop(await readBody(req)));
    }
    if (req.method === "POST" && /^\/loops\/[^/]+\/enable$/.test(p)) {
      const id = p.split("/")[2];
      const { enabled } = await readBody(req);
      return send(res, 200, setLoopEnabled(id, enabled !== false));
    }
    if (req.method === "POST" && /^\/loops\/[^/]+\/run$/.test(p)) {
      runCronLoop(p.split("/")[2]);
      return send(res, 202, { triggered: true });
    }
    if (req.method === "DELETE" && /^\/loops\/[^/]+$/.test(p)) {
      return send(res, 200, removeLoop(p.split("/")[2]));
    }
    return send(res, 404, { error: "not found" });
  } catch (err) {
    return send(res, 500, { error: String(err?.message || err) });
  }
});

// --- WebSocket: live session stream ---------------------------------------

const wss = new WebSocketServer({ noServer: true });

server.on("upgrade", (req, socket, head) => {
  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/ws" || !isAuthorized(req)) {
    socket.write("HTTP/1.1 401 Unauthorized\r\n\r\n");
    socket.destroy();
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => wss.emit("connection", ws, req));
});

wss.on("connection", (ws) => {
  let current = null; // the LiveSession this socket is attached to

  ws.send(JSON.stringify({ type: "ready", version: VERSION }));

  ws.on("message", (raw) => {
    let msg;
    try { msg = JSON.parse(raw.toString()); }
    catch { return ws.send(JSON.stringify({ type: "error", data: "bad json" })); }

    try {
      switch (msg.type) {
        case "start": {
          if (!msg.cwd) throw new Error("cwd required");
          current = startSession({
            project: msg.project || null,
            cwd: msg.cwd,
            resumeId: msg.resumeId || null,
            permissionMode: msg.permissionMode || null,
            autoApprove: msg.autoApprove !== false,
            model: msg.model || null,
          });
          current.subscribe(ws);
          ws.send(JSON.stringify({ type: "started", key: current.key }));
          break;
        }
        case "attach": {
          const s = getSession(msg.id);
          if (!s) throw new Error("session not found");
          if (current) current.unsubscribe(ws);
          current = s;
          current.subscribe(ws);
          ws.send(JSON.stringify({ type: "attached", id: msg.id }));
          break;
        }
        case "input": {
          if (!current) throw new Error("no active session");
          current.send(msg.text || "");
          break;
        }
        case "auto-continue": {
          if (!current) throw new Error("no active session");
          const r = attachAutoContinue(current, msg);
          ws.send(JSON.stringify({ type: "auto-continue", ...r }));
          break;
        }
        case "stop": {
          if (current) current.claude.stop();
          break;
        }
        default:
          ws.send(JSON.stringify({ type: "error", data: `unknown type: ${msg.type}` }));
      }
    } catch (err) {
      ws.send(JSON.stringify({ type: "error", data: String(err?.message || err) }));
    }
  });

  ws.on("close", () => { if (current) current.unsubscribe(ws); });
});

startScheduler();
server.listen(config.port, config.host, () => {
  console.log(`[bridge] listening on ${config.host}:${config.port}`);
  console.log(`[bridge] projects: ${config.projectsDir}`);
  console.log(`[bridge] token:    ${config.token}`);
});
