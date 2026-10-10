import { describe, expect, it } from "vitest";
import {
  STATE_GAMEOVER,
  STATE_PLAYING,
  STATE_READY,
  STATE_WAIT,
} from "../src/shared/protocol.js";
import { nowMs } from "../src/server/clock.js";
import { EntityManager } from "../src/server/entities.js";
import { GameEngine } from "../src/server/engine.js";
import { OscClient } from "../src/server/osc.js";
import { CoinHunt } from "../src/server/modes/coinHunt.js";
import { TagData, Tracker } from "../src/server/tracker.js";

function makeEngine(): { engine: GameEngine; tracker: Tracker } {
  const tracker = new Tracker();
  const osc = new OscClient({ ip: "127.0.0.1", port: 1, enabled: false });
  const entities = new EntityManager();
  const engine = new GameEngine(osc, tracker, entities, [3000, 1500], [4000, 1500]);
  return { engine, tracker };
}

function setTag(tracker: Tracker, id: number, x: number, y: number): TagData {
  const t = new TagData(id);
  t.pos = [x, y];
  t.lastFixMs = nowMs();
  tracker.tags.set(id, t);
  return t;
}

describe("GameEngine state machine", () => {
  it("WAIT -> READY when both players are in their zones", () => {
    const { engine, tracker } = makeEngine();
    setTag(tracker, 0, 3000, 1500);
    setTag(tracker, 1, 4000, 1500);
    engine.update();
    expect(engine.state).toBe(STATE_READY);
    expect(engine.timeLeft).toBe(GameEngine.READY_S);
  });

  it("READY -> WAIT when a player leaves the zone", () => {
    const { engine, tracker } = makeEngine();
    setTag(tracker, 0, 3000, 1500);
    const t1 = setTag(tracker, 1, 4000, 1500);
    engine.update();
    expect(engine.state).toBe(STATE_READY);
    t1.pos = [500, 500];
    engine.update();
    expect(engine.state).toBe(STATE_WAIT);
  });

  it("runs READY -> PLAYING -> GAMEOVER -> WAIT", () => {
    const { engine, tracker } = makeEngine();
    setTag(tracker, 0, 3000, 1500);
    setTag(tracker, 1, 4000, 1500);
    engine.update();
    expect(engine.state).toBe(STATE_READY);

    engine.stateEnteredMs = nowMs() - (GameEngine.READY_S * 1000 + 100);
    engine.update();
    expect(engine.state).toBe(STATE_PLAYING);
    expect(engine.entities.entities.size).toBeGreaterThan(0); // a coin spawned

    engine.stateEnteredMs = nowMs() - (GameEngine.GAME_TIME_S * 1000 + 100);
    engine.update();
    expect(engine.state).toBe(STATE_GAMEOVER);

    engine.stateEnteredMs = nowMs() - (GameEngine.GAMEOVER_S * 1000 + 100);
    engine.update();
    expect(engine.state).toBe(STATE_WAIT);
  });

  it("cleans up entities, timers and OOB on setState(WAIT)", () => {
    const { engine, tracker } = makeEngine();
    setTag(tracker, 0, 3000, 1500);
    setTag(tracker, 1, 4000, 1500);
    engine.debugStartRound();
    expect(engine.entities.entities.size).toBeGreaterThan(0);
    engine.oobActive[0] = true;
    engine.oobCountdown[0] = 1.2;

    engine.setState(STATE_WAIT);
    expect(engine.entities.entities.size).toBe(0);
    expect(engine.timeLeft).toBe(0);
    expect(engine.oobActive[0]).toBe(false);
    expect(engine.oobCountdown[0]).toBe(GameEngine.OOB_TIMEOUT_S);
    expect(engine.roundWinner).toBe(-1);
  });
});

describe("Out-of-bounds", () => {
  it("subtracts one life, resets the window and keeps the round alive", () => {
    const { engine, tracker } = makeEngine();
    engine.debugStartRound();
    const ch = engine.mode as CoinHunt;
    setTag(tracker, 0, -2000, 1500); // far outside + margin
    const before = ch.lives[0];
    engine.oobCountdown[0] = 0.05;
    engine.updateOob(0.1);
    expect(ch.lives[0]).toBe(before - 1);
    expect(engine.oobActive[0]).toBe(false);
    expect(engine.oobCountdown[0]).toBe(GameEngine.OOB_TIMEOUT_S);
    expect(engine.state).toBe(STATE_PLAYING);
  });

  it("ends the round with the opponent as winner at zero lives", () => {
    const { engine } = makeEngine();
    engine.debugStartRound();
    const ch = engine.mode as CoinHunt;
    for (let i = 0; i < CoinHunt.START_LIVES; i++) ch.onPlayerOut(0);
    expect(ch.lives[0]).toBe(0);
    expect(engine.roundWinner).toBe(2);
    expect(engine.state).toBe(STATE_GAMEOVER);
  });
});
