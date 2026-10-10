/**
 * Engine: shared state machine, round timer, out-of-bounds and entity sync.
 * The engine owns WAIT -> READY -> PLAYING -> GAMEOVER. Modes implement only the
 * round content via `modes/base.ts`. Ported from `sender_py/engine.py`.
 */
import {
  STATE_GAMEOVER,
  STATE_NAMES,
  STATE_PLAYING,
  STATE_READY,
  STATE_WAIT,
  START_ZONE_RADIUS_MM,
  TAG0_ID,
  TAG1_ID,
  type GameState,
  type Vec2,
} from "../shared/protocol.js";
import { nowMs } from "./clock.js";
import type { EntityManager } from "./entities.js";
import type { GameMode } from "./modes/base.js";
import { CoinHunt } from "./modes/coinHunt.js";
import type { OscClient } from "./osc.js";
import type { TagData, Tracker } from "./tracker.js";

export class GameEngine {
  static READY_S = 3;
  static GAMEOVER_S = 10;
  static GAME_TIME_S = 30;
  static OOB_MARGIN_MM = 400;
  static OOB_TIMEOUT_S = 5;
  static OSC_GAME_INTERVAL_MS = 100;

  osc: OscClient;
  tracker: Tracker;
  entities: EntityManager;
  p1Start: Vec2;
  p2Start: Vec2;

  state: GameState = STATE_WAIT;
  timeLeft = 0;
  stateEnteredMs = nowMs();
  lastTickMs = nowMs();
  lastGameOscMs = 0;
  oobCountdown: [number, number] = [GameEngine.OOB_TIMEOUT_S, GameEngine.OOB_TIMEOUT_S];
  oobActive: [boolean, boolean] = [false, false];
  roundWinner = -1;

  modes: GameMode[];
  modeIndex = 0;
  mode: GameMode;

  constructor(osc: OscClient, tracker: Tracker, entities: EntityManager, p1Start: Vec2, p2Start: Vec2) {
    this.osc = osc;
    this.tracker = tracker;
    this.entities = entities;
    this.p1Start = p1Start;
    this.p2Start = p2Start;
    this.modes = [new CoinHunt(this)];
    this.mode = this.modes[0];
  }

  // ============================ helpers ============================
  get tags(): Map<number, TagData> {
    return this.tracker.tags;
  }

  fieldBounds(): [number, number, number, number] {
    return this.tracker.fieldBounds();
  }

  inZone(tag: TagData | undefined, zone: Vec2): boolean {
    if (tag === undefined || tag.pos === null) return false;
    return Math.hypot(tag.pos[0] - zone[0], tag.pos[1] - zone[1]) < START_ZONE_RADIUS_MM;
  }

  stateName(): string {
    return STATE_NAMES[this.state] ?? "?";
  }

  // ============================ state machine ============================
  setState(s: GameState): void {
    this.state = s;
    this.stateEnteredMs = nowMs();
    this.lastTickMs = nowMs();
    this.lastGameOscMs = 0; // force immediate /game/stats
    if (s === STATE_PLAYING) {
      this.roundWinner = -1;
      for (let i = 0; i < 2; i++) {
        this.oobCountdown[i] = GameEngine.OOB_TIMEOUT_S;
        this.oobActive[i] = false;
      }
    } else {
      // every non-playing state cleans up
      this.entities.clear();
      for (let i = 0; i < 2; i++) {
        this.oobCountdown[i] = GameEngine.OOB_TIMEOUT_S;
        this.oobActive[i] = false;
      }
      this.timeLeft = s === STATE_READY ? GameEngine.READY_S : 0;
      // reset the winner only when preparing a new round, never on GAMEOVER
      // (a forced winner such as "ran out of lives" must survive)
      if (s === STATE_WAIT || s === STATE_READY) this.roundWinner = -1;
      this.mode.onRoundEnd();
    }
    console.log("game state ->", this.stateName());
  }

  requestEnd(): void {
    if (this.state === STATE_PLAYING) this.setState(STATE_GAMEOVER);
  }

  debugStartRound(): void {
    this.mode.onRoundStart();
    this.setState(STATE_PLAYING);
  }

  resetRound(): void {
    this.setState(STATE_WAIT);
  }

  nextMode(): void {
    if (this.modes.length <= 1) {
      this.entities.clear();
      this.mode.onRoundEnd();
      this.setState(STATE_WAIT);
      this.sendModeOsc();
      console.log("mode reset ->", this.mode.displayName);
      return;
    }
    this.modeIndex = (this.modeIndex + 1) % this.modes.length;
    this.mode = this.modes[this.modeIndex];
    this.entities.clear();
    this.mode.onModeEnter();
    this.setState(STATE_WAIT);
    this.sendModeOsc();
  }

  setModeById(modeId: string): void {
    for (let idx = 0; idx < this.modes.length; idx++) {
      if (this.modes[idx].id === modeId) {
        this.modeIndex = idx;
        this.mode = this.modes[idx];
        return;
      }
    }
  }

