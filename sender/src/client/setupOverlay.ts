/**
 * Mobile- and touch-friendly setup panel (TAB). Six measured anchor distances,
 * circle-intersection auto-layout, tag capture and config save. Anchors and
 * start zones are dragged directly on the canvas.
 */
import { START_ZONE_RADIUS_MM, type Vec2 } from "../shared/protocol.js";
import type { ClientMessage, GameView, StatusView } from "../shared/types.js";
import type { Camera } from "./canvas.js";
import { escapeHtml } from "./hud.js";

const D_PAIRS = ["A0-A1", "A0-A2", "A0-A3", "A1-A2", "A1-A3", "A2-A3"];

export interface SetupPanel {
  el: HTMLElement;
  update(status: StatusView): void;
}

export function createSetupPanel(send: (msg: ClientMessage) => void): SetupPanel {
  const el = document.createElement("div");
  el.innerHTML = `
    <h2>SETUP-MODUS</h2>
    <div class="sub">Anker-Distanzen (gemessen, mm) · TAB zurück zum Spiel</div>
    <div id="dist-rows"></div>
    <div class="row">
      <button class="primary" id="btn-layout">Auto-Layout (Kreisschnitt)</button>
      <button id="btn-standard">Standard 3x7m</button>
    </div>
    <div class="row">
      <button id="btn-cap1">Tag-Capture P1 (Z)</button>
      <button id="btn-cap2">Tag-Capture P2 (X)</button>
    </div>
    <div class="row">
      <button id="btn-save">Config speichern (V)</button>
    </div>
    <div class="status" id="setup-status"></div>
    <div class="sub">Anker &amp; Startzonen im Feld mit Finger/Maus ziehen.</div>
  `;

  const rowsEl = el.querySelector<HTMLDivElement>("#dist-rows")!;
  const inputs: HTMLInputElement[] = [];
  const rowEls: HTMLDivElement[] = [];
  for (let i = 0; i < 6; i++) {
    const row = document.createElement("div");
    row.className = "dist-row";
    const label = document.createElement("label");
    label.textContent = D_PAIRS[i];
    const input = document.createElement("input");
    input.type = "number";
    input.inputMode = "decimal";
    input.step = "1";
    input.value = "0";
    input.addEventListener("input", () => {
      send({ type: "setup.setDistances", distances: inputs.map((x) => Number(x.value) || 0) });
    });
    row.appendChild(label);
    row.appendChild(input);
    rowsEl.appendChild(row);
    inputs.push(input);
    rowEls.push(row);
  }

  el.querySelector("#btn-layout")!.addEventListener("click", () => {
    send({ type: "setup.applyLayout" });
  });
  el.querySelector("#btn-standard")!.addEventListener("click", () => {
    send({ type: "setup.standardLayout" });
  });
  el.querySelector("#btn-cap1")!.addEventListener("click", () => {
    send({ type: "setup.captureZone", player: 0 });
  });
  el.querySelector("#btn-cap2")!.addEventListener("click", () => {
    send({ type: "setup.captureZone", player: 1 });
  });
  el.querySelector("#btn-save")!.addEventListener("click", () => {
    send({ type: "setup.save" });
  });

  const statusEl = el.querySelector<HTMLDivElement>("#setup-status")!;

  return {
    el,
    update(status: StatusView): void {
      const dists = status.setup.distances;
      for (let i = 0; i < inputs.length; i++) {
        if (document.activeElement !== inputs[i]) {
          const v = Math.round(dists[i] ?? 0);
          if (inputs[i].value !== String(v)) inputs[i].value = String(v);
        }
      }
      statusEl.innerHTML = status.setup.status ? escapeHtml(status.setup.status) : "";
    },
  };
}

export type SetupHit =
  | { kind: "anchor"; index: number }
  | { kind: "zone"; player: number }
  | null;

/** Hit-test anchors (priority) and start zones in screen space. */
export function hitTestSetup(
  cam: Camera,
  game: GameView,
  px: number,
  py: number,
): SetupHit {
  // zones first (larger grab target), then anchors on top
  for (const [player, zone] of [
    [1, game.startZones[1]],
    [0, game.startZones[0]],
  ] as [number, Vec2][]) {
    const qx = cam.sx(zone[0]);
    const qy = cam.sy(zone[1]);
    if (Math.hypot(px - qx, py - qy) < Math.max(20, START_ZONE_RADIUS_MM * cam.s)) {
      return { kind: "zone", player };
    }
  }
  for (const i of [3, 2, 1, 0]) {
    const qx = cam.sx(game.anchors.ax[i]);
    const qy = cam.sy(game.anchors.ay[i]);
    if (Math.hypot(px - qx, py - qy) < 20) return { kind: "anchor", index: i };
  }
  return null;
}
