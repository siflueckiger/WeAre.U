"""Position tracking: UWB frame ingestion, 4-anchor trilateration and filters.

Direct port of the math in the original `sender/sender.pde` (functions
`trilaterate`, `handleFrame`). Coordinates are in mm, X/Y in the field frame.
"""

import time
from collections import deque

from shared.protocol import (
    TAG0_ID, TAG1_ID, TRAIL_MAX, DEFAULT_AX, DEFAULT_AY,
)


def _lerp(a, b, t):
    return a + (b - a) * t


class TagData:
    def __init__(self, tag_id):
        self.id = tag_id
        self.mask = 0
        self.kalman = [0] * 8
        self.speed_ms = 0.0
        self.pos = None               # (x, y) mm or None
        self.last_fix_ms = 0
        self.trail = deque(maxlen=TRAIL_MAX)


class Tracker:
    """Owns the tag state and the coordinate computation."""

    def __init__(self, use_speed_clamp=True, use_ema=True,
                 max_speed_mm_s=4200.0, smooth_alpha=0.30):
        self.tags = {}
        self.seen_ids = set()
        self.frames = 0
        self.last_frame_ms = 0
        self.ax = list(DEFAULT_AX)
        self.ay = list(DEFAULT_AY)
        self.use_speed_clamp = use_speed_clamp
        self.use_ema = use_ema
        self.max_speed_mm_s = max_speed_mm_s
        self.smooth_alpha = smooth_alpha

    # ---- anchors ----
    def set_anchors(self, ax, ay):
        self.ax = list(ax)
        self.ay = list(ay)

    def field_bounds(self):
        return (min(self.ax), max(self.ax), min(self.ay), max(self.ay))

    # ---- frame ingestion (called from the serial thread) ----
    def handle_frame(self, tagid, mask, kalman):
        now = _now_ms()
        self.frames += 1
        self.last_frame_ms = now
        self.seen_ids.add(tagid)

        t = self.tags.get(tagid)
        if t is None:
            t = TagData(tagid)
            self.tags[tagid] = t
        t.mask = mask
        t.kalman = list(kalman)

        if tagid not in (TAG0_ID, TAG1_ID):
            return
        p = self.trilaterate(t)
        if p is None:
            return

        first = (t.pos is None or t.last_fix_ms == 0)
        if not first and self.use_speed_clamp:
            dt = (now - t.last_fix_ms) / 1000.0
            max_d = self.max_speed_mm_s * max(dt, 0.02)
            dx, dy = p[0] - t.pos[0], p[1] - t.pos[1]
            d = (dx * dx + dy * dy) ** 0.5
            if d > max_d and d > 0:
                p = (t.pos[0] + dx / d * max_d, t.pos[1] + dy / d * max_d)

        old = t.pos
        if not first and self.use_ema:
            t.pos = (_lerp(t.pos[0], p[0], self.smooth_alpha),
                     _lerp(t.pos[1], p[1], self.smooth_alpha))
        else:
            t.pos = p

        if not first and old is not None:
            dt = (now - t.last_fix_ms) / 1000.0
            if dt > 0:
                t.speed_ms = _dist(old, t.pos) / dt

        t.trail.append(t.pos)
        t.last_fix_ms = now

    def trilaterate(self, t):
        ax, ay = self.ax, self.ay
        n = sum(1 for i in range(4) if (t.mask & (1 << i)) and t.kalman[i] > 0)
        if n < 3:
            return None
        r = -1
        for i in range(4):
            if (t.mask & (1 << i)) and t.kalman[i] > 0:
                r = i
                break
        if r < 0:
            return None
        dr = t.kalman[r]

        sxx = sxy = syy = sbx = sby = 0.0
        for j in range(4):
            if j == r or not (t.mask & (1 << j)) or t.kalman[j] <= 0:
                continue
            a = 2 * (ax[j] - ax[r])
            b = 2 * (ay[j] - ay[r])
            c = (dr * dr - t.kalman[j] * t.kalman[j]
                 - (ax[r] * ax[r] + ay[r] * ay[r])
                 + (ax[j] * ax[j] + ay[j] * ay[j]))
            sxx += a * a
            sxy += a * b
            syy += b * b
            sbx += a * c
            sby += b * c

        det = sxx * syy - sxy * sxy
        if abs(det) < 1e-6:
            return None
        x = (syy * sbx - sxy * sby) / det
        y = (sxx * sby - sxy * sbx) / det
        return (x, y)


def _now_ms():
    return int(time.monotonic() * 1000)


def _dist(a, b):
    dx = a[0] - b[0]
    dy = a[1] - b[1]
    return (dx * dx + dy * dy) ** 0.5
