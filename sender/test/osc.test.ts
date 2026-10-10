import { describe, expect, it } from "vitest";
import { encodeMessage, type OscArg } from "../src/server/osc.js";

function readString(buf: Buffer, offset: { v: number }): string {
  const end = buf.indexOf(0, offset.v);
  const s = buf.toString("ascii", offset.v, end);
  offset.v += (end - offset.v + 1 + 3) & ~3;
  return s;
}

function decode(buf: Buffer): { address: string; tags: string; args: Array<number | string> } {
  const offset = { v: 0 };
  const address = readString(buf, offset);
  const tags = readString(buf, offset).slice(1);
  const args: Array<number | string> = [];
  for (const t of tags) {
    if (t === "i") {
      args.push(buf.readInt32BE(offset.v));
      offset.v += 4;
    } else if (t === "f") {
      args.push(buf.readFloatBE(offset.v));
      offset.v += 4;
    } else {
      args.push(readString(buf, offset));
    }
  }
  return { address, tags, args };
}

describe("OSC encoding", () => {
  it("encodes int and float args big-endian with correct type tags", () => {
    const args: OscArg[] = [
      { t: "i", v: 1 },
      { t: "i", v: 30 },
      { t: "i", v: 3 },
      { t: "i", v: 2 },
      { t: "i", v: -1 },
    ];
    const d = decode(encodeMessage("/game/stats", args));
    expect(d.address).toBe("/game/stats");
    expect(d.tags).toBe("iiiii");
    expect(d.args).toEqual([1, 30, 3, 2, -1]);
  });

  it("encodes strings and floats", () => {
    const d = decode(
      encodeMessage("/game/mode", [
        { t: "s", v: "coinHunt" },
        { t: "s", v: "Coin Hunt" },
      ]),
    );
    expect(d.tags).toBe("ss");
    expect(d.args).toEqual(["coinHunt", "Coin Hunt"]);

    const f = decode(
      encodeMessage("/p1/pos", [
        { t: "f", v: 3000.5 },
        { t: "f", v: 1500.25 },
      ]),
    );
    expect(f.tags).toBe("ff");
    expect(f.args[0] as number).toBeCloseTo(3000.5, 3);
    expect(f.args[1] as number).toBeCloseTo(1500.25, 3);
  });

  it("encodes the 9-arg entity upsert", () => {
    const d = decode(
      encodeMessage("/ent/upsert", [
        { t: "i", v: 5 },
        { t: "s", v: "coin" },
        { t: "f", v: 1234 },
        { t: "f", v: 2345 },
        { t: "f", v: 120 },
        { t: "i", v: 255 },
        { t: "i", v: 220 },
        { t: "i", v: 40 },
        { t: "s", v: "MAG" },
      ]),
    );
    expect(d.address).toBe("/ent/upsert");
    expect(d.tags).toBe("isfffiiis");
    expect(d.args).toEqual([5, "coin", 1234, 2345, 120, 255, 220, 40, "MAG"]);
  });
});
