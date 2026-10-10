/**
 * Mode 1: Coin Hunt.
 *
 * Competitive coin collection. Bouncing hazards spawn progressively as coins are
 * collected and are neutral (dangerous to BOTH players). Powerups change the
 * rules. Direct port of `sender_py/modes/coin_hunt.py` / `sender/Mode_CoinHunt.pde`.
 */
import { TAG0_ID, TAG1_ID, type Vec2, type Vec3 } from "../../shared/protocol.js";
import type { Entity } from "../entities.js";
import type { GameEngine } from "../engine.js";
import { GameMode } from "./base.js";

const C_COIN: Vec3 = [255, 220, 40];
const C_ENEMY: Vec3 = [255, 60, 60];

/** Must match GameEngine.OOB_TIMEOUT_S (5 s). */
const OOB_TIMEOUT_S = 5;

const PU_MAGNET = 0;
const PU_INVIS = 1;
const PU_FREEZE = 2;
const PU_DOUBLE = 3;
const PU_LIFE = 4;

class Enemy {
  constructor(
    public ent: Entity,
    public vx: number,
    public vy: number,
  ) {}
}

export class CoinHunt extends GameMode {
  override readonly id = "coinHunt";
  override readonly displayName = "Coin Hunt";

  // coins
  static COLLECT_RADIUS_MM = 300;
  static COIN_MARGIN_MM = 500;
  static COIN_MIN_DIST_PLAYER_MM = 800;
  static COIN_FAIR_DIFF_MM = 1200;
  static COIN_VISUAL_MM = 120;

  // hazards
  static ENEMY_SPEED_MM_S = 600;
  static ENEMY_CATCH_RADIUS_MM = 350;
  static ENEMY_VISUAL_MM = 200;
  static ENEMY_SPAWN_SAFE_MM = 1200;
  static ENEMY_SPAWN_COINS_1 = 3;
  static ENEMY_SPAWN_COINS_2 = 6;

  // lives
  static START_LIVES = 3;
  static MAX_LIVES = 5;
  static INVULN_S = 2.0;

  // powerups
  static POWERUP_INTERVAL_S = 8;
  static POWERUP_LIFETIME_S = 15;
  static POWERUP_COLLECT_RADIUS_MM = 400;
  static POWERUP_VISUAL_MM = 200;
  static MAGNET_PULL_MM_S = 700;
  static MAGNET_S = 5;
  static INVIS_S = 5;
  static FREEZE_S = 4;

  scoreP1 = 0;
  scoreP2 = 0;
  coin: Entity | null = null;
  lives: [number, number] = [CoinHunt.START_LIVES, CoinHunt.START_LIVES];
  invuln: [number, number] = [0, 0];
  magnet: [number, number] = [0, 0];
  invis: [number, number] = [0, 0];
  freezeAll = 0;
  nextCoinDouble = false;
  enemies: Enemy[] = [];
  powerup: Entity | null = null;
  powerupType = PU_MAGNET;
  powerupTimer = CoinHunt.POWERUP_INTERVAL_S;
  powerupLife = 0;

  constructor(engine: GameEngine) {
    super(engine);
  }

  // ============================ lifecycle ============================
  override onRoundEnd(): void {
    this.coin = null;
    this.powerup = null;
    this.enemies = [];
    this.freezeAll = 0;
    this.nextCoinDouble = false;
    for (let i = 0; i < 2; i++) {
      this.invuln[i] = 0;
      this.magnet[i] = 0;
      this.invis[i] = 0;
    }
  }

  override onRoundStart(): void {
    this.scoreP1 = 0;
    this.scoreP2 = 0;
    this.engine.entities.clear();
    this.coin = null;
    this.powerup = null;
    this.enemies = [];
    for (let i = 0; i < 2; i++) {
      this.lives[i] = CoinHunt.START_LIVES;
      this.invuln[i] = 0;
      this.magnet[i] = 0;
      this.invis[i] = 0;
    }
    this.freezeAll = 0;
    this.nextCoinDouble = false;
    this.powerupTimer = CoinHunt.POWERUP_INTERVAL_S;
    this.spawnCoin();
  }

  /** Out of bounds costs one life (not the round); only 0 lives ends it. */
  override onPlayerOut(player: number): void {
    this.lives[player] -= 1;
    this.invuln[player] = CoinHunt.INVULN_S;
    console.log(`P${player + 1} out of bounds! -1 life, remaining: ${this.lives[player]}`);
    this.engine.osc.hit(player, CoinHunt.INVULN_S);
    this.engine.oobCountdown[player] = OOB_TIMEOUT_S;
    this.engine.oobActive[player] = false;
    if (this.lives[player] <= 0) {
      this.engine.roundWinner = player === 0 ? 2 : 1;
      console.log(`P${player + 1} ran out of lives (out of bounds) -> round over`);
      this.engine.requestEnd();
    }
  }

