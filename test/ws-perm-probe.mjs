// Probe the permission flow THROUGH the daemon (which has Keychain/login
// access). Starts a default-mode session, asks for a tool, dumps raw events
// so we can see the permission control request shape.
//   node test/ws-perm-probe.mjs <host:port> <token> <cwd>
import WebSocket from "ws";
const [target, token, cwd] = process.argv.slice(2);
const ws = new WebSocket(`ws://${target}/ws?token=${encodeURIComponent(token)}`);
let sent = false;
ws.on("open", () => {
  ws.send(JSON.stringify({ type: "start", cwd, permissionMode: "default" }));
});
ws.on("message", (raw) => {
  const msg = JSON.parse(raw.toString());
  if (msg.type === "event") {
    const e = msg.data;
    console.log("EVENT", e.type, e.subtype || "");
    if (e.type !== "assistant" && e.type !== "system") {
      console.log("   RAW", JSON.stringify(e).slice(0, 500));
    }
  } else {
    console.log("MSG", JSON.stringify(msg).slice(0, 300));
  }
  if (msg.type === "session" && !sent) {
    sent = true;
    setTimeout(() => {
      console.log(">>> sending prompt");
      ws.send(JSON.stringify({ type: "input",
        text: "Use the Bash tool to run: echo hello-from-probe" }));
    }, 1500);
  }
});
ws.on("error", (e) => { console.error("ERR", e.message); process.exit(1); });
setTimeout(() => { ws.close(); process.exit(0); }, 45000);
