/**
 * High-DPI HTML5 canvas renderer for the playing field.
 * All coordinates are in field mm; the camera maps them to CSS pixels. The
 * canvas backing store is scaled by devicePixelRatio for true retina rendering.
 */
import { STATE_PLAYING, STATE_READY, STATE_WAIT, type Vec2 } from "../shared/protocol.js";
import type { EntityView, GameView } from "../shared/types.js";

const BG = "#16161a";
const GRID = "#24242c";
const ANCHOR = "#5ac85a";
const C_P1 = "#00c8ff";
const C_P2 = "#ff9628";

export class Camera {
  s = 1;
  ox = 0;
  oy = 0;
  w = 0;
  h = 0;

  compute(ax: number[], ay: number[], w: number, h: number, setup: boolean): void {
    const minx = Math.min(...ax);
    const maxx = Math.max(...ax);
    const miny = Math.min(...ay);
    const maxy = Math.max(...ay);
    let fw = maxx - minx;
    let fh = maxy - miny;
    if (fw < 1) fw = 1000;
    if (fh < 1) fh = 1000;
    const top = setup ? 40 : 16;
    const bottom = h - (setup ? 40 : 16);
    const side = setup ? 60 : 24;
    const availW = w - 2 * side;
    const availH = bottom - top;
    this.s = Math.min(availW / fw, availH / fh);
    const fieldTop = top + (availH - fh * this.s) / 2;
    this.ox = side + (availW - fw * this.s) / 2 - minx * this.s;
    this.oy = fieldTop + maxy * this.s;
    this.w = w;
    this.h = h;
  }

  sx(x: number): number {
    return this.ox + x * this.s;
  }
  sy(y: number): number {
    return this.oy - y * this.s;
  }
  /** screen px -> world mm */
  worldFromScreen(px: number, py: number): Vec2 {
    return [(px - this.ox) / this.s, (this.oy - py) / this.s];
  }
}

export function renderField(
  ctx: CanvasRenderingContext2D,
  w: number,
  h: number,
  game: GameView,
  cam: Camera,
  setupActive: boolean,
): void {
  ctx.clearRect(0, 0, w, h);
  ctx.fillStyle = BG;
  ctx.fillRect(0, 0, w, h);

  cam.compute(game.anchors.ax, game.anchors.ay, w, h, setupActive);

  drawGrid(ctx, cam, game.anchors.ax, game.anchors.ay);
  const showZones = setupActive || game.state === STATE_WAIT || game.state === STATE_READY;
  if (showZones) drawStartZones(ctx, cam, game.startZones, setupActive);
  drawAnchors(ctx, cam, game.anchors.ax, game.anchors.ay);

  if (!setupActive) {
    drawEntities(ctx, cam, game.entities);
    if (game.state === STATE_PLAYING) drawHitRings(ctx, cam, game.players);
    drawPlayers(ctx, cam, game);
  } else {
    // still show player dots while calibrating, to capture zones
    drawPlayers(ctx, cam, game);
  }
}

function drawGrid(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  ax: number[],
  ay: number[],
): void {
  const minx = Math.min(...ax);
  const maxx = Math.max(...ax);
  const miny = Math.min(...ay);
  const maxy = Math.max(...ay);
  const step = 500;
  ctx.strokeStyle = GRID;
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let gx = Math.floor(minx / step) * step; gx <= maxx; gx += step) {
    ctx.moveTo(cam.sx(gx), cam.sy(miny));
    ctx.lineTo(cam.sx(gx), cam.sy(maxy));
  }
  for (let gy = Math.floor(miny / step) * step; gy <= maxy; gy += step) {
    ctx.moveTo(cam.sx(minx), cam.sy(gy));
    ctx.lineTo(cam.sx(maxx), cam.sy(gy));
  }
  ctx.stroke();
}

function drawAnchors(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  ax: number[],
  ay: number[],
): void {
  ctx.font = "11px system-ui, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "bottom";
  for (let i = 0; i < 4; i++) {
    const x = cam.sx(ax[i]);
    const y = cam.sy(ay[i]);
    ctx.fillStyle = ANCHOR;
    ctx.fillRect(x - 8, y - 8, 16, 16);
    ctx.fillStyle = "#fff";
    ctx.fillText(`A${i}`, x, y - 11);
  }
}