  // ============================ per-frame ============================
  update(): void {
    const t0 = this.tags.get(TAG0_ID);
    const t1 = this.tags.get(TAG1_ID);

    if (this.state === STATE_WAIT) {
      this.timeLeft = 0;
      if (this.inZone(t0, this.p1Start) && this.inZone(t1, this.p2Start)) {
        this.setState(STATE_READY);
      }
    } else if (this.state === STATE_READY) {
      this.timeLeft = Math.max(
        0,
        GameEngine.READY_S - (nowMs() - this.stateEnteredMs) / 1000,
      );
      if (!this.inZone(t0, this.p1Start) || !this.inZone(t1, this.p2Start)) {
        this.setState(STATE_WAIT);
      } else if (this.timeLeft <= 0) {
        this.mode.onRoundStart();
        this.setState(STATE_PLAYING);
      }
    } else if (this.state === STATE_PLAYING) {
      this.timeLeft = Math.max(
        0,
        GameEngine.GAME_TIME_S - (nowMs() - this.stateEnteredMs) / 1000,
      );
      const now = nowMs();
      let dt = (now - this.lastTickMs) / 1000;
      this.lastTickMs = now;
      dt = Math.max(0, Math.min(dt, 0.25));
      this.mode.update(dt);
      this.updateOob(dt);
      if (this.timeLeft <= 0) this.setState(STATE_GAMEOVER);
    } else if (this.state === STATE_GAMEOVER) {
      if (nowMs() - this.stateEnteredMs > GameEngine.GAMEOVER_S * 1000) {
        this.setState(STATE_WAIT);
      }
    }
  }

  updateOob(dt: number): void {
    const b = this.fieldBounds();
    for (let i = 0; i < 2; i++) {
      const tag = this.tags.get(i === 0 ? TAG0_ID : TAG1_ID);
      if (tag === undefined || tag.pos === null) {
        this.oobCountdown[i] = GameEngine.OOB_TIMEOUT_S;
        this.oobActive[i] = false;
        continue;
      }
      const [x, y] = tag.pos;
      const outside =
        x < b[0] - GameEngine.OOB_MARGIN_MM ||
        x > b[1] + GameEngine.OOB_MARGIN_MM ||
        y < b[2] - GameEngine.OOB_MARGIN_MM ||
        y > b[3] + GameEngine.OOB_MARGIN_MM;
      if (outside) {
        this.oobCountdown[i] -= dt;
        this.oobActive[i] = true;
        if (this.oobCountdown[i] <= 0) {
          this.oobCountdown[i] = 0;
          this.mode.onPlayerOut(i);
          return;
        }
      } else {
        this.oobCountdown[i] = GameEngine.OOB_TIMEOUT_S;
        this.oobActive[i] = false;
      }
    }
  }

  // ============================ OSC ============================
  sendModeOsc(): void {
    this.osc.mode(this.mode.id, this.mode.displayName);
  }

  sendStartZones(): void {
    this.osc.startZones(this.p1Start, this.p2Start);
  }

  sendAnchors(): void {
    this.osc.anchors(this.tracker.ax, this.tracker.ay);
  }

  sendGameOsc(): void {
    if (nowMs() - this.lastGameOscMs < GameEngine.OSC_GAME_INTERVAL_MS) return;
    this.lastGameOscMs = nowMs();

    const sc = this.mode.scores();
    const tl =
      this.state === STATE_READY
        ? Math.floor(this.timeLeft + 0.999)
        : Math.floor(this.timeLeft);
    this.osc.stats(this.state, tl, sc[0], sc[1], this.roundWinner);
    for (let i = 0; i < 2; i++) {
      this.osc.oob(i, Math.floor(this.oobCountdown[i] + 0.999), this.oobActive[i]);
    }

    if (this.state === STATE_GAMEOVER) this.sendResultOsc();
    if (this.state === STATE_PLAYING) this.osc.hud(this.mode.hudLines());
    this.sendEntitiesOsc();
  }

  sendResultOsc(): void {
    const rt = this.mode.resultText();
    const title = rt ? rt[0] : "GAME OVER";
    const subtitle = rt && rt.length > 1 ? rt[1] : this.defaultSubtitle();
    this.osc.result(title, subtitle);
  }

  defaultSubtitle(): string {
    if (this.roundWinner === 1) return "SPIELER 1 GEWINNT!";
    if (this.roundWinner === 2) return "SPIELER 2 GEWINNT!";
    return "UNENTSCHIEDEN!";
  }

  sendEntitiesOsc(): void {
    for (const eid of this.entities.removedIds) this.osc.entRemove(eid);
    this.entities.removedIds.length = 0;
    for (const e of this.entities.values()) {
      if (!e.visible) continue;
      if (e.needsUpsert) {
        this.osc.entUpsert(e);
        e.needsUpsert = false;
      }
      this.osc.entPos(e);
    }
  }

  centerValue(): string {
    if (this.state === STATE_WAIT) {
      const both =
        this.inZone(this.tags.get(TAG0_ID), this.p1Start) &&
        this.inZone(this.tags.get(TAG1_ID), this.p2Start);
      return both ? "STARTING" : "WAITING";
    }
    if (this.state === STATE_READY) return String(Math.max(1, Math.floor(this.timeLeft + 0.999)));
    if (this.state === STATE_PLAYING) return `${Math.floor(this.timeLeft)}s`;
    return "GAME OVER";
  }
}
