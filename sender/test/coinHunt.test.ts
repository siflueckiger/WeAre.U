import { describe, expect, it } from "vitest";
import { EntityManager } from "../src/server/entities.js";
import { GameEngine } from "../src/server/engine.js";
import { CoinHunt } from "../src/server/modes/coinHunt.js";
import { OscClient } from "../src/server/osc.js";
import { TagData, Tracker } from "../src/server/tracker.js";

function makeCoinHunt(): { ch: CoinHunt; tracker: Tracker } {
  const tracker = new Tracker();
  const osc = new OscClient({ ip: "127.0.0.1", port: 1, enabled: false });
  const engine = new GameEngine(osc, tracker, new EntityManager(), [3000, 1500], [4000, 1500]);
  engine.debugStartRound();
  return { ch: engine.mode as CoinHunt, tracker };
}

function setTag(tracker: Tracker, id: number, x: number, y: number): void {
  const t = new TagData(id);
  t.pos = [x, y];
  tracker.tags.set(id, t);
}

describe("CoinHunt", () => {
  it("scores a coin and respawns a new one", () => {
    const { ch, tracker } = makeCoinHunt();
    expect(ch.coin).not.toBeNull();
    const firstId = ch.coin!.id;
    setTag(tracker, 0, ch.coin!.x, ch.coin!.y);
    ch.collectCoinCheck();
    expect(ch.scoreP1).toBe(1);
    expect(ch.coin).not.toBeNull();
    expect(ch.coin!.id).not.toBe(firstId);
  });

  it("doubles the next coin on the DOUBLE powerup", () => {
    const { ch, tracker } = makeCoinHunt();
    ch.nextCoinDouble = true;
    setTag(tracker, 0, ch.coin!.x, ch.coin!.y);
    ch.collectCoinCheck();
    expect(ch.scoreP1).toBe(2);
    expect(ch.nextCoinDouble).toBe(false);
  });

  it("consumes a magnet on the owner's coin capture", () => {
    const { ch, tracker } = makeCoinHunt();
    ch.magnet[0] = 5;
    setTag(tracker, 0, ch.coin!.x, ch.coin!.y);
    ch.collectCoinCheck();
    expect(ch.magnet[0]).toBe(0);
  });

  it("bounces hazards off the field walls", () => {
    const { ch } = makeCoinHunt();
    ch.spawnEnemy();
    const en = ch.enemies[0];
    en.ent.x = 100; // inside the left wall margin (200 mm)
    en.ent.y = 1500;
    en.vx = -600;
    en.vy = 0;
    ch.updateEnemies(0.01);
    expect(en.ent.x).toBe(200);
    expect(en.vx).toBeGreaterThan(0);
  });

  it("deflects a hazard when it hits a player instead of teleporting", () => {
    const { ch, tracker } = makeCoinHunt();
    ch.spawnEnemy();
    const en = ch.enemies[0];
    en.ent.x = 3000;
    en.ent.y = 1500;
    en.vx = 600;
    en.vy = 0;
    setTag(tracker, 0, 3000, 1500);
    const before = ch.lives[0];
    ch.updateEnemies(0.0);
    expect(ch.lives[0]).toBe(before - 1);
    expect(ch.invuln[0]).toBeGreaterThan(0);
    expect(en.vx).toBeLessThan(0); // velocity flipped, position unchanged
    expect(en.ent.x).toBe(3000);
  });

  it("spawns a hazard only after the first coin threshold", () => {
    const { ch, tracker } = makeCoinHunt();
    expect(ch.enemies.length).toBe(0);
    for (let i = 0; i < CoinHunt.ENEMY_SPAWN_COINS_1; i++) {
      setTag(tracker, 0, ch.coin!.x, ch.coin!.y);
      ch.collectCoinCheck();
    }
    expect(ch.enemies.length).toBe(1);
  });
});
