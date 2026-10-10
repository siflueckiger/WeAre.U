"""Virtual play mode: two keyboard-driven players fed into the same TagData
pipeline the serial frames use. Debug without UWB hardware.

WASD = P1, arrow keys = P2. main.py orchestrates the toggle.
"""

from shared.protocol import TAG0_ID, TAG1_ID
from sender_py.tracker import TagData

VIRTUAL_SPEED_MM_S = 1500.0


class VirtualTags:
    def __init__(self, tracker, osc, p1_start, p2_start):
        self.tracker = tracker
        self.osc = osc
        self.p1_start = p1_start
        self.p2_start = p2_start
        self.on = False
        self.keys = set()          # held pygame key constants
        self.last_ms = 0
        # key bindings, set by main
        self.w = self.s = self.a = self.d = None
        self.up = self.down = self.left = self.right = None

    def bind(self, w, a, s, d, up, down, left, right):
        self.w, self.a, self.s, self.d = w, a, s, d
        self.up, self.down, self.left, self.right = up, down, left, right

    # ---- lifecycle (called by main) ----
    def enable(self, now_ms):
        self.on = True
        self.ensure_players(now_ms)
        print("Virtual play: ON (WASD = P1, arrows = P2)")

    def disable(self):
        self.on = False
        self.clear_players()
        self.keys.clear()
        self.last_ms = 0
        print("Virtual play: OFF")

    def ensure_players(self, now_ms):
        self.last_ms = 0
        for tid, start in ((TAG0_ID, self.p1_start), (TAG1_ID, self.p2_start)):
            t = self.tracker.tags.get(tid)
            if t is None:
                t = TagData(tid)
                self.tracker.tags[tid] = t
            if t.pos is None:
                t.pos = (start[0], start[1])
                t.speed_ms = 0.0
                t.last_fix_ms = now_ms
                self.osc.pos(tid, t.pos[0], t.pos[1])

    def clear_players(self):
        for tid in (TAG0_ID, TAG1_ID):
            t = self.tracker.tags.get(tid)
            if t is None:
                continue
            t.pos = None
            t.trail.clear()
            t.speed_ms = 0.0
            t.last_fix_ms = 0

    def reset_players(self, now_ms):
        for tid, start in ((TAG0_ID, self.p1_start), (TAG1_ID, self.p2_start)):
            t = self.tracker.tags.get(tid)
            if t is None:
                t = TagData(tid)
                self.tracker.tags[tid] = t
            t.pos = (start[0], start[1])
            t.trail.clear()
            t.speed_ms = 0.0
            t.last_fix_ms = now_ms
            self.osc.pos(tid, t.pos[0], t.pos[1])
        self.last_ms = 0

    # ---- per-frame ----
    def update(self, now_ms):
        if not self.on:
            return
        if self.last_ms == 0:
            self.last_ms = now_ms
        dt = (now_ms - self.last_ms) / 1000.0
        self.last_ms = now_ms
        dt = max(0.0, min(dt, 0.25))
        self.tracker.last_frame_ms = now_ms   # keep "no data" warning quiet
        self._move(TAG0_ID, self.w, self.s, self.a, self.d, dt, now_ms)
        self._move(TAG1_ID, self.up, self.down, self.left, self.right, dt, now_ms)

    def _move(self, tid, up, down, left, right, dt, now_ms):
        dx = dy = 0.0
        if up in self.keys:
            dy += 1
        if down in self.keys:
            dy -= 1
        if left in self.keys:
            dx -= 1
        if right in self.keys:
            dx += 1
        t = self.tracker.tags.get(tid)
        if t is None or t.pos is None:
            return
        speed = 0.0
        if dx or dy:
            mag = (dx * dx + dy * dy) ** 0.5
            dx /= mag
            dy /= mag
            speed = VIRTUAL_SPEED_MM_S
            t.pos = (t.pos[0] + dx * speed * dt, t.pos[1] + dy * speed * dt)
        t.speed_ms = speed
        t.trail.append(t.pos)
        t.last_fix_ms = now_ms
        self.osc.pos(tid, t.pos[0], t.pos[1])