  override update(dt: number): void {
    this.tickTimers(dt);
    this.updateMagnet(dt);
    this.updateEnemies(dt);
    this.updatePowerup(dt);
    if (this.coin !== null) this.collectCoinCheck();
  }

  // ============================ data ============================
  override scores(): [number, number] {
    return [this.scoreP1, this.scoreP2];
  }

  override hudLines(): string[] {
    const lines: string[] = [];
    if (this.freezeAll > 0) lines.push(`ENEMIES FROZEN ${Math.trunc(this.freezeAll)}s`);
    if (this.nextCoinDouble) lines.push("NEXT COIN x2");
    return lines;
  }

  override playerLives(player: number): number {
    return this.lives[player];
  }

  override playerEffects(player: number): string[] {
    const fx: string[] = [];
    if (this.magnet[player] > 0) fx.push(`MAGNET ${Math.trunc(this.magnet[player])}s`);
    if (this.invis[player] > 0) fx.push(`INVIS ${Math.trunc(this.invis[player])}s`);
    return fx;
  }

  override playerInvuln(player: number): number {
    return this.invuln[player];
  }

  // ============================ timers ============================
  tickTimers(dt: number): void {
    this.freezeAll = Math.max(0, this.freezeAll - dt);
    for (let i = 0; i < 2; i++) {
      this.invuln[i] = Math.max(0, this.invuln[i] - dt);
      this.magnet[i] = Math.max(0, this.magnet[i] - dt);
      this.invis[i] = Math.max(0, this.invis[i] - dt);
    }
  }

  // ============================ coins ============================
  updateMagnet(dt: number): void {
    if (this.coin === null) return;
    let best = -1;
    let bestD = Number.POSITIVE_INFINITY;
    for (let p = 0; p < 2; p++) {
      if (this.magnet[p] <= 0) continue;
      const t = this.engine.tags.get(p === 0 ? TAG0_ID : TAG1_ID);
      if (t === undefined || t.pos === null) continue;
      const d = dist(t.pos, [this.coin.x, this.coin.y]);
      if (d < bestD) {
        bestD = d;
        best = p;
      }
    }
    if (best < 0) return;
    const t = this.engine.tags.get(best === 0 ? TAG0_ID : TAG1_ID);
    if (t === undefined || t.pos === null) return;
    const dx = t.pos[0] - this.coin.x;
    const dy = t.pos[1] - this.coin.y;
    const d = Math.hypot(dx, dy);
    if (d < 1) return;
    const step = Math.min(CoinHunt.MAGNET_PULL_MM_S * dt, d);
    this.coin.x += (dx / d) * step;
    this.coin.y += (dy / d) * step;
  }

  collectCoinCheck(): void {
    if (this.coin === null) return;
    for (let p = 0; p < 2; p++) {
      const t = this.engine.tags.get(p === 0 ? TAG0_ID : TAG1_ID);
      if (t === undefined || t.pos === null) continue;
      if (dist(t.pos, [this.coin.x, this.coin.y]) < CoinHunt.COLLECT_RADIUS_MM) {
        this.collectCoin(p);
        break;
      }
    }
  }

  collectCoin(player: number): void {
    const gain = this.nextCoinDouble ? 2 : 1;
    this.nextCoinDouble = false;
    if (player === 0) this.scoreP1 += gain;
    else this.scoreP2 += gain;
    console.log(
      `P${player + 1} collected coin (+${gain}) -> P1:${this.scoreP1} P2:${this.scoreP2}`,
    );
    if (this.magnet[player] > 0) {
      this.magnet[player] = 0;
      console.log(`P${player + 1} magnet consumed on coin capture`);
    }
    if (this.coin !== null) this.engine.entities.remove(this.coin.id);
    this.coin = null;
    this.maybeSpawnEnemies();
    this.spawnCoin();
  }