function drawStartZones(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  zones: [Vec2, Vec2],
  setupActive: boolean,
): void {
  const entries: [Vec2, string, string][] = [
    [zones[0], "P1", C_P1],
    [zones[1], "P2", C_P2],
  ];
  ctx.font = "12px system-ui, sans-serif";
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  for (const [zone, label, color] of entries) {
    const x = cam.sx(zone[0]);
    const y = cam.sy(zone[1]);
    ctx.strokeStyle = color;
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(x, y, Math.max(1, 250 * cam.s), 0, Math.PI * 2);
    ctx.stroke();
    if (setupActive) {
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = color;
    ctx.fillText(label, x, y);
  }
}

function drawEntities(ctx: CanvasRenderingContext2D, cam: Camera, entities: EntityView[]): void {
  for (const e of entities) {
    const x = cam.sx(e.x);
    const y = cam.sy(e.y);
    const r = Math.max(2, e.radius * cam.s);
    const rgb = `rgb(${e.color[0]},${e.color[1]},${e.color[2]})`;
    if (e.type === "enemy" || e.type === "obstacle") {
      ctx.fillStyle = rgb;
      ctx.fillRect(x - r, y - r, 2 * r, 2 * r);
    } else if (e.type === "powerup" || e.type === "zone") {
      ctx.strokeStyle = rgb;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.stroke();
    } else {
      ctx.fillStyle = rgb;
      ctx.beginPath();
      ctx.arc(x, y, r, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(255,255,255,0.8)";
      ctx.lineWidth = 1;
      ctx.stroke();
    }
    if (e.label) {
      ctx.fillStyle = "#fff";
      ctx.font = "11px system-ui, sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(e.label, x, y);
    }
  }
}

function drawHitRings(
  ctx: CanvasRenderingContext2D,
  cam: Camera,
  players: GameView["players"],
): void {
  const colors = [C_P1, C_P2];
  ctx.lineWidth = 1;
  for (const p of players) {
    if (p.pos === null) continue;
    ctx.strokeStyle = colors[p.id];
    ctx.globalAlpha = 0.5;
    ctx.beginPath();
    ctx.arc(cam.sx(p.pos[0]), cam.sy(p.pos[1]), Math.max(1, 300 * cam.s), 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
  }
}

function drawPlayers(ctx: CanvasRenderingContext2D, cam: Camera, game: GameView): void {
  const colors = [C_P1, C_P2];
  for (const p of game.players) {
    const color = colors[p.id];
    const stale = p.lastFixAgeMs > 2000;
    // trail with a fading gradient from dim to bright
    if (p.trail.length >= 2) {
      const n = p.trail.length;
      for (let i = 1; i < n; i++) {
        const f = 15 + ((i - 1) * (200 - 15)) / Math.max(1, n - 2);
        const a = stale ? f * 0.35 : f / 255;
        ctx.strokeStyle = color;
        ctx.globalAlpha = Math.max(0, Math.min(1, a));
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(cam.sx(p.trail[i - 1][0]), cam.sy(p.trail[i - 1][1]));
        ctx.lineTo(cam.sx(p.trail[i][0]), cam.sy(p.trail[i][1]));
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }
    if (p.pos !== null) {
      const x = cam.sx(p.pos[0]);
      const y = cam.sy(p.pos[1]);
      ctx.globalAlpha = stale ? 0.4 : 1;
      // invulnerability blink
      if (p.invuln > 0 && Math.floor(p.invuln * 6) % 2 === 0) ctx.globalAlpha *= 0.45;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(x, y, 7, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "#fff";
      ctx.lineWidth = 1.5;
      ctx.stroke();
      ctx.globalAlpha = 1;
      ctx.fillStyle = "#fff";
      ctx.font = "12px system-ui, sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(p.id === 0 ? "P1" : "P2", x + 11, y);
    }
  }

  // out-of-bounds ring
  for (let i = 0; i < 2; i++) {
    const o = game.oob[i];
    const p = game.players[i];
    if (!o.active || p.pos === null) continue;
    const x = cam.sx(p.pos[0]);
    const y = cam.sy(p.pos[1]);
    const r = Math.max(20, 40 * cam.s);
    ctx.strokeStyle = "#ff3c3c";
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(x, y, r, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = "#ff5050";
    ctx.font = "12px system-ui, sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "bottom";
    ctx.fillText(`GO BACK! ${Math.ceil(o.seconds)}s`, x, y - r - 4);
  }
}
