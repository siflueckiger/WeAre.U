/**
 * Unified HTTP + WebSocket server.
 *
 * Serves the built web app (dist/client) and broadcasts the game state to all
 * connected browsers at ~30 Hz. Setup / drag&drop / virtual-input commands come
 * back over the same socket.
 */
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";
import { WebSocketServer, type WebSocket } from "ws";
import type { ClientMessage } from "../shared/types.js";
import type { App } from "./app.js";

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
  ".map": "application/json; charset=utf-8",
};

export interface WebServerOptions {
  port: number;
  /** directory holding the built client (index.html + assets) */
  clientDir: string;
  broadcastHz?: number;
}

export function startWebServer(app: App, opts: WebServerOptions): () => void {
  const clientDir = resolve(opts.clientDir);
  const broadcastHz = opts.broadcastHz ?? 30;

  const server = createServer((req, res) => serveStatic(req, res, clientDir));
  const wss = new WebSocketServer({ server, path: "/ws" });

  const clients = new Set<WebSocket>();
  wss.on("connection", (ws) => {
    clients.add(ws);
    ws.on("message", (data) => {
      try {
        const msg = JSON.parse(data.toString()) as ClientMessage;
        if (msg && typeof msg.type === "string") app.handleClientMessage(msg);
      } catch {
        /* ignore malformed frames */
      }
    });
    ws.on("close", () => clients.delete(ws));
    ws.on("error", () => clients.delete(ws));
    // send an immediate snapshot so the UI paints without waiting a tick
    safeSend(ws, JSON.stringify({ type: "snapshot", ...app.snapshot() }));
  });

  const interval = setInterval(() => {
    if (clients.size === 0) return;
    const payload = JSON.stringify({ type: "snapshot", ...app.snapshot() });
    for (const ws of clients) safeSend(ws, payload);
  }, Math.round(1000 / broadcastHz));

  server.listen(opts.port, () => {
    console.log(`web UI + websocket on http://localhost:${opts.port}`);
  });

  return () => {
    clearInterval(interval);
    for (const ws of clients) ws.close();
    wss.close();
    server.close();
  };
}

function safeSend(ws: WebSocket, payload: string): void {
  if (ws.readyState === ws.OPEN) ws.send(payload);
}

function serveStatic(req: IncomingMessage, res: ServerResponse, clientDir: string): void {
  const urlPath = decodeURIComponent((req.url ?? "/").split("?")[0]);
  let filePath = normalize(join(clientDir, urlPath));

  if (!filePath.startsWith(clientDir)) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }
  if (urlPath === "/" || (existsSync(filePath) && statSync(filePath).isDirectory())) {
    filePath = join(clientDir, "index.html");
  }
  if (!existsSync(filePath)) {
    // SPA fallback
    const index = join(clientDir, "index.html");
    if (existsSync(index)) {
      res.writeHead(200, { "content-type": MIME[".html"] });
      res.end(readFileSync(index));
      return;
    }
    res.writeHead(404);
    res.end("not found -- run `npm run build` first");
    return;
  }
  res.writeHead(200, { "content-type": MIME[extname(filePath)] ?? "application/octet-stream" });
  res.end(readFileSync(filePath));
}