  spawnCoin(): void {
    const b = this.engine.fieldBounds();
    const t0 = this.engine.tags.get(TAG0_ID);
    const t1 = this.engine.tags.get(TAG1_ID);
    for (let k = 0; k < 100; k++) {
      const x = rand(b[0] + CoinHunt.COIN_MARGIN_MM, b[1] - CoinHunt.COIN_MARGIN_MM);
      const y = rand(b[2] + CoinHunt.COIN_MARGIN_MM, b[3] - CoinHunt.COIN_MARGIN_MM);
      const d0 = t0 && t0.pos ? dist([x, y], t0.pos) : Number.POSITIVE_INFINITY;
      const d1 = t1 && t1.pos ? dist([x, y], t1.pos) : Number.POSITIVE_INFINITY;
      if (Math.min(d0, d1) < CoinHunt.COIN_MIN_DIST_PLAYER_MM) continue;
      if (t0 && t1 && t0.pos && t1.pos && Math.abs(d0 - d1) > CoinHunt.COIN_FAIR_DIFF_MM) continue;
      this.coin = this.engine.entities.spawn("coin", x, y, CoinHunt.COIN_VISUAL_MM, C_COIN);
      return;
    }
    this.coin = this.engine.entities.spawn(
      "coin",
      rand(b[0] + CoinHunt.COIN_MARGIN_MM, b[1] - CoinHunt.COIN_MARGIN_MM),
      rand(b[2] + CoinHunt.COIN_MARGIN_MM, b[3] - CoinHunt.COIN_MARGIN_MM),
      CoinHunt.COIN_VISUAL_MM,
      C_COIN,
    );
  }

  // ============================ hazards ============================
  maybeSpawnEnemies(): void {
    const total = this.scoreP1 + this.scoreP2;
    if (this.enemies.length === 0 && total >= CoinHunt.ENEMY_SPAWN_COINS_1) {
      this.spawnEnemy();
    } else if (this.enemies.length === 1 && total >= CoinHunt.ENEMY_SPAWN_COINS_2) {
      this.spawnEnemy();
    }
  }

  spawnEnemy(): void {
    const pos = this.randomFarPoint(CoinHunt.ENEMY_SPAWN_SAFE_MM);
    const ang =
      (rand(25, 65) * Math.PI) / 180 + Math.floor(Math.random() * 4) * (Math.PI / 2);
    const vx = Math.cos(ang) * CoinHunt.ENEMY_SPEED_MM_S;
    const vy = Math.sin(ang) * CoinHunt.ENEMY_SPEED_MM_S;
    const e = this.engine.entities.spawn("enemy", pos[0], pos[1], CoinHunt.ENEMY_VISUAL_MM, C_ENEMY);
    this.enemies.push(new Enemy(e, vx, vy));
    console.log(`Hazard spawned (${this.enemies.length})`);
  }

  updateEnemies(dt: number): void {
    const b = this.engine.fieldBounds();
    const m = CoinHunt.ENEMY_VISUAL_MM;
    for (const en of this.enemies) {
      if (this.freezeAll <= 0) {
        en.ent.x += en.vx * dt;
        en.ent.y += en.vy * dt;
        if (en.ent.x < b[0] + m) {
          en.ent.x = b[0] + m;
          en.vx = Math.abs(en.vx);
        }
        if (en.ent.x > b[1] - m) {
          en.ent.x = b[1] - m;
          en.vx = -Math.abs(en.vx);
        }
        if (en.ent.y < b[2] + m) {
          en.ent.y = b[2] + m;
          en.vy = Math.abs(en.vy);
        }
        if (en.ent.y > b[3] - m) {
          en.ent.y = b[3] - m;
          en.vy = -Math.abs(en.vy);
        }
      }
      for (let p = 0; p < 2; p++) {
        if (this.invis[p] > 0 || this.invuln[p] > 0) continue;
        const td = this.engine.tags.get(p === 0 ? TAG0_ID : TAG1_ID);
        if (td === undefined || td.pos === null) continue;
        if (dist([en.ent.x, en.ent.y], td.pos) < CoinHunt.ENEMY_CATCH_RADIUS_MM) {
          this.catchPlayer(p, en);
        }
      }
    }
  }

  catchPlayer(player: number, en: Enemy): void {
    this.lives[player] -= 1;
    this.invuln[player] = CoinHunt.INVULN_S;
    console.log(`P${player + 1} hit by hazard! lives=${this.lives[player]}`);
    this.engine.osc.hit(player, CoinHunt.INVULN_S);
    en.vx = -en.vx;
    en.vy = -en.vy;
    if (this.lives[player] <= 0) {
      this.engine.roundWinner = player === 0 ? 2 : 1;
      this.engine.requestEnd();
    }
  }

