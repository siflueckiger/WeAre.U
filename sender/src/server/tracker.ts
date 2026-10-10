/**
 * Position tracking: UWB frame ingestion, 4-anchor trilateration and filters.
 * Direct port of the math in `sender_py/tracker.py` / `sender/sender.pde`.
 * Coordinates are in mm, X/Y in the field frame.
 */
import {
  DEFAULT_AX,
  DEFAULT_AY,
  TAG0_ID,
  TAG1_ID,
  TRAIL_MAX,
  type Vec2,
} from "../shared/protocol.js";
import { nowMs } from "./clock.js";

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function dist(a: Vec2, b: Vec2): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

export class TagData {
  id: number;
  mask = 0;
  kalman: number[] = new Array(8).fill(0);
  speedMs = 0;
  pos: Vec2 | null = null;
  lastFixMs = 0;
  trail: Vec2[] = [];

  constructor(id: number) {
    this.id = id;
  }
}

export interface TrackerOptions {
  useSpeedClamp?: boolean;
  useEma?: boolean;
  maxSpeedMmS?: number;
  smoothAlpha?: number;
}

export class Tracker {
  tags = new Map<number, TagData>();
  seenIds = new Set<number>();
  frames = 0;
  lastFrameMs = 0;
  ax: number[] = [...DEFAULT_AX];
  ay: number[] = [...DEFAULT_AY];

  useSpeedClamp: boolean;
  useEma: boolean;
  maxSpeedMmS: number;
  smoothAlpha: number;

  constructor(opts: TrackerOptions = {}) {
    this.useSpeedClamp = opts.useSpeedClamp ?? true;
    this.useEma = opts.useEma ?? true;
    this.maxSpeedMmS = opts.maxSpeedMmS ?? 4200;
    this.smoothAlpha = opts.smoothAlpha ?? 0.3;
  }

  setAnchors(ax: number[], ay: number[]): void {
    this.ax = [...ax];
    this.ay = [...ay];
  }

  /** [minX, maxX, minY, maxY] */
  fieldBounds(): [number, number, number, number] {
    return [Math.min(...this.ax), Math.max(...this.ax), Math.min(...this.ay), Math.max(...this.ay)];
  }

  /** Called from the serial thread; ingests one whole frame. */
  handleFrame(tagid: number, mask: number, kalman: number[]): void {
    const now = nowMs();
    this.frames += 1;
    this.lastFrameMs = now;
    this.seenIds.add(tagid);

    let t = this.tags.get(tagid);
    if (t === undefined) {
      t = new TagData(tagid);
      this.tags.set(tagid, t);
    }
    t.mask = mask;
    t.kalman = [...kalman];

    if (tagid !== TAG0_ID && tagid !== TAG1_ID) return;
    let p = this.trilaterate(t);
    if (p === null) return;

    const first = t.pos === null || t.lastFixMs === 0;
    if (!first && this.useSpeedClamp && t.pos !== null) {
      const dt = (now - t.lastFixMs) / 1000;
      const maxD = this.maxSpeedMmS * Math.max(dt, 0.02);
      const dx = p[0] - t.pos[0];
      const dy = p[1] - t.pos[1];
      const d = Math.hypot(dx, dy);
      if (d > maxD && d > 0) {
        p = [t.pos[0] + (dx / d) * maxD, t.pos[1] + (dy / d) * maxD];
      }
    }

    const old = t.pos;
    if (!first && this.useEma && t.pos !== null) {
      t.pos = [lerp(t.pos[0], p[0], this.smoothAlpha), lerp(t.pos[1], p[1], this.smoothAlpha)];
    } else {
      t.pos = p;
    }

    if (!first && old !== null) {
      const dt = (now - t.lastFixMs) / 1000;
      if (dt > 0) t.speedMs = dist(old, t.pos) / dt;
    }

    t.trail.push(t.pos);
    if (t.trail.length > TRAIL_MAX) t.trail.shift();
    t.lastFixMs = now;
  }

  trilaterate(t: TagData): Vec2 | null {
    const { ax, ay } = this;
    let n = 0;
    for (let i = 0; i < 4; i++) {
      if (t.mask & (1 << i) && t.kalman[i] > 0) n++;
    }
    if (n < 3) return null;

    let r = -1;
    for (let i = 0; i < 4; i++) {
      if (t.mask & (1 << i) && t.kalman[i] > 0) {
        r = i;
        break;
      }
    }
    if (r < 0) return null;
    const dr = t.kalman[r];

    let sxx = 0;
    let sxy = 0;
    let syy = 0;
    let sbx = 0;
    let sby = 0;
    for (let j = 0; j < 4; j++) {
      if (j === r || !(t.mask & (1 << j)) || t.kalman[j] <= 0) continue;
      const a = 2 * (ax[j] - ax[r]);
      const b = 2 * (ay[j] - ay[r]);
      const c =
        dr * dr -
        t.kalman[j] * t.kalman[j] -
        (ax[r] * ax[r] + ay[r] * ay[r]) +
        (ax[j] * ax[j] + ay[j] * ay[j]);
      sxx += a * a;
      sxy += a * b;
      syy += b * b;
      sbx += a * c;
      sby += b * c;
    }

    const det = sxx * syy - sxy * sxy;
    if (Math.abs(det) < 1e-6) return null;
    const x = (syy * sbx - sxy * sby) / det;
    const y = (sxx * sby - sxy * sbx) / det;
    return [x, y];
  }
}
