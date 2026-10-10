import { performance } from "node:perf_hooks";

/** Monotonic milliseconds, analogous to Python's `time.monotonic() * 1000`. */
export function nowMs(): number {
  return Math.round(performance.now());
}