  // ============================ powerups ============================
  updatePowerup(dt: number): void {
    if (this.powerup !== null) {
      this.powerupLife -= dt;
      if (this.powerupLife <= 0) {
        this.engine.entities.remove(this.powerup.id);
        this.powerup = null;
        this.powerupTimer = CoinHunt.POWERUP_INTERVAL_S;
        return;
      }
      for (let p = 0; p < 2; p++) {
        const t = this.engine.tags.get(p === 0 ? TAG0_ID : TAG1_ID);
        if (t === undefined || t.pos === null) continue;
        if (dist(t.pos, [this.powerup.x, this.powerup.y]) < CoinHunt.POWERUP_COLLECT_RADIUS_MM) {
          this.applyPowerup(this.powerupType, p);
          this.engine.entities.remove(this.powerup.id);
          this.powerup = null;
          this.powerupTimer = CoinHunt.POWERUP_INTERVAL_S;
          return;
        }
      }
    } else {
      this.powerupTimer -= dt;
      if (this.powerupTimer <= 0) this.spawnPowerup();
    }
  }

  spawnPowerup(): void {
    this.powerupType = Math.floor(Math.random() * 5);
    const pos = this.randomFarPoint(CoinHunt.COIN_MIN_DIST_PLAYER_MM);
    this.powerup = this.engine.entities.spawn(
      "powerup",
      pos[0],
      pos[1],
      CoinHunt.POWERUP_VISUAL_MM,
      this.powerupColor(this.powerupType),
    );
    this.powerup.label = this.powerupLabel(this.powerupType);
    this.powerupLife = CoinHunt.POWERUP_LIFETIME_S;
    console.log("Powerup spawned:", this.powerupName(this.powerupType));
  }

  powerupColor(t: number): Vec3 {
    switch (t) {
      case PU_MAGNET:
        return [120, 220, 255];
      case PU_INVIS:
        return [180, 140, 255];
      case PU_FREEZE:
        return [120, 255, 200];
      case PU_DOUBLE:
        return [255, 200, 120];
      default:
        return [255, 120, 200];
    }
  }

  powerupLabel(t: number): string {
    switch (t) {
      case PU_MAGNET:
        return "MAG";
      case PU_INVIS:
        return "INV";
      case PU_FREEZE:
        return "FRE";
      case PU_DOUBLE:
        return "DOU";
      default:
        return "LIF";
    }
  }

  powerupName(t: number): string {
    switch (t) {
      case PU_MAGNET:
        return "MAGNET";
      case PU_INVIS:
        return "INVIS";
      case PU_FREEZE:
        return "FREEZE";
      case PU_DOUBLE:
        return "DOUBLE";
      default:
        return "LIFE";
    }
  }

  applyPowerup(t: number, player: number): void {
    switch (t) {
      case PU_MAGNET:
        this.magnet[player] = CoinHunt.MAGNET_S;
        break;
      case PU_INVIS:
        this.invis[player] = CoinHunt.INVIS_S;
        break;
      case PU_FREEZE:
        this.freezeAll = CoinHunt.FREEZE_S;
        break;
      case PU_DOUBLE:
        this.nextCoinDouble = true;
        break;
      case PU_LIFE:
        this.lives[player] = Math.min(this.lives[player] + 1, CoinHunt.MAX_LIVES);
        break;
    }
    console.log(`P${player + 1} got ${this.powerupName(t)}`);
  }

  // ============================ helpers ============================
  randomFarPoint(minDist: number): Vec2 {
    const b = this.engine.fieldBounds();
    const t0 = this.engine.tags.get(TAG0_ID);
    const t1 = this.engine.tags.get(TAG1_ID);
    for (let k = 0; k < 100; k++) {
      const x = rand(b[0] + CoinHunt.COIN_MARGIN_MM, b[1] - CoinHunt.COIN_MARGIN_MM);
      const y = rand(b[2] + CoinHunt.COIN_MARGIN_MM, b[3] - CoinHunt.COIN_MARGIN_MM);
      const d0 = t0 && t0.pos ? dist([x, y], t0.pos) : Number.POSITIVE_INFINITY;
      const d1 = t1 && t1.pos ? dist([x, y], t1.pos) : Number.POSITIVE_INFINITY;
      if (Math.min(d0, d1) < minDist) continue;
      return [x, y];
    }
    return [
      rand(b[0] + CoinHunt.COIN_MARGIN_MM, b[1] - CoinHunt.COIN_MARGIN_MM),
      rand(b[2] + CoinHunt.COIN_MARGIN_MM, b[3] - CoinHunt.COIN_MARGIN_MM),
    ];
  }
}

function dist(a: Vec2, b: Vec2): number {
  return Math.hypot(a[0] - b[0], a[1] - b[1]);
}

function rand(min: number, max: number): number {
  return min + Math.random() * (max - min);
}
