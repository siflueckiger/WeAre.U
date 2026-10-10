/**
 * Central truth for the WeAre.U protocol, ported from `shared/protocol.py`.
 * Every value here must match `docs/osc-protocol.md` and the receiver.
 */

// ============================ NETWORK ============================
export const LISTEN_PORT = 8000; // receiver listens here; sender targets this
export const OSC_LOCAL_PORT = 12000; // unused sender-side listen port (oscP5 compat)

// ============================ GAME STATES ============================
export const STATE_WAIT = 0; // players must reach their start zones
export const STATE_PLAYING = 1; // round running
export const STATE_GAMEOVER = 2; // result screen, auto restart
export const STATE_READY = 3; // countdown before round start

export type GameState =
  | typeof STATE_WAIT
  | typeof STATE_PLAYING
  | typeof STATE_GAMEOVER
  | typeof STATE_READY;

export const STATE_NAMES: Record<number, string> = {
  [STATE_WAIT]: "WAIT",
  [STATE_PLAYING]: "PLAYING",
  [STATE_GAMEOVER]: "GAMEOVER",
  [STATE_READY]: "READY",
};

// ============================ FIELD ============================
// Anchor positions A0..A3 in mm -- standard 3x7m layout.
// A0 top left, A1 bottom left, A2 bottom right, A3 top right.
export const DEFAULT_AX = [0, 0, 7000, 7000];
export const DEFAULT_AY = [3000, 0, 0, 3000];

// Start positions per player (mm) -- centered, 1 m apart.
export const DEFAULT_P1_START = [3000, 1500];
export const DEFAULT_P2_START = [4000, 1500];
export const START_ZONE_RADIUS_MM = 250;

// ============================ TAGS ============================
export const TAG0_ID = 0x0000;
export const TAG1_ID = 0x0001;

export const C_P1: [number, number, number] = [0, 200, 255]; // player 1 (cyan)
export const C_P2: [number, number, number] = [255, 150, 40]; // player 2 (orange)
export const TRAIL_MAX = 60;

// ============================ OSC ADDRESSES ============================
export const ADDR_P1_POS = "/p1/pos";
export const ADDR_P2_POS = "/p2/pos";
export const ADDR_ENT_UPSERT = "/ent/upsert";
export const ADDR_ENT_POS = "/ent/pos";
export const ADDR_ENT_REMOVE = "/ent/remove";
export const ADDR_GAME_STATS = "/game/stats";
export const ADDR_GAME_OOB = "/game/oob";
export const ADDR_GAME_MODE = "/game/mode";
export const ADDR_GAME_RESULT = "/game/result";
export const ADDR_GAME_HIT = "/game/hit";
export const ADDR_HUD = "/hud";
export const ADDR_START_P1 = "/start/p1";
export const ADDR_START_P2 = "/start/p2";
export const ADDR_ANCHORS = "/anchors";

// ============================ ENTITY TYPES ============================
export type EntityType = "coin" | "enemy" | "powerup" | "zone" | "obstacle";

export const ENTITY_SHAPES: Record<string, string> = {
  coin: "circle",
  enemy: "square",
  powerup: "ring",
  zone: "ring",
  obstacle: "rect",
};

export type Vec2 = [number, number];
export type Vec3 = [number, number, number];
