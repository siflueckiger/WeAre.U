import { describe, expect, it } from "vitest";
import { Tracker, TagData } from "../src/server/tracker.js";

const AX = [0, 1000, 1000, 0];
const AY = [0, 0, 1000, 1000];

function kalmanFor(x: number, y: number): number[] {
  const k = [0, 0, 0, 0, 0, 0, 0, 0];
  for (let i = 0; i < 4; i++) k[i] = Math.round(Math.hypot(AX[i] - x, AY[i] - y));
  return k;
}

describe("Tracker trilateration", () => {
  it("recovers a point from four exact distances", () => {
    const t = new Tracker();
    t.setAnchors(AX, AY);
    const tag = new TagData(0);
    tag.mask = 0b1111;
    tag.kalman = kalmanFor(300, 400);
    const p = t.trilaterate(tag);
    expect(p).not.toBeNull();
    // integer mm distances introduce sub-mm rounding error
    expect(p![0]).toBeCloseTo(300, 0);
    expect(p![1]).toBeCloseTo(400, 0);
  });

  it("returns null with fewer than three anchors", () => {
    const t = new Tracker();
    t.setAnchors(AX, AY);
    const tag = new TagData(0);
    tag.mask = 0b0011;
    tag.kalman = kalmanFor(300, 400);
    expect(t.trilaterate(tag)).toBeNull();
  });

  it("returns the first fix unchanged and then clamps fast jumps", () => {
    const t = new Tracker({ useSpeedClamp: true, useEma: false });
    t.setAnchors(AX, AY);
    t.handleFrame(0, 0b1111, kalmanFor(100, 100));
    const first = t.tags.get(0)!;
    expect(first.pos![0]).toBeCloseTo(100, 0);
    expect(first.pos![1]).toBeCloseTo(100, 0);

    // a 900 mm jump within a few ms must be clamped far below 900 mm
    t.handleFrame(0, 0b1111, kalmanFor(1000, 100));
    const moved = Math.hypot(first.pos![0] - 100, first.pos![1] - 100);
    expect(moved).toBeLessThan(200);
    expect(moved).toBeGreaterThan(0);
  });

  it("applies EMA smoothing toward the new fix", () => {
    const t = new Tracker({ useSpeedClamp: false, useEma: true, smoothAlpha: 0.5 });
    t.setAnchors(AX, AY);
    t.handleFrame(0, 0b1111, kalmanFor(0, 0));
    t.handleFrame(0, 0b1111, kalmanFor(200, 0));
    const p = t.tags.get(0)!.pos!;
    // EMA = 0 + 0.5*(200-0) = 100
    expect(p[0]).toBeGreaterThan(50);
    expect(p[0]).toBeLessThan(150);
  });

  it("computes field bounds from the anchors", () => {
    const t = new Tracker();
    t.setAnchors(AX, AY);
    expect(t.fieldBounds()).toEqual([0, 1000, 0, 1000]);
  });
});
