"""Engine: shared state machine, round timer, out-of-bounds and entity sync.

The engine owns WAIT -> READY -> PLAYING -> GAMEOVER. Modes implement only the
round content via `modes/base.py`.
"""

import time

from shared.protocol import (
    STATE_WAIT, STATE_PLAYING, STATE_GAMEOVER, STATE_READY,
    START_ZONE_RADIUS_MM, TAG0_ID, TAG1_ID,
)
from sender_py.modes.coin_hunt import CoinHunt


def now_ms():
    return int(time.monotonic() * 1000)


class GameEngine:
    READY_S = 3
    GAMEOVER_S = 10
    GAME_TIME_S = 30
    OOB_MARGIN_MM = 400
    OOB_TIMEOUT_S = 5
    OSC_GAME_INTERVAL_MS = 100

    def __init__(self, osc, tracker, entities, p1_start, p2_start):
        self.osc = osc
        self.tracker = tracker
        self.entities = entities
        self.p1_start = p1_start
        self.p2_start = p2_start

        self.state = STATE_WAIT
        self.time_left = 0.0
        self.state_entered_ms = now_ms()
        self.last_tick_ms = now_ms()
        self.last_game_osc_ms = 0
        self.oob_countdown = [float(self.OOB_TIMEOUT_S)] * 2
        self.oob_active = [False, False]
        self.round_winner = -1

        self.modes = [CoinHunt(self)]
        self.mode_index = 0
        self.mode = self.modes[0]

    # ============================ helpers ============================
    @property
    def tags(self):
        return self.tracker.tags

    def field_bounds(self):
        return self.tracker.field_bounds()

    def in_zone(self, tag, zone):
        if tag is None or tag.pos is None:
            return False
        dx = tag.pos[0] - zone[0]
        dy = tag.pos[1] - zone[1]
        return (dx * dx + dy * dy) ** 0.5 < START_ZONE_RADIUS_MM

    def state_name(self):
        from shared.protocol import STATE_NAMES
        return STATE_NAMES.get(self.state, "?")

    # ============================ state machine ============================
    def set_state(self, s):
        self.state = s
        self.state_entered_ms = now_ms()
        self.last_tick_ms = now_ms()
        self.last_game_osc_ms = 0            # force immediate /game/stats
        if s == STATE_PLAYING:
            self.round_winner = -1
            for i in range(2):
                self.oob_countdown[i] = float(self.OOB_TIMEOUT_S)
                self.oob_active[i] = False
        else:
            # every non-playing state cleans up
            self.entities.clear()
            for i in range(2):
                self.oob_countdown[i] = float(self.OOB_TIMEOUT_S)
                self.oob_active[i] = False
            self.round_winner = -1
            self.time_left = self.READY_S if s == STATE_READY else 0.0
            self.mode.on_round_end()
        print("game state ->", self.state_name())

    def request_end(self):
        if self.state == STATE_PLAYING:
            self.set_state(STATE_GAMEOVER)

    def debug_start_round(self):
        self.mode.on_round_start()
        self.set_state(STATE_PLAYING)

    def reset_round(self):
        self.set_state(STATE_WAIT)

    def next_mode(self):
        if len(self.modes) <= 1:
            self.entities.clear()
            self.mode.on_round_end()
            self.set_state(STATE_WAIT)
            self.send_mode_osc()
            print("mode reset ->", self.mode.display_name)
            return
        self.mode_index = (self.mode_index + 1) % len(self.modes)
        self.mode = self.modes[self.mode_index]
        self.entities.clear()
        self.mode.on_mode_enter()
        self.set_state(STATE_WAIT)
        self.send_mode_osc()

    def set_mode_by_id(self, mode_id):
        for i, m in enumerate(self.modes):
            if m.id == mode_id:
                self.mode_index = i
                self.mode = m
                return

    # ============================ per-frame ============================
    def update(self):
        t0 = self.tags.get(TAG0_ID)
        t1 = self.tags.get(TAG1_ID)

        if self.state == STATE_WAIT:
            self.time_left = 0.0
            if self.in_zone(t0, self.p1_start) and self.in_zone(t1, self.p2_start):
                self.set_state(STATE_READY)
        elif self.state == STATE_READY:
            self.time_left = max(0.0, self.READY_S - (now_ms() - self.state_entered_ms) / 1000.0)
            if not self.in_zone(t0, self.p1_start) or not self.in_zone(t1, self.p2_start):
                self.set_state(STATE_WAIT)
            elif self.time_left <= 0:
                self.mode.on_round_start()
                self.set_state(STATE_PLAYING)
        elif self.state == STATE_PLAYING:
            self.time_left = max(0.0, self.GAME_TIME_S - (now_ms() - self.state_entered_ms) / 1000.0)
            dt = (now_ms() - self.last_tick_ms) / 1000.0
            self.last_tick_ms = now_ms()
            dt = max(0.0, min(dt, 0.25))
            self.mode.update(dt)
            self.update_oob(dt)
            if self.time_left <= 0:
                self.set_state(STATE_GAMEOVER)
        elif self.state == STATE_GAMEOVER:
            if now_ms() - self.state_entered_ms > self.GAMEOVER_S * 1000:
                self.set_state(STATE_WAIT)

    def update_oob(self, dt):
        b = self.field_bounds()
        for i in range(2):
            tag = self.tags.get(TAG0_ID if i == 0 else TAG1_ID)
            if tag is None or tag.pos is None:
                self.oob_countdown[i] = float(self.OOB_TIMEOUT_S)
                self.oob_active[i] = False
                continue
            x, y = tag.pos
            outside = (x < b[0] - self.OOB_MARGIN_MM or x > b[1] + self.OOB_MARGIN_MM
                       or y < b[2] - self.OOB_MARGIN_MM or y > b[3] + self.OOB_MARGIN_MM)
            if outside:
                self.oob_countdown[i] -= dt
                self.oob_active[i] = True
                if self.oob_countdown[i] <= 0:
                    self.oob_countdown[i] = 0
                    self.mode.on_player_out(i)
                    return
            else:
                self.oob_countdown[i] = float(self.OOB_TIMEOUT_S)
                self.oob_active[i] = False

    # ============================ OSC ============================
    def send_mode_osc(self):
        self.osc.mode(self.mode.id, self.mode.display_name)

    def send_start_zones(self):
        self.osc.start_zones(self.p1_start, self.p2_start)

    def send_anchors(self):
        self.osc.anchors(self.tracker.ax, self.tracker.ay)

    def send_game_osc(self):
        if now_ms() - self.last_game_osc_ms < self.OSC_GAME_INTERVAL_MS:
            return
        self.last_game_osc_ms = now_ms()

        sc = self.mode.scores()
        tl = int(self.time_left + 0.999) if self.state == STATE_READY else int(self.time_left)
        self.osc.stats(self.state, tl, sc[0], sc[1], self.round_winner)
        for i in range(2):
            self.osc.oob(i, int(self.oob_countdown[i] + 0.999), self.oob_active[i])

        if self.state == STATE_GAMEOVER:
            self.send_result_osc()
        if self.state == STATE_PLAYING:
            self.osc.hud(self.mode.hud_lines())
        self.send_entities_osc()

    def send_result_osc(self):
        rt = self.mode.result_text()
        title = rt[0] if rt else "GAME OVER"
        subtitle = rt[1] if rt and len(rt) > 1 else self.default_subtitle()
        self.osc.result(title, subtitle)

    def default_subtitle(self):
        if self.round_winner == 1:
            return "SPIELER 1 GEWINNT!"
        if self.round_winner == 2:
            return "SPIELER 2 GEWINNT!"
        return "UNENTSCHIEDEN!"

    def send_entities_osc(self):
        for eid in self.entities.removed_ids:
            self.osc.ent_remove(eid)
        self.entities.removed_ids.clear()
        for e in self.entities.values():
            if not e.visible:
                continue
            if e.needs_upsert:
                self.osc.ent_upsert(e)
                e.needs_upsert = False
            self.osc.ent_pos(e)
