/**
 * Browser entry point: WebSocket client, high-DPI canvas render loop, keyboard
 * shortcuts and setup-mode pointer dragging.
 */
import type { ClientMessage, GameView, ServerMessage, StatusView } from "../shared/types.js";
import { Camera, renderField } from "./canvas.js";
import { renderFooter, renderHeader, renderOverlays } from "./hud.js";
import { createSetupPanel, hitTestSetup, type SetupHit, type SetupPanel } from "./setupOverlay.js";
import { createVirtualInput } from "./virtualInput.js";

const canvas = document.querySelector<HTMLCanvasElement>("#field")!;
const wrap = document.querySelector<HTMLElement>("#field-wrap")!;
const headerEl = document.querySelector<HTMLElement>("#hud-header")!;
const footerEl = document.querySelector<HTMLElement>("#hud-footer")!;
const overlaysEl = document.querySelector<HTMLElement>("#overlays")!;
const setupEl = document.querySelector<HTMLElement>("#setup-panel")!;
const touchEl = document.querySelector<HTMLElement>("#touch-controls")!;

const ctx = canvas.getContext("2d", { alpha: false })!;
const cam = new Camera();

let latest: { game: GameView; status: StatusView } | null = null;
let socket: WebSocket | null = null;
let cssW = 1;
let cssH = 1;
let dpr = window.devicePixelRatio || 1;

function send(msg: ClientMessage): void {
  if (socket && socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(msg));
}

const panel: SetupPanel = createSetupPanel(send);
setupEl.appendChild(panel.el);

const virtual = createVirtualInput(send, touchEl);

// ============================ websocket ============================
function connect(): void {
  const proto = location.protocol === "https:" ? "wss" : "ws";
  const ws = new WebSocket(`${proto}://${location.host}/ws`);
  socket = ws;
  ws.onmessage = (ev) => {
    try {
      const msg = JSON.parse(ev.data as string) as ServerMessage;
      if (msg.type === "snapshot") {
        latest = { game: msg.game, status: msg.status };
        virtual.setVirtual(msg.status.virtual);
      }
    } catch {
      /* ignore */
    }
  };
  ws.onclose = () => {
    socket = null;
    setTimeout(connect, 1000);
  };
  ws.onerror = () => ws.close();
}

// ============================ canvas sizing ============================
function resize(): void {
  dpr = window.devicePixelRatio || 1;
  const rect = wrap.getBoundingClientRect();
  cssW = Math.max(1, rect.width);
  cssH = Math.max(1, rect.height);
  const bw = Math.max(1, Math.round(cssW * dpr));
  const bh = Math.max(1, Math.round(cssH * dpr));
  if (canvas.width !== bw || canvas.height !== bh) {
    canvas.width = bw;
    canvas.height = bh;
  }
}
window.addEventListener("resize", resize);
new ResizeObserver(resize).observe(wrap);

// ============================ render loop ============================
function frame(): void {
  if (latest) {
    const setupActive = latest.status.appMode === "setup";
    setupEl.classList.toggle("hidden", !setupActive);
    resize();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    renderField(ctx, cssW, cssH, latest.game, cam, setupActive);
    renderHeader(headerEl, latest.game);
    renderFooter(footerEl, latest.status);
    renderOverlays(overlaysEl, latest.game, latest.status);
    if (setupActive) panel.update(latest.status);
  }
  requestAnimationFrame(frame);
}

// ============================ setup dragging ============================
let drag: { hit: SetupHit; active: boolean } = { hit: null, active: false };

function pointerPos(e: PointerEvent): [number, number] {
  const rect = canvas.getBoundingClientRect();
  return [e.clientX - rect.left, e.clientY - rect.top];
}

canvas.addEventListener("pointerdown", (e) => {
  if (!latest || latest.status.appMode !== "setup") return;
  const [px, py] = pointerPos(e);
  const hit = hitTestSetup(cam, latest.game, px, py);
  if (hit) {
    drag = { hit, active: true };
    canvas.setPointerCapture(e.pointerId);
  }
});
canvas.addEventListener("pointermove", (e) => {
  if (!drag.active || drag.hit === null) return;
  const [px, py] = pointerPos(e);
  const [wx, wy] = cam.worldFromScreen(px, py);
  if (drag.hit.kind === "anchor") {
    send({ type: "setup.dragAnchor", index: drag.hit.index, x: wx, y: wy, commit: false });
  } else {
    send({ type: "setup.dragZone", player: drag.hit.player, x: wx, y: wy, commit: false });
  }
});
function endDrag(e: PointerEvent): void {
  if (!drag.active || drag.hit === null) return;
  const [px, py] = pointerPos(e);
  const [wx, wy] = cam.worldFromScreen(px, py);
  if (drag.hit.kind === "anchor") {
    send({ type: "setup.dragAnchor", index: drag.hit.index, x: wx, y: wy, commit: true });
  } else {
    send({ type: "setup.dragZone", player: drag.hit.player, x: wx, y: wy, commit: true });
  }
  drag = { hit: null, active: false };
}
canvas.addEventListener("pointerup", endDrag);
canvas.addEventListener("pointercancel", endDrag);

// ============================ keyboard ============================
window.addEventListener("keydown", (e) => {
  if (isTextInput(e.target)) return;
  if (virtual.handleKey(e.code, true)) return;
  if (e.code === "Tab") {
    e.preventDefault();
    send({ type: "mode", mode: latest?.status.appMode === "setup" ? "game" : "setup" });
    return;
  }
  if (e.code === "KeyV") {
    send({ type: "virtual", on: !(latest?.status.virtual ?? false) });
    return;
  }
  if (e.code === "KeyR") {
    send({ type: "reset" });
    return;
  }
  if (e.code === "Space") {
    e.preventDefault();
    send({ type: "start" });
    return;
  }
  if (e.code === "KeyM") {
    send({ type: "nextMode" });
    return;
  }
  if (latest?.status.appMode === "setup") {
    if (e.code === "KeyZ") send({ type: "setup.captureZone", player: 0 });
    else if (e.code === "KeyX") send({ type: "setup.captureZone", player: 1 });
    else if (e.code === "KeyL") send({ type: "setup.applyLayout" });
    else if (e.code === "KeyS" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      send({ type: "setup.save" });
    }
  }
});
window.addEventListener("keyup", (e) => {
  virtual.handleKey(e.code, false);
});

function isTextInput(target: EventTarget | null): boolean {
  const el = target as HTMLElement | null;
  if (!el) return false;
  const tag = el.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
}

connect();
resize();
requestAnimationFrame(frame);
