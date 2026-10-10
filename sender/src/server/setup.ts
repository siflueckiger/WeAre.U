/**
 * Interactive setup / calibration logic (TAB).
 * Anchor distances -> auto-layout, start zones via live tag capture or drag,
 * persistence in config.json. Ported from `sender_py/setup_mode.py`.
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import {
  DEFAULT_AX,
  DEFAULT_AY,
  TAG0_ID,
  TAG1_ID,
  type Vec2,
} from "../shared/protocol.js";
import type { GameEngine } from "./engine.js";

export const D_PAIRS: [number, number][] = [
  [0, 1],
  [0, 2],
  [0, 3],
  [1, 2],
  [1, 3],
  [2, 3],
];
export const D_NAMES = ["A0-A1", "A0-A2", "A0-A3", "A1-A2", "A1-A3", "A2-A3"];
export const LAYOUT_WARN_MM = 200;

const CONFIG_FILE = process.env.WEAREU_CONFIG ?? resolve(process.cwd(), "config.json");

export class SetupMode {
  private engine: GameEngine;
  anchorD: number[] = [0, 0, 0, 0, 0, 0];
  status = "";

  constructor(engine: GameEngine) {
    this.engine = engine;
    this.computeD();
  }

  get configFile(): string {
    return CONFIG_FILE;
  }

  // ============================ geometry ============================
  computeD(): void {
    const { ax, ay } = this.engine.tracker;
    for (let i = 0; i < D_PAIRS.length; i++) {
      const [a, b] = D_PAIRS[i];
      this.anchorD[i] = Math.hypot(ax[a] - ax[b], ay[a] - ay[b]);
    }
  }

  applyLayout(): void {
    const [d01, d02, d03, d12, d13, d23] = this.anchorD;
    if (d01 < 1) {
      this.status = "A0-A1 zu klein";
      return;
    }
    const ax = [0, d01, 0, 0];
    const ay = [0, 0, 0, 0];
    const x2 = (d02 * d02 - d12 * d12 + d01 * d01) / (2 * d01);
    let y2sq = d02 * d02 - x2 * x2;
    const x3 = (d03 * d03 - d13 * d13 + d01 * d01) / (2 * d01);
    let y3sq = d03 * d03 - x3 * x3;
    this.status = "Layout berechnet";
    if (y2sq < 0) {
      this.status = "WARNUNG: A2 inkonsistent - geklemmt";
      y2sq = 0;
    }
    if (y3sq < 0) {
      this.status = "WARNUNG: A3 inkonsistent - geklemmt";
      y3sq = 0;
    }
    ax[2] = x2;
    ay[2] = Math.sqrt(y2sq);
    ax[3] = x3;
    ay[3] = Math.sqrt(y3sq);
    this.engine.tracker.setAnchors(ax, ay);
    const d23c = Math.hypot(ax[2] - ax[3], ay[2] - ay[3]);
    if (Math.abs(d23c - d23) > LAYOUT_WARN_MM) {
      this.status = `WARNUNG: A2-A3-Check (${d23c.toFixed(0)} vs ${d23.toFixed(0)})`;
    }
    this.computeD();
    this.engine.sendAnchors();
  }

  standardLayout(): void {
    this.engine.tracker.setAnchors([...DEFAULT_AX], [...DEFAULT_AY]);
    this.computeD();
    this.engine.sendAnchors();
    this.status = "Standard-Layout 3x7m gesetzt";
  }

  captureZone(player: number): void {
    const tid = player === 0 ? TAG0_ID : TAG1_ID;
    const t = this.engine.tracker.tags.get(tid);
    if (t === undefined || t.pos === null) {
      this.status = `P${player + 1}: noch kein Positions-Fix`;
      return;
    }
    if (player === 0) this.engine.p1Start = [t.pos[0], t.pos[1]];
    else this.engine.p2Start = [t.pos[0], t.pos[1]];
    this.engine.sendStartZones();
    this.status = `P${player + 1}-Start -> (${t.pos[0].toFixed(0)}, ${t.pos[1].toFixed(0)})`;
  }

  setAnchor(index: number, p: Vec2, commit: boolean): void {
    if (index < 0 || index > 3) return;
    this.engine.tracker.ax[index] = p[0];
    this.engine.tracker.ay[index] = p[1];
    if (commit) {
      this.computeD();
      this.engine.sendAnchors();
    }
  }

  setZone(player: number, p: Vec2, commit: boolean): void {
    if (player === 0) this.engine.p1Start = [p[0], p[1]];
    else this.engine.p2Start = [p[0], p[1]];
    if (commit) this.engine.sendStartZones();
  }

  // ============================ config ============================
  loadConfig(): void {
    if (!existsSync(CONFIG_FILE)) {
      console.log("no config.json -- using built-in defaults");
      this.computeD();
      return;
    }
    try {
      const j = JSON.parse(readFileSync(CONFIG_FILE, "utf8"));
      if (Array.isArray(j.AX) && j.AX.length === 4 && Array.isArray(j.AY) && j.AY.length === 4) {
        this.engine.tracker.setAnchors(j.AX, j.AY);
      }
      if (Array.isArray(j.D) && j.D.length === 6) {
        this.anchorD = j.D.map(Number);
      } else {
        this.computeD();
      }
      if (Array.isArray(j.P1_START) && j.P1_START.length === 2) {
        this.engine.p1Start = [Number(j.P1_START[0]), Number(j.P1_START[1])];
      }
      if (Array.isArray(j.P2_START) && j.P2_START.length === 2) {
        this.engine.p2Start = [Number(j.P2_START[0]), Number(j.P2_START[1])];
      }
      if (typeof j.MODE === "string") this.engine.setModeById(j.MODE);
      console.log("config loaded:", CONFIG_FILE);
    } catch (e) {
      console.log("config load failed:", e);
      this.computeD();
    }
  }

  saveConfig(): void {
    try {
      const j = {
        AX: this.engine.tracker.ax,
        AY: this.engine.tracker.ay,
        D: this.anchorD,
        P1_START: [...this.engine.p1Start],
        P2_START: [...this.engine.p2Start],
        MODE: this.engine.mode.id,
      };
      writeFileSync(CONFIG_FILE, JSON.stringify(j, null, 2));
      this.status = "Config gespeichert";
      console.log("config saved:", CONFIG_FILE);
    } catch (e) {
      this.status = "Speichern fehlgeschlagen";
      console.log("config save failed:", e);
    }
  }
}
