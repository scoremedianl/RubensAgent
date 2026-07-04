// Manual WS smoke test: connects to the bridge (default: the mini over
// Tailscale), starts a session, sends one prompt, prints events, exits.
//   node test/ws-smoke.mjs <host:port> <token> <cwd> [prompt]
import WebSocket from "ws";

const [target, token, cwd, prompt = "Reply with exactly: BRIDGE OK"] = process.argv.slice(2);
if (!target || !token || !cwd) {
  console.error("usage: node test/ws-smoke.mjs <host:port> <token> <cwd> [prompt]");
  process.exit(1);
}

const ws = new WebSocket(`ws://${target}/ws?token=${encodeURIComponent(token)}`);
let sentPrompt = false;

ws.on("open", () => {
  console.log("[open] connected");
  ws.send(JSON.stringify({ type: "start", cwd, autoApprove: true }));
});
ws.on("message", (raw) => {
  const msg = JSON.parse(raw.toString());
  if (msg.type === "event") {
    const e = msg.data;
    if (e.type === "assistant") {
      for (const b of e.message?.content || []) {
        if (b.type === "text") console.log("[assistant]", b.text);
        if (b.type === "tool_use") console.log("[tool_use]", b.name);
      }
    } else {
      console.log("[event]", e.type, e.subtype || "");
    }
  } else {
    console.log("[msg]", JSON.stringify(msg).slice(0, 200));
  }
  // Once the session id is assigned, send the prompt.
  if ((msg.type === "session" || msg.type === "started") && !sentPrompt) {
    sentPrompt = true;
    setTimeout(() => ws.send(JSON.stringify({ type: "input", text: prompt })), 300);
  }
});
ws.on("close", () => { console.log("[close]"); process.exit(0); });
ws.on("error", (e) => { console.error("[error]", e.message); process.exit(1); });

setTimeout(() => { console.log("[timeout] done"); ws.close(); }, 20000);
