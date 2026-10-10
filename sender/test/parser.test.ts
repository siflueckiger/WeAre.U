import { describe, expect, it } from "vitest";
import { FrameParser, FRAME_LEN } from "../src/server/serial.js";

function buildFrame(tagid: number, mask: number, kalman: number[]): Buffer {
  const b = Buffer.alloc(FRAME_LEN);
  b.write("CmdM:4", 0, "ascii");
  b.writeUInt8(91, 6);
  b.writeUInt16LE(tagid, 11);
  b.writeUInt8(mask, 16);
  for (let i = 0; i < 8; i++) b.writeUInt32LE(kalman[i] >>> 0, 50 + i * 4);
  return b;
}

describe("FrameParser", () => {
  it("parses a whole CmdM:4 frame", () => {
    const p = new FrameParser();
    const kalman = [100, 200, 300, 400, 0, 0, 0, 0];
    p.push(buildFrame(1, 0b1111, kalman));
    const f = p.next();
    expect(f).not.toBeNull();
    expect(f!.tagid).toBe(1);
    expect(f!.mask).toBe(0b1111);
    expect(f!.kalman.slice(0, 4)).toEqual(kalman.slice(0, 4));
    expect(p.next()).toBeNull();
  });

  it("handles frames split across chunks", () => {
    const p = new FrameParser();
    const frame = buildFrame(0, 0b1111, [10, 20, 30, 40, 0, 0, 0, 0]);
    p.push(frame.subarray(0, 40));
    expect(p.next()).toBeNull();
    p.push(frame.subarray(40));
    const f = p.next();
    expect(f).not.toBeNull();
    expect(f!.tagid).toBe(0);
    expect(f!.kalman[3]).toBe(40);
  });

  it("skips noise and rejects frames with the wrong length byte", () => {
    const p = new FrameParser();
    const bogus = Buffer.from("CmdM:4xxxxxx");
    bogus.writeUInt8(10, 6); // wrong length
    p.push(bogus);
    expect(p.next()).toBeNull();
    p.push(buildFrame(1, 1, [7, 0, 0, 0, 0, 0, 0, 0]));
    const f = p.next();
    expect(f).not.toBeNull();
    expect(f!.tagid).toBe(1);
    expect(f!.kalman[0]).toBe(7);
  });

  it("parses two consecutive frames", () => {
    const p = new FrameParser();
    p.push(buildFrame(0, 1, [1, 0, 0, 0, 0, 0, 0, 0]));
    p.push(buildFrame(1, 2, [2, 0, 0, 0, 0, 0, 0, 0]));
    expect(p.next()!.tagid).toBe(0);
    expect(p.next()!.tagid).toBe(1);
    expect(p.next()).toBeNull();
  });
});
