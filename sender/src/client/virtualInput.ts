/**
 * Virtual play input: keyboard (WASD = P1, arrows = P2) plus on-screen D-pads
 * for touch devices. Sends the currently held movement tokens to the server.
 */
import type { ClientMessage, VirtualKey } from "../shared/types.js";

const P1_MAP: Record<string, VirtualKey> = {
  KeyW: "w",
  KeyA: "a",
  KeyS: "s",
  KeyD: "d",
};
const P2_MAP: Record<string, VirtualKey> = {
  ArrowUp: "up",
  ArrowDown: "down",
  ArrowLeft: "left",
  ArrowRight: "right",
};

export interface VirtualInput {
  /** Returns true when the key was consumed as a movement key. */
  handleKey(code: string, down: boolean): boolean;
  setVirtual(on: boolean): void;
  /** true while any movement key is held (used to suppress shortcuts) */
  hasMovement(): boolean;
  destroy(): void;
}

export function createVirtualInput(
  send: (msg: ClientMessage) => void,
  touchRoot: HTMLElement,
): VirtualInput {
  const held = new Set<VirtualKey>();
  let virtualOn = false;

  const flush = (): void => {
    send({ type: "keys", keys: [...held] });
  };

  const add = (k: VirtualKey): void => {
    if (held.has(k)) return;
    held.add(k);
    flush();
  };
  const remove = (k: VirtualKey): void => {
    if (!held.has(k)) return;
    held.delete(k);
    flush();
  };

  const isTextInput = (target: EventTarget | null): boolean => {
    const el = target as HTMLElement | null;
    if (!el) return false;
    const tag = el.tagName;
    return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || el.isContentEditable;
  };

  const onKeyDown = (e: KeyboardEvent): void => {
    if (!virtualOn || isTextInput(e.target)) return;
    const token = P1_MAP[e.code] ?? P2_MAP[e.code];
    if (token === undefined) return;
    e.preventDefault();
    add(token);
  };
  const onKeyUp = (e: KeyboardEvent): void => {
    if (isTextInput(e.target)) return;
    const token = P1_MAP[e.code] ?? P2_MAP[e.code];
    if (token === undefined) return;
    e.preventDefault();
    remove(token);
  };
  window.addEventListener("keydown", onKeyDown);
  window.addEventListener("keyup", onKeyUp);

  // ---- touch D-pads ----
  touchRoot.innerHTML = "";
  const pads: { label: string; tokens: Record<string, VirtualKey> }[] = [
    { label: "P1", tokens: { up: "w", down: "s", left: "a", right: "d" } },
    { label: "P2", tokens: { up: "up", down: "down", left: "left", right: "right" } },
  ];
  for (const pad of pads) {
    const dpad = document.createElement("div");
    dpad.className = "dpad";
    const cells: { key: string; glyph: string }[] = [
      { key: "spacer", glyph: "" },
      { key: "up", glyph: "▲" },
      { key: "spacer2", glyph: "" },
      { key: "left", glyph: "◀" },
      { key: "spacer3", glyph: "" },
      { key: "right", glyph: "▶" },
      { key: "spacer4", glyph: "" },
      { key: "down", glyph: "▼" },
      { key: "spacer5", glyph: "" },
    ];
    for (const cell of cells) {
      const token = pad.tokens[cell.key];
      if (token === undefined) {
        const spacer = document.createElement("div");
        spacer.className = "spacer";
        dpad.appendChild(spacer);
        continue;
      }
      const btn = document.createElement("button");
      btn.className = "touch-btn";
      btn.textContent = cell.glyph;
      const press = (e: PointerEvent): void => {
        e.preventDefault();
        btn.setPointerCapture?.(e.pointerId);
        btn.classList.add("active");
        add(token);
      };
      const release = (e: PointerEvent): void => {
        e.preventDefault();
        btn.classList.remove("active");
        remove(token);
      };
      btn.addEventListener("pointerdown", press);
      btn.addEventListener("pointerup", release);
      btn.addEventListener("pointercancel", release);
      btn.addEventListener("pointerleave", release);
      dpad.appendChild(btn);
    }
    touchRoot.appendChild(dpad);
  }

  return {
    handleKey(code: string, down: boolean): boolean {
      const token = P1_MAP[code] ?? P2_MAP[code];
      if (token === undefined) return false;
      if (!virtualOn) return false;
      if (down) add(token);
      else remove(token);
      return true;
    },
    setVirtual(on: boolean): void {
      virtualOn = on;
      touchRoot.classList.toggle("hidden", !on);
      if (!on) {
        for (const k of [...held]) remove(k);
      }
    },
    hasMovement(): boolean {
      return held.size > 0;
    },
    destroy(): void {
      window.removeEventListener("keydown", onKeyDown);
      window.removeEventListener("keyup", onKeyUp);
    },
  };
}
