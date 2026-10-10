/**
 * Application orchestrator: owns the tracker, engine, OSC output, serial input
 * and the virtual-play fallback. The WebSocket server drives it and reads
 * snapshots from it.
 */
import {
  STATE_GAMEOVER,
  STATE_READY,
  STATE_WAIT,
  TAG0_ID,
  TAG1_ID,
  type GameState,
  type Vec2,
} from "../shared/protocol.js";
import type {
  ClientMessage,
  EntityView,
  GameView,
  PlayerView,
  StatusView,
  VirtualKey,
} from "../shared/types.js";
import { nowMs } from "./clock.js";
import { EntityManager } from "./entities.js";
import { GameEngine } from "./engine.js";
import { OscClient } from "./osc.js";
import { SerialReader } from "./serial.js";
import { SetupMode } from "./setup.js";
import { Tracker } from "./tracker.js";
import { VirtualTags } from "./virtualTags.js";

export interface AppArgs {
  headless: boolean;
  sim: boolean;
  ip: string;
  targetPort: number;
  portHint: string;
  webPort: number;
  fps: number;
}

export type AppMode = "game" | "setup";

export class App {
  readonly args: AppArgs;
  tracker: Tracker;
  osc: OscClient;
  entities: EntityManager;
  engine: GameEngine;
  setup: SetupMode;
  virtual: VirtualTags;
  serial: SerialReader;

  appMode: AppMode = "game";
  serialStatus = "searching";
  private fps = 0;
  private fpsFrames = 0;
  private fpsLastMs = nowMs();

  constructor(args: AppArgs) {
    this.args = args;
    this.tracker = new Tracker();
    this.osc = new OscClient({ ip: args.ip, port: args.targetPort, enabled: true });
    this.entities = new EntityManager();
    this.engine = new GameEngine(
      this.osc,
      this.tracker,
      this.entities,
      [3000, 1500],
      [4000, 1500],
    );
    this.virtual = new VirtualTags(
      this.tracker,
      this.osc,
      this.engine.p1Start,
      this.engine.p2Start,
    );
    this.setup = new SetupMode(this.engine);
    this.serial = new SerialReader({
      onFrame: (f) => this.onFrame(f.tagid, f.mask, f.kalman),
      onStatus: (t) => {
        this.serialStatus = t;
      },
      portHint: args.portHint,
    });
  }

  // ============================ startup ============================
  start(): void {
    this.setup.loadConfig();
    this.virtual.setZones(this.engine.p1Start, this.engine.p2Start);
    this.engine.mode.onModeEnter();
    this.engine.sendModeOsc();
    this.engine.sendStartZones();
    this.engine.sendAnchors();
    if (this.args.sim) this.virtual.enable();
    this.serial.start();
  }

  shutdown(): void {
    this.serial.stop();
    this.osc.close();
  }

  // ============================ serial ============================
  onFrame(tagid: number, mask: number, kalman: number[]): void {
    if (this.virtual.on) return;
    this.tracker.handleFrame(tagid, mask, kalman);
    if (tagid === TAG0_ID || tagid === TAG1_ID) {
      const t = this.tracker.tags.get(tagid);
      if (t !== undefined && t.pos !== null) this.osc.pos(tagid, t.pos[0], t.pos[1]);
    }
  }

  // ============================ per-frame ============================
  update(): void {
    this.virtual.update();
    if (this.appMode === "game") {
      this.engine.update();
      this.engine.sendGameOsc();
    }
    this.tickFps();
  }

  private tickFps(): void {
    this.fpsFrames += 1;
    const now = nowMs();
    if (now - this.fpsLastMs >= 1000) {
      this.fps = Math.round((this.fpsFrames * 1000) / (now - this.fpsLastMs));
      this.fpsFrames = 0;
      this.fpsLastMs = now;
    }
  }

  // ============================ app mode ============================
  setAppMode(mode: AppMode): void {
    if (mode === this.appMode) return;
    if (mode === "setup") {
      this.engine.resetRound();
      this.appMode = "setup";
    } else {
      this.appMode = "game";
      this.engine.resetRound();
      this.engine.sendModeOsc();
      this.engine.sendStartZones();
      this.engine.sendAnchors();
    }
  }

  toggleAppMode(): void {
    this.setAppMode(this.appMode === "game" ? "setup" : "game");
  }

