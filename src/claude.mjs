// Wraps a single Claude Code process running in headless streaming mode.
//
// We drive the official `claude` CLI with:
//   --print --input-format stream-json --output-format stream-json --verbose
// which gives a bidirectional, newline-delimited JSON protocol: we write user
// messages to stdin and read assistant/tool/result events from stdout. The
// process stays alive across turns, so one ClaudeSession == one conversation.

import { spawn } from "node:child_process";
import { EventEmitter } from "node:events";
import { config } from "./config.mjs";

export class ClaudeSession extends EventEmitter {
  /**
   * @param {object} opts
   * @param {string} opts.cwd          project directory to run in
   * @param {string} [opts.resumeId]   existing Claude session id to continue
   * @param {string} [opts.permissionMode]  one of default | acceptEdits |
   *                 bypassPermissions | plan. Falls back from autoApprove.
   * @param {boolean} [opts.autoApprove]  legacy: true → bypassPermissions
   * @param {string} [opts.model]      optional model override
   */
  constructor({ cwd, resumeId = null, permissionMode = null, autoApprove = true, model = null }) {
    super();
    this.cwd = cwd;
    this.resumeId = resumeId;
    this.permissionMode = permissionMode
      || (autoApprove ? "bypassPermissions" : "default");
    this.model = model;
    this.sessionId = resumeId || null;
    this.proc = null;
    this._stdoutBuf = "";
    this._alive = false;
  }

  start() {
    const args = [
      "--print",
      "--input-format", "stream-json",
      "--output-format", "stream-json",
      "--verbose",
      "--permission-mode", this.permissionMode,
    ];
    if (this.resumeId) args.push("--resume", this.resumeId);
    if (this.model) args.push("--model", this.model);

    this.proc = spawn(config.claudeBin, args, {
      cwd: this.cwd,
      env: { ...process.env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    this._alive = true;

    this.proc.stdout.setEncoding("utf8");
    this.proc.stdout.on("data", (chunk) => this._onStdout(chunk));

    this.proc.stderr.setEncoding("utf8");
    this.proc.stderr.on("data", (d) => this.emit("stderr", d));

    this.proc.on("exit", (code, signal) => {
      this._alive = false;
      this.emit("exit", { code, signal });
    });
    this.proc.on("error", (err) => this.emit("error", err));
    return this;
  }

  _onStdout(chunk) {
    this._stdoutBuf += chunk;
    let idx;
    while ((idx = this._stdoutBuf.indexOf("\n")) >= 0) {
      const line = this._stdoutBuf.slice(0, idx).trim();
      this._stdoutBuf = this._stdoutBuf.slice(idx + 1);
      if (!line) continue;
      let event;
      try {
        event = JSON.parse(line);
      } catch {
        this.emit("raw", line); // non-JSON line, surface for debugging
        continue;
      }
      // The init system event carries the canonical session id.
      if (event.session_id && !this.sessionId) {
        this.sessionId = event.session_id;
        this.emit("session", this.sessionId);
      }
      this.emit("event", event);
    }
  }

  // Send a user turn. Accepts a plain string.
  send(text) {
    if (!this._alive || !this.proc?.stdin.writable) {
      throw new Error("session is not running");
    }
    const msg = {
      type: "user",
      message: { role: "user", content: [{ type: "text", text: String(text) }] },
    };
    this.proc.stdin.write(JSON.stringify(msg) + "\n");
  }

  get alive() {
    return this._alive;
  }

  stop() {
    if (!this.proc) return;
    try {
      this.proc.stdin.end();
    } catch { /* ignore */ }
    // Give it a moment to flush, then force-kill if still around.
    setTimeout(() => {
      if (this._alive) {
        try { this.proc.kill("SIGTERM"); } catch { /* ignore */ }
      }
    }, 1500);
  }
}
