#!/usr/bin/env node
/**
 * WeAre.U Node sender entry point.
 *
 * Runs UWB tracking, the game engine, OSC output to the Pi VR headsets and an
 * optional browser operator UI.
 *
 * Usage:
 *   node dist/server/main.js                 # web UI on http://localhost:3000
 *   node dist/server/main.js --sim           # virtual players on (no hardware)
 *   node dist/server/main.js --headless      # daemon, no web UI
 *   node dist/server/main.js --ip 192.168.1.106 --target-port 8000
 */
import { parseArgs } from "node:util";
import { resolve } from "node:path";
import { App, type AppArgs } from "./app.js";
import { startWebServer } from "./wsServer.js";

function main(): void {
  const { values } = parseArgs({
    options: {
      headless: { type: "boolean", default: false },
      sim: { type: "boolean", default: false },
      ip: { type: "string", default: "192.168.1.106" },
      "target-port": { type: "string", default: "8000" },
      "port-hint": { type: "string", default: "usbmodem" },
      "web-port": { type: "string", default: "3000" },
      fps: { type: "string", default: "60" },
      help: { type: "boolean", short: "h", default: false },
    },
    allowPositionals: false,
  });

  if (values.help) {
    console.log(
      [
        "WeAre.U Node sender",
        "",
        "  --headless          run as a daemon (no web UI)",
        "  --sim               start with virtual players (WASD / arrows)",
        "  --ip <addr>         receiver OSC target IP (default 192.168.1.106)",
        "  --target-port <n>   receiver OSC port (default 8000)",
        "  --port-hint <s>     serial port substring (default usbmodem)",
        "  --web-port <n>      web UI port (default 3000)",
        "  --fps <n>           engine tick rate (default 60)",
      ].join("\n"),
    );
    return;
  }

  const args: AppArgs = {
    headless: values.headless as boolean,
    sim: values.sim as boolean,
    ip: values.ip as string,
    targetPort: Number.parseInt(values["target-port"] as string, 10) || 8000,
    portHint: values["port-hint"] as string,
    webPort: Number.parseInt(values["web-port"] as string, 10) || 3000,
    fps: Number.parseInt(values.fps as string, 10) || 60,
  };

  const app = new App(args);
  console.log(`OSC -> ${args.ip}:${args.targetPort}`);
  app.start();

  let stopWeb: (() => void) | null = null;
  if (!args.headless) {
    stopWeb = startWebServer(app, {
      port: args.webPort,
      clientDir: resolve(process.cwd(), "dist/client"),
      broadcastHz: Math.min(60, args.fps),
    });
  } else {
    console.log("headless mode: no web UI");
  }

  const tickMs = Math.round(1000 / args.fps);
  const timer = setInterval(() => app.update(), tickMs);

  let shuttingDown = false;
  const shutdown = (): void => {
    if (shuttingDown) return;
    shuttingDown = true;
    clearInterval(timer);
    stopWeb?.();
    app.shutdown();
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);
}

main();