  // ============================ commands ============================
  handleClientMessage(msg: ClientMessage): void {
    switch (msg.type) {
      case "mode":
        this.setAppMode(msg.mode);
        break;
      case "reset":
        this.engine.resetRound();
        if (this.virtual.on) this.virtual.resetPlayers();
        console.log("round reset (R)");
        break;
      case "start":
        if (this.engine.state === STATE_WAIT || this.engine.state === STATE_READY) {
          this.engine.debugStartRound();
        } else if (this.engine.state === STATE_GAMEOVER) {
          this.engine.resetRound();
        }
        break;
      case "nextMode":
        this.engine.nextMode();
        break;
      case "virtual":
        if (msg.on === this.virtual.on) break;
        this.engine.resetRound();
        this.virtual.setZones(this.engine.p1Start, this.engine.p2Start);
        if (msg.on) this.virtual.enable();
        else this.virtual.disable();
        break;
      case "keys":
        this.virtual.setKeys(msg.keys as VirtualKey[]);
        break;
      case "filters":
        if (msg.clamp !== undefined) this.tracker.useSpeedClamp = msg.clamp;
        if (msg.ema !== undefined) this.tracker.useEma = msg.ema;
        if (msg.alpha !== undefined) this.tracker.smoothAlpha = msg.alpha;
        break;
      case "setup.setDistances": {
        const next = [0, 0, 0, 0, 0, 0];
        for (let i = 0; i < 6; i++) next[i] = Number(msg.distances[i]) || 0;
        this.setup.anchorD = next;
        break;
      }
      case "setup.applyLayout":
        this.setup.applyLayout();
        break;
      case "setup.standardLayout":
        this.setup.standardLayout();
        break;
      case "setup.dragAnchor":
        this.setup.setAnchor(msg.index, [msg.x, msg.y], msg.commit);
        break;
      case "setup.dragZone":
        this.setup.setZone(msg.player, [msg.x, msg.y], msg.commit);
        break;
      case "setup.captureZone":
        this.setup.captureZone(msg.player);
        break;
      case "setup.save":
        this.setup.saveConfig();
        break;
    }
  }

  // ============================ snapshots ============================
  snapshot(): { game: GameView; status: StatusView } {
    const now = nowMs();
    const players: [PlayerView, PlayerView] = [
      this.buildPlayer(0, now),
      this.buildPlayer(1, now),
    ];
    const entities: EntityView[] = [];
    for (const e of this.entities.values()) {
      if (!e.visible) continue;
      entities.push({
        id: e.id,
        type: e.type,
        x: e.x,
        y: e.y,
        radius: e.radius,
        color: e.color,
        label: e.label,
      });
    }
    const rt = this.engine.state === STATE_GAMEOVER ? this.engine.mode.resultText() : null;

    const game: GameView = {
      state: this.engine.state as GameState,
      stateName: this.engine.stateName(),
      timeLeft: this.engine.timeLeft,
      centerValue: this.engine.centerValue(),
      p1Score: this.engine.mode.scores()[0],
      p2Score: this.engine.mode.scores()[1],
      winner: this.engine.roundWinner,
      modeId: this.engine.mode.id,
      modeName: this.engine.mode.displayName,
      hudLines: this.engine.mode.hudLines(),
      resultTitle: rt ? rt[0] : null,
      resultSubtitle: rt && rt.length > 1 ? rt[1] : null,
      players,
      oob: [
        { seconds: this.engine.oobCountdown[0], active: this.engine.oobActive[0] },
        { seconds: this.engine.oobCountdown[1], active: this.engine.oobActive[1] },
      ],
      entities,
      anchors: { ax: [...this.tracker.ax], ay: [...this.tracker.ay] },
      startZones: [[...this.engine.p1Start], [...this.engine.p2Start]],
    };

    let unknownTagId: number | null = null;
    for (const id of this.tracker.seenIds) {
      if (id !== TAG0_ID && id !== TAG1_ID) {
        unknownTagId = id;
        break;
      }
    }

    const status: StatusView = {
      serialConnected: this.serial.isConnected(),
      serialPort: this.serial.portName,
      serialStatus: this.serialStatus,
      oscIp: this.osc.ip,
      oscPort: this.osc.port,
      oscSent: this.osc.sent,
      frames: this.tracker.frames,
      fps: this.fps,
      lastFrameAgeMs: this.tracker.lastFrameMs ? now - this.tracker.lastFrameMs : -1,
      unknownTagId,
      virtual: this.virtual.on,
      appMode: this.appMode,
      useSpeedClamp: this.tracker.useSpeedClamp,
      useEma: this.tracker.useEma,
      smoothAlpha: this.tracker.smoothAlpha,
      anchorDistances: [...this.setup.anchorD],
      setup: {
        active: this.appMode === "setup",
        distances: [...this.setup.anchorD],
        status: this.setup.status,
      },
    };

    return { game, status };
  }

  private buildPlayer(id: number, now: number): PlayerView {
    const tag = this.tracker.tags.get(id === 0 ? TAG0_ID : TAG1_ID);
    const zone: Vec2 = id === 0 ? this.engine.p1Start : this.engine.p2Start;
    const invuln = this.engine.mode.playerInvuln(id);
    return {
      id,
      pos: tag?.pos ?? null,
      trail: tag?.trail.map((p) => [p[0], p[1]] as Vec2) ?? [],
      speed: tag?.speedMs ?? 0,
      lastFixAgeMs: tag && tag.lastFixMs ? now - tag.lastFixMs : -1,
      lives: this.engine.mode.playerLives(id),
      effects: this.engine.mode.playerEffects(id),
      inZone: this.engine.inZone(tag, zone),
      invuln,
    };
  }
}
