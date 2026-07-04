// Bearer-token auth. The daemon only listens on the Tailscale/LAN interface,
// but we still require a token so a stray device on the tailnet can't drive it.

import crypto from "node:crypto";
import { config } from "./config.mjs";

function safeEqual(a, b) {
  const ab = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (ab.length !== bb.length) return false;
  return crypto.timingSafeEqual(ab, bb);
}

// Accepts the token from either the Authorization header (REST) or a
// `token` query parameter (WebSocket, which can't set custom headers easily).
export function extractToken(req) {
  const header = req.headers["authorization"];
  if (header && header.startsWith("Bearer ")) return header.slice(7).trim();
  try {
    const url = new URL(req.url, "http://localhost");
    const q = url.searchParams.get("token");
    if (q) return q;
  } catch {
    /* ignore malformed URL */
  }
  return null;
}

export function isAuthorized(req) {
  const token = extractToken(req);
  return token != null && safeEqual(token, config.token);
}
