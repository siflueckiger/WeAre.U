/**
 * Virtual play mode: two keyboard/Web-driven players fed into the same TagData
 * pipeline the serial frames use. Debug/test without UWB hardware.
 * Ported from `sender_py/virtual_tags.py`.
 */
import { TAG0_ID, TAG1_ID, TRAIL_MAX, type Vec2 } from "../shared/protocol.js";
import { nowMs } from "./clock.js";
import { TagData, type Tracker } from "./tracker.js";
import type { OscClient } from "./osc.js";
import type { VirtualKey } from "../shared/types.js";

export const VIRTUAL_SPEED_MM_S = 1500;

export class VirtualTags {
  on = false;
  private keys = new Set<VirtualKey>();
  private lastMs = 0;

  constructor(
    private tracker: Tracker,
    private osc: OscClient,
    private p1Start: Vec2,
    private p2Start: Vec2,
  ) {}

  setKeys(keys: VirtualKey[]): void {
    this.keys = new Set(keys);
  }

  isKeyHeld(key: VirtualKey): boolean {
    return this.keys.has(key);
  }

  enable(): void {
    this.on = true;
    this.ensurePlayers();
    console.log("Virtual play: ON (WASD = P1, arrows = P2)");
  }

  disable(): void {
    this.on = false;
    this.clearPlayers();
    this.keys.clear();
    this.lastMs = 0;
    console.log("Virtual play: OFF");
  }

  setZones(p1: Vec2, p2: Vec2): void {
    this.p1Start = p1;
    this.p2Start = p2;
  }

  ensurePlayers(): void {
    this.lastMs = 0;
    for (const [tid, start] of [
      [TAG0_ID, this.p1Start],
      [TAG1_ID, this.p2Start],
    ] as [number, Vec2][]) {
      let t = this.tracker.tags.get(tid);
      if (t === undefined) {
        t = new TagData(tid);
        this.tracker.tags.set(tid, t);
      }
      if (t.pos === null) {
        t.pos = [start[0], start[1]];
        t.speedMs = 0;
        t.lastFixMs = nowMs();
        this.osc.pos(tid, t.pos[0], t.pos[1]);
      }
    }
  }

  clearPlayers(): void {
    for (const tid of [TAG0_ID, TAG1_ID]) {
      const t = this.tracker.tags.get(tid);
      if (t === undefined) continue;
      t.pos = null;
      t.trail = [];
      t.speedMs = 0;
      t.lastFixMs = 0;
    }
  }

  resetPlayers(): void {
    for (const [tid, start] of [
      [TAG0_ID, this.p1Start],
      [TAG1_ID, this.p2Start],
    ] as [number, Vec2][]) {
      let t = this.tracker.tags.get(tid);
      if (t === undefined) {
        t = new TagData(tid);
        this.tracker.tags.set(tid, t);
      }
      t.pos = [start[0], start[1]];
      t.trail = [];
      t.speedMs = 0;
      t.lastFixMs = nowMs();
      this.osc.pos(tid, t.pos[0], t.pos[1]);
    }
    this.lastMs = 0;
  }

  update(): void {
    if (!this.on) return;
    const now = nowMs();
    if (this.lastMs === 0) this.lastMs = now;
    let dt = (now - this.lastMs) / 1000;
    this.lastMs = now;
    dt = Math.max(0, Math.min(dt, 0.25));
    this.tracker.lastFrameMs = now; // keep "no data" warning quiet
    this.move(TAG0_ID, "w", "s", "a", "d", dt, now);
    this.move(TAG1_ID, "up", "down", "left", "right", dt, now);
  }

  private move(
    tid: number,
    up: VirtualKey,
    down: VirtualKey,
    left: VirtualKey,
    right: VirtualKey,
    dt: number,
    now: number,
  ): void {
    let dx = 0;
    let dy = 0;
    if (this.keys.has(up)) dy += 1;
    if (this.keys.has(down)) dy -= 1;
    if (this.keys.has(left)) dx -= 1;
    if (this.keys.has(right)) dx += 1;
    const t = this.tracker.tags.get(tid);
    if (t === undefined || t.pos === null) return;
    let speed = 0;
    if (dx !== 0 || dy !== 0) {
      const mag = Math.hypot(dx, dy);
      dx /= mag;
      dy /= mag;
      speed = VIRTUAL_SPEED_MM_S;
      t.pos = [t.pos[0] + dx * speed * dt, t.pos[1] + dy * speed * dt];
    }
    t.speedMs = speed;
    t.trail.push(t.pos);
    if (t.trail.length > TRAIL_MAX) t.trail.shift();
    t.lastFixMs = now;
    this.osc.pos(tid, t.pos[0], t.pos[1]);
  }
}
