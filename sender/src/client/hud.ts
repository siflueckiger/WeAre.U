/**
 * DOM-based operator HUD: top header (scores, lives, timer), floating warnings
 * and the status footer. DOM text stays crisp on retina and scales with the
 * browser, unlike rasterised canvas text.
 */
import { STATE_GAMEOVER, STATE_PLAYING, STATE_READY, STATE_WAIT } from "../shared/protocol.js";
import type { GameView, PlayerView, StatusView } from "../shared/types.js";

const P1 = "#00c8ff";
const P2 = "#ff9628";

const STATE_COLORS: Record<number, string> = {
  [STATE_WAIT]: "#a0a0a0",
  [STATE_READY]: "#ffe678",
  [STATE_PLAYING]: "#8ce68c",
  [STATE_GAMEOVER]: "#ffaa3c",
};

export function renderHeader(el: HTMLElement, game: GameView): void {
  el.innerHTML = [
    playerHead(game, 0),
    centerHead(game),
    playerHead(game, 1),
  ].join("");
}

function playerHead(game: GameView, id: 0 | 1): string {
  const p = game.players[id];
  const color = id === 0 ? P1 : P2;
  const cls = id === 0 ? "" : " p2";
  const score = id === 0 ? game.p1Score : game.p2Score;
  const pips = renderPips(p.lives);
  const status = renderStatus(p);
  return `
    <div class="player-head${cls}" style="color:${color}">
      <div class="player-label">P${id + 1}</div>
      <div class="player-score">${score}</div>
      <div class="pips">${pips}</div>
      ${status}
    </div>`;
}

function renderStatus(p: PlayerView): string {
  if (p.invuln > 0) {
    return `<div class="player-status" style="color:#ff5050">HIT!</div>`;
  }
  if (p.effects.length > 0) {
    return `<div class="player-status" style="color:#ebd296">${escapeHtml(p.effects.join("  "))}</div>`;
  }
  const text = p.inZone ? "IN ZONE" : "GO TO ZONE";
  const color = p.inZone ? "#8ce68c" : "#ff965a";
  return `<div class="player-status" style="color:${color}">${text}</div>`;
}

function renderPips(lives: number): string {
  if (lives < 0) return "";
  const slots = Math.max(5, lives);
  let out = "";
  for (let i = 0; i < slots; i++) {
    out += `<span class="pip${i < lives ? " on" : ""}"></span>`;
  }
  return out;
}

function centerHead(game: GameView): string {
  const color = STATE_COLORS[game.state] ?? "#fff";
  const hud = game.hudLines.join("    ");
  const line =
    game.state === STATE_GAMEOVER && game.resultTitle
      ? `${game.resultTitle} — ${game.resultSubtitle ?? ""}`
      : hud;
  return `
    <div class="center-head">
      <div class="center-mode">${escapeHtml(game.modeName)}</div>
      <div class="center-value" style="color:${color}">${escapeHtml(game.centerValue)}</div>
      <div class="center-state" style="color:${color}">${escapeHtml(game.stateName)}</div>
      <div class="center-hud">${escapeHtml(line)}</div>
    </div>`;
}

export function renderFooter(el: HTMLElement, status: StatusView): void {
  let dotCls = "";
  let serial: string;
  if (status.virtual) {
    dotCls = "sim";
    serial = "VIRTUAL SIM";
  } else if (!status.serialConnected) {
    serial = "SERIAL --";
  } else {
    dotCls = "ok";
    serial = `SERIAL OK${status.serialPort ? " " + status.serialPort : ""}`;
  }
  const filt = `Clamp ${onOff(status.useSpeedClamp)} · EMA ${onOff(status.useEma)} a=${status.smoothAlpha.toFixed(2)}`;
  el.innerHTML = [
    `<span><span class="status-dot ${dotCls}"></span>${escapeHtml(serial)}</span>`,
    `<span>OSC ${escapeHtml(status.oscIp)}:${status.oscPort} · sent ${status.oscSent}</span>`,
    `<span>frames ${status.frames} · ${status.fps} fps</span>`,
    `<span>${filt}</span>`,
    `<span class="footer-hint">V virtual · R reset · SPACE start · TAB setup · M mode · H headset</span>`,
  ].join("");
}

function onOff(b: boolean): string {
  return b ? "ON" : "OFF";
}

export function renderOverlays(el: HTMLElement, game: GameView, status: StatusView): void {
  const warns: { text: string; cls: string }[] = [];
  if (!status.virtual && !status.serialConnected) {
    warns.push({ text: "SERIAL NOT CONNECTED — searching port", cls: "" });
  } else if (!status.virtual && status.lastFrameAgeMs > 2000) {
    warns.push({ text: "NO TAG DATA FOR >2s", cls: "" });
  }
  if (status.unknownTagId !== null) {
    warns.push({
      text: `UNKNOWN TagID 0x${status.unknownTagId.toString(16).toUpperCase().padStart(4, "0")} — check TAG0_ID/TAG1_ID`,
      cls: "warm",
    });
  }
  for (let i = 0; i < 2; i++) {
    const o = game.oob[i];
    if (o.active) {
      warns.push({
        text: `P${i + 1}: GO BACK NOW OR LOSE A LIFE (${Math.max(0, Math.ceil(o.seconds))}s)`,
        cls: "",
      });
    }
  }
  el.innerHTML = warns
    .map((w) => `<div class="warn ${w.cls}">${escapeHtml(w.text)}</div>`)
    .join("");
}

export function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
