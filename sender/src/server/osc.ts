/**
 * Minimal OSC-over-UDP client (protocol v2, see docs/osc-protocol.md).
 * Implemented directly on top of node:dgram so the encoding exactly matches the
 * receiver's expectations (python-osc): 4-byte padded strings, big-endian
 * int32/float32 arguments.
 */
import dgram from "node:dgram";
import {
  ADDR_ANCHORS,
  ADDR_ENT_POS,
  ADDR_ENT_REMOVE,
  ADDR_ENT_UPSERT,
  ADDR_GAME_HIT,
  ADDR_GAME_MODE,
  ADDR_GAME_OOB,
  ADDR_GAME_RESULT,
  ADDR_GAME_STATS,
  ADDR_HUD,
  ADDR_P1_POS,
  ADDR_P2_POS,
  ADDR_START_P1,
  ADDR_START_P2,
  TAG0_ID,
  type Vec2,
} from "../shared/protocol.js";
import type { Entity } from "./entities.js";

export type OscArg =
  | { t: "i"; v: number }
  | { t: "f"; v: number }
  | { t: "s"; v: string };

const i = (v: number): OscArg => ({ t: "i", v: Math.trunc(v) });
const f = (v: number): OscArg => ({ t: "f", v });
const s = (v: string): OscArg => ({ t: "s", v });

function pad4(len: number): number {
  return (len + 3) & ~3;
}

function oscString(value: string): Buffer {
  const raw = Buffer.from(value, "ascii");
  const out = Buffer.alloc(pad4(raw.length + 1));
  raw.copy(out, 0);
  return out;
}

function encodeMessage(address: string, args: OscArg[]): Buffer {
  const parts: Buffer[] = [oscString(address)];
  let tags = ",";
  for (const a of args) tags += a.t;
  parts.push(oscString(tags));
  for (const a of args) {
    if (a.t === "i") {
      const b = Buffer.alloc(4);
      b.writeInt32BE(a.v | 0, 0);
      parts.push(b);
    } else if (a.t === "f") {
      const b = Buffer.alloc(4);
      b.writeFloatBE(a.v, 0);
      parts.push(b);
    } else {
      parts.push(oscString(a.v));
    }
  }
  return Buffer.concat(parts);
}

export interface OscClientOptions {
  ip: string;
  port: number;
  enabled?: boolean;
}

export class OscClient {
  readonly ip: string;
  readonly port: number;
  enabled: boolean;
  sent = 0;
  /** Optional hook so the app can mirror hit flashes into the web UI. */
  onHit: ((player: number, seconds: number) => void) | null = null;
  private socket: dgram.Socket | null = null;

  constructor(opts: OscClientOptions) {
    this.ip = opts.ip;
    this.port = opts.port;
    this.enabled = opts.enabled ?? true;
    if (this.enabled) {
      this.socket = dgram.createSocket("udp4");
      this.socket.on("error", () => {
        /* ignore transient UDP errors */
      });
      this.socket.unref();
    }
  }

  close(): void {
    this.socket?.close();
    this.socket = null;
  }

  private send(address: string, args: OscArg[]): void {
    if (!this.enabled || this.socket === null) return;
    try {
      const buf = encodeMessage(address, args);
      this.socket.send(buf, this.port, this.ip, () => {});
      this.sent += 1;
    } catch {
      /* ignore */
    }
  }

  // ---- players ----
  pos(tagid: number, x: number, y: number): void {
    this.send(tagid === TAG0_ID ? ADDR_P1_POS : ADDR_P2_POS, [f(x), f(y)]);
  }

  // ---- game ----
  stats(state: number, timeLeft: number, p1: number, p2: number, winner: number): void {
    this.send(ADDR_GAME_STATS, [i(state), i(timeLeft), i(p1), i(p2), i(winner)]);
  }

  oob(player: number, secondsLeft: number, active: boolean): void {
    this.send(ADDR_GAME_OOB, [i(player), i(secondsLeft), i(active ? 1 : 0)]);
  }

  mode(modeId: string, displayName: string): void {
    this.send(ADDR_GAME_MODE, [s(modeId), s(displayName)]);
  }

  result(title: string, subtitle: string): void {
    this.send(ADDR_GAME_RESULT, [s(title), s(subtitle)]);
  }

  hit(player: number, seconds: number): void {
    this.onHit?.(player, seconds);
    this.send(ADDR_GAME_HIT, [i(player), f(seconds)]);
  }

  hud(lines: string[]): void {
    if (lines.length === 0) return;
    this.send(ADDR_HUD, [s(lines[0] ?? ""), ...lines.slice(1).map(s)]);
  }

  // ---- entities ----
  entUpsert(e: Entity): void {
    this.send(ADDR_ENT_UPSERT, [
      i(e.id),
      s(e.type),
      f(e.x),
      f(e.y),
      f(e.radius),
      i(e.color[0]),
      i(e.color[1]),
      i(e.color[2]),
      s(e.label),
    ]);
  }

  entPos(e: Entity): void {
    this.send(ADDR_ENT_POS, [i(e.id), f(e.x), f(e.y)]);
  }

  entRemove(eid: number): void {
    this.send(ADDR_ENT_REMOVE, [i(eid)]);
  }

  // ---- setup / config ----
  startZones(p1: Vec2, p2: Vec2): void {
    this.send(ADDR_START_P1, [f(p1[0]), f(p1[1])]);
    this.send(ADDR_START_P2, [f(p2[0]), f(p2[1])]);
  }

  anchors(ax: number[], ay: number[]): void {
    this.send(ADDR_ANCHORS, [...ax.map(f), ...ay.map(f)]);
  }
}

export { encodeMessage };
