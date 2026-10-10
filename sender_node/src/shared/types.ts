import type { EntityType, GameState, Vec2, Vec3 } from "./protocol.js";

// ============================ VIEW MODELS ============================

export interface PlayerView {
  /** 0 = P1 (tag 0x0000), 1 = P2 (tag 0x0001) */
  id: number;
  pos: Vec2 | null;
  trail: Vec2[];
  /** current speed in mm/s */
  speed: number;
  lastFixAgeMs: number; // ms since last fix, -1 when no fix
  lives: number;
  effects: string[];
  inZone: boolean;
  /** seconds of remaining invulnerability (also drives the hit flash) */
  invuln: number;
}

export interface EntityView {
  id: number;
  type: EntityType;
  x: number;
  y: number;
  radius: number;
  color: Vec3;
  label: string;
}

export interface OobView {
  seconds: number;
  active: boolean;
}

export interface GameView {
  state: GameState;
  stateName: string;
  timeLeft: number;
  centerValue: string;
  p1Score: number;
  p2Score: number;
  winner: number;
  modeId: string;
  modeName: string;
  hudLines: string[];
  resultTitle: string | null;
  resultSubtitle: string | null;
  players: [PlayerView, PlayerView];
  oob: [OobView, OobView];
  entities: EntityView[];
  anchors: { ax: number[]; ay: number[] };
  startZones: [Vec2, Vec2];
}

export interface SetupView {
  active: boolean;
  /** six measured anchor distances A0-A1 .. A2-A3 */
  distances: number[];
  status: string;
}

export interface StatusView {
  serialConnected: boolean;
  serialPort: string;
  serialStatus: string;
  oscIp: string;
  oscPort: number;
  oscSent: number;
  frames: number;
  fps: number;
  lastFrameAgeMs: number;
  unknownTagId: number | null;
  virtual: boolean;
  appMode: "game" | "setup";
  useSpeedClamp: boolean;
  useEma: boolean;
  smoothAlpha: number;
  anchorDistances: number[];
  setup: SetupView;
}

// ============================ SERVER -> CLIENT ============================

export interface SnapshotMessage {
  type: "snapshot";
  game: GameView;
  status: StatusView;
}

export type ServerMessage = SnapshotMessage;

// ============================ CLIENT -> SERVER ============================

export type VirtualKey =
  | "w"
  | "a"
  | "s"
  | "d"
  | "up"
  | "down"
  | "left"
  | "right";

export type ClientMessage =
  | { type: "mode"; mode: "game" | "setup" }
  | { type: "reset" }
  | { type: "start" }
  | { type: "nextMode" }
  | { type: "virtual"; on: boolean }
  | { type: "keys"; keys: VirtualKey[] }
  | { type: "filters"; clamp?: boolean; ema?: boolean; alpha?: number }
  | { type: "setup.setDistances"; distances: number[] }
  | { type: "setup.applyLayout" }
  | { type: "setup.standardLayout" }
  | { type: "setup.dragAnchor"; index: number; x: number; y: number; commit: boolean }
  | { type: "setup.dragZone"; player: number; x: number; y: number; commit: boolean }
  | { type: "setup.captureZone"; player: number }
  | { type: "setup.save" };
