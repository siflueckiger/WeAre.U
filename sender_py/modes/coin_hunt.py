"""Mode 1: Coin Hunt.

Competitive coin collection. Bouncing hazards spawn progressively as coins are
collected and are neutral (dangerous to BOTH players). Powerups change the rules.
Direct port of `sender/Mode_CoinHunt.pde`.
"""

import math
import random

from shared.protocol import C_P1, C_P2, TAG0_ID, TAG1_ID, STATE_PLAYING
from sender_py.modes.base import GameMode

C_COIN = (255, 220, 40)
C_ENEMY = (255, 60, 60)

PU_MAGNET, PU_INVIS, PU_FREEZE, PU_DOUBLE, PU_LIFE = range(5)


class Enemy:
    def __init__(self, ent, vx, vy):
        self.ent = ent
        self.vx = vx
        self.vy = vy


class CoinHunt(GameMode):
    id = "coinHunt"
    display_name = "Coin Hunt"

    # coins
    COLLECT_RADIUS_MM = 300
    COIN_MARGIN_MM = 500
    COIN_MIN_DIST_PLAYER_MM = 800
    COIN_FAIR_DIFF_MM = 1200
    COIN_VISUAL_MM = 120

    # hazards
    ENEMY_SPEED_MM_S = 600
    ENEMY_CATCH_RADIUS_MM = 350
    ENEMY_VISUAL_MM = 200
    ENEMY_SPAWN_SAFE_MM = 1200
    ENEMY_SPAWN_COINS_1 = 3
    ENEMY_SPAWN_COINS_2 = 6

    # lives
    START_LIVES = 3
    MAX_LIVES = 5
    INVULN_S = 2.0

    # powerups
    POWERUP_INTERVAL_S = 8
    POWERUP_LIFETIME_S = 15
    POWERUP_COLLECT_RADIUS_MM = 400
    POWERUP_VISUAL_MM = 200
    MAGNET_PULL_MM_S = 700
    MAGNET_S = 5
    INVIS_S = 5
    FREEZE_S = 4

    def __init__(self, engine):
        super().__init__(engine)
        self.score_p1 = 0
        self.score_p2 = 0
        self.coin = None
        self.lives = [self.START_LIVES] * 2
        self.invuln = [0.0] * 2
        self.magnet = [0.0] * 2
        self.invis = [0.0] * 2
        self.freeze_all = 0.0
        self.next_coin_double = False
        self.enemies = []
        self.powerup = None
        self.powerup_type = PU_MAGNET
        self.powerup_timer = float(self.POWERUP_INTERVAL_S)
        self.powerup_life = 0.0

    # ============================ lifecycle ============================
    def on_round_end(self):
        self.coin = None
        self.powerup = None
        self.enemies = []
        self.freeze_all = 0.0
        self.next_coin_double = False
        for i in range(2):
            self.invuln[i] = 0.0
            self.magnet[i] = 0.0
            self.invis[i] = 0.0

    def on_round_start(self):
        self.score_p1 = 0
        self.score_p2 = 0
        self.engine.entities.clear()
        self.coin = None
        self.powerup = None
        self.enemies = []
        for i in range(2):
            self.lives[i] = self.START_LIVES
            self.invuln[i] = 0.0
            self.magnet[i] = 0.0
            self.invis[i] = 0.0
        self.freeze_all = 0.0
        self.next_coin_double = False
        self.powerup_timer = float(self.POWERUP_INTERVAL_S)
        self.spawn_coin()

    # Out of bounds costs one life (not the round). The player gets a fresh
    # warning window; only at 0 lives does the round end.
    def on_player_out(self, player):
        self.lives[player] -= 1
        self.invuln[player] = self.INVULN_S
        print("P%d out of bounds! -1 life, remaining: %d" % (player + 1, self.lives[player]))
        self.engine.osc.hit(player, self.INVULN_S)
        self.engine.oob_countdown[player] = float(self.engine.OOB_TIMEOUT_S)
        self.engine.oob_active[player] = False
        if self.lives[player] <= 0:
            self.engine.round_winner = 2 if player == 0 else 1
            print("P%d ran out of lives (out of bounds) -> round over" % (player + 1))
            self.engine.request_end()

    def update(self, dt):
        self.tick_timers(dt)
        self.update_magnet(dt)
        self.update_enemies(dt)
        self.update_powerup(dt)
        if self.coin is not None:
            self.collect_coin_check()

    # ============================ data ============================
    def scores(self):
        return (self.score_p1, self.score_p2)

    def hud_lines(self):
        lines = []
        if self.freeze_all > 0:
            lines.append("ENEMIES FROZEN %ds" % int(self.freeze_all))
        if self.next_coin_double:
            lines.append("NEXT COIN x2")
        return lines

    def player_lives(self, player):
        return self.lives[player]

    def player_effects(self, player):
        fx = []
        if self.magnet[player] > 0:
            fx.append("MAGNET %ds" % int(self.magnet[player]))
        if self.invis[player] > 0:
            fx.append("INVIS %ds" % int(self.invis[player]))
        return fx

    # ============================ timers ============================
    def tick_timers(self, dt):
        self.freeze_all = max(0.0, self.freeze_all - dt)
        for i in range(2):
            self.invuln[i] = max(0.0, self.invuln[i] - dt)
            self.magnet[i] = max(0.0, self.magnet[i] - dt)
            self.invis[i] = max(0.0, self.invis[i] - dt)

    # ============================ coins ============================
    def update_magnet(self, dt):
        if self.coin is None:
            return
        best = -1
        best_d = float("inf")
        for p in range(2):
            if self.magnet[p] <= 0:
                continue
            t = self.engine.tags.get(TAG0_ID if p == 0 else TAG1_ID)
            if t is None or t.pos is None:
                continue
            d = _dist(t.pos, (self.coin.x, self.coin.y))
            if d < best_d:
                best_d = d
                best = p
        if best < 0:
            return
        t = self.engine.tags.get(TAG0_ID if best == 0 else TAG1_ID)
        dx = t.pos[0] - self.coin.x
        dy = t.pos[1] - self.coin.y
        d = math.hypot(dx, dy)
        if d < 1:
            return
        step = min(self.MAGNET_PULL_MM_S * dt, d)
        self.coin.x += dx / d * step
        self.coin.y += dy / d * step

    def collect_coin_check(self):
        for p in range(2):
            t = self.engine.tags.get(TAG0_ID if p == 0 else TAG1_ID)
            if t is None or t.pos is None:
                continue
            if _dist(t.pos, (self.coin.x, self.coin.y)) < self.COLLECT_RADIUS_MM:
                self.collect_coin(p)
                break

    def collect_coin(self, player):
        gain = 2 if self.next_coin_double else 1
        self.next_coin_double = False
        if player == 0:
            self.score_p1 += gain
        else:
            self.score_p2 += gain
        print("P%d collected coin (+%d) -> P1:%d P2:%d"
              % (player + 1, gain, self.score_p1, self.score_p2))
        if self.magnet[player] > 0:
            self.magnet[player] = 0
            print("P%d magnet consumed on coin capture" % (player + 1))
        if self.coin is not None:
            self.engine.entities.remove(self.coin.id)
        self.coin = None
        self.maybe_spawn_enemies()
        self.spawn_coin()

    def spawn_coin(self):
        b = self.engine.field_bounds()
        t0 = self.engine.tags.get(TAG0_ID)
        t1 = self.engine.tags.get(TAG1_ID)
        for _ in range(100):
            x = random.uniform(b[0] + self.COIN_MARGIN_MM, b[1] - self.COIN_MARGIN_MM)
            y = random.uniform(b[2] + self.COIN_MARGIN_MM, b[3] - self.COIN_MARGIN_MM)
            d0 = _dist((x, y), t0.pos) if t0 and t0.pos else float("inf")
            d1 = _dist((x, y), t1.pos) if t1 and t1.pos else float("inf")
            if min(d0, d1) < self.COIN_MIN_DIST_PLAYER_MM:
                continue
            if (t0 and t1 and t0.pos and t1.pos
                    and abs(d0 - d1) > self.COIN_FAIR_DIFF_MM):
                continue
            self.coin = self.engine.entities.spawn("coin", x, y, self.COIN_VISUAL_MM, C_COIN)
            return
        self.coin = self.engine.entities.spawn(
            "coin",
            random.uniform(b[0] + self.COIN_MARGIN_MM, b[1] - self.COIN_MARGIN_MM),
            random.uniform(b[2] + self.COIN_MARGIN_MM, b[3] - self.COIN_MARGIN_MM),
            self.COIN_VISUAL_MM, C_COIN)

    # ============================ hazards ============================
    def maybe_spawn_enemies(self):
        total = self.score_p1 + self.score_p2
        if len(self.enemies) == 0 and total >= self.ENEMY_SPAWN_COINS_1:
            self.spawn_enemy()
        elif len(self.enemies) == 1 and total >= self.ENEMY_SPAWN_COINS_2:
            self.spawn_enemy()

    def spawn_enemy(self):
        pos = self.random_far_point(self.ENEMY_SPAWN_SAFE_MM)
        ang = math.radians(random.uniform(25, 65)) + random.randint(0, 3) * math.pi / 2
        vx = math.cos(ang) * self.ENEMY_SPEED_MM_S
        vy = math.sin(ang) * self.ENEMY_SPEED_MM_S
        e = self.engine.entities.spawn("enemy", pos[0], pos[1], self.ENEMY_VISUAL_MM, C_ENEMY)
        self.enemies.append(Enemy(e, vx, vy))
        print("Hazard spawned (%d)" % len(self.enemies))

    def update_enemies(self, dt):
        b = self.engine.field_bounds()
        m = self.ENEMY_VISUAL_MM
        for en in self.enemies:
            if self.freeze_all <= 0:
                en.ent.x += en.vx * dt
                en.ent.y += en.vy * dt
                if en.ent.x < b[0] + m:
                    en.ent.x = b[0] + m
                    en.vx = abs(en.vx)
                if en.ent.x > b[1] - m:
                    en.ent.x = b[1] - m
                    en.vx = -abs(en.vx)
                if en.ent.y < b[2] + m:
                    en.ent.y = b[2] + m
                    en.vy = abs(en.vy)
                if en.ent.y > b[3] - m:
                    en.ent.y = b[3] - m
                    en.vy = -abs(en.vy)
            for p in range(2):
                if self.invis[p] > 0 or self.invuln[p] > 0:
                    continue
                td = self.engine.tags.get(TAG0_ID if p == 0 else TAG1_ID)
                if td is None or td.pos is None:
                    continue
                if _dist((en.ent.x, en.ent.y), td.pos) < self.ENEMY_CATCH_RADIUS_MM:
                    self.catch_player(p, en)

    def catch_player(self, player, en):
        self.lives[player] -= 1
        self.invuln[player] = self.INVULN_S
        print("P%d hit by hazard! lives=%d" % (player + 1, self.lives[player]))
        self.engine.osc.hit(player, self.INVULN_S)
        en.vx = -en.vx
        en.vy = -en.vy
        if self.lives[player] <= 0:
            self.engine.round_winner = 2 if player == 0 else 1
            self.engine.request_end()

    # ============================ powerups ============================
    def update_powerup(self, dt):
        if self.powerup is not None:
            self.powerup_life -= dt
            if self.powerup_life <= 0:
                self.engine.entities.remove(self.powerup.id)
                self.powerup = None
                self.powerup_timer = float(self.POWERUP_INTERVAL_S)
                return
            for p in range(2):
                t = self.engine.tags.get(TAG0_ID if p == 0 else TAG1_ID)
                if t is None or t.pos is None:
                    continue
                if _dist(t.pos, (self.powerup.x, self.powerup.y)) < self.POWERUP_COLLECT_RADIUS_MM:
                    self.apply_powerup(self.powerup_type, p)
                    self.engine.entities.remove(self.powerup.id)
                    self.powerup = None
                    self.powerup_timer = float(self.POWERUP_INTERVAL_S)
                    return
        else:
            self.powerup_timer -= dt
            if self.powerup_timer <= 0:
                self.spawn_powerup()

    def spawn_powerup(self):
        self.powerup_type = random.randint(0, 4)
        pos = self.random_far_point(self.COIN_MIN_DIST_PLAYER_MM)
        self.powerup = self.engine.entities.spawn(
            "powerup", pos[0], pos[1], self.POWERUP_VISUAL_MM,
            self.powerup_color(self.powerup_type))
        self.powerup.label = self.powerup_label(self.powerup_type)
        self.powerup_life = float(self.POWERUP_LIFETIME_S)
        print("Powerup spawned:", self.powerup_name(self.powerup_type))

    def powerup_color(self, t):
        return {
            PU_MAGNET: (120, 220, 255),
            PU_INVIS: (180, 140, 255),
            PU_FREEZE: (120, 255, 200),
            PU_DOUBLE: (255, 200, 120),
        }.get(t, (255, 120, 200))

    def powerup_label(self, t):
        return {PU_MAGNET: "MAG", PU_INVIS: "INV", PU_FREEZE: "FRE",
                PU_DOUBLE: "DOU"}.get(t, "LIF")

    def powerup_name(self, t):
        return {PU_MAGNET: "MAGNET", PU_INVIS: "INVIS", PU_FREEZE: "FREEZE",
                PU_DOUBLE: "DOUBLE"}.get(t, "LIFE")

    def apply_powerup(self, t, player):
        if t == PU_MAGNET:
            self.magnet[player] = self.MAGNET_S
        elif t == PU_INVIS:
            self.invis[player] = self.INVIS_S
        elif t == PU_FREEZE:
            self.freeze_all = self.FREEZE_S
        elif t == PU_DOUBLE:
            self.next_coin_double = True
        elif t == PU_LIFE:
            self.lives[player] = min(self.lives[player] + 1, self.MAX_LIVES)
        print("P%d got %s" % (player + 1, self.powerup_name(t)))

    # ============================ helpers ============================
    def random_far_point(self, min_dist):
        b = self.engine.field_bounds()
        t0 = self.engine.tags.get(TAG0_ID)
        t1 = self.engine.tags.get(TAG1_ID)
        for _ in range(100):
            x = random.uniform(b[0] + self.COIN_MARGIN_MM, b[1] - self.COIN_MARGIN_MM)
            y = random.uniform(b[2] + self.COIN_MARGIN_MM, b[3] - self.COIN_MARGIN_MM)
            d0 = _dist((x, y), t0.pos) if t0 and t0.pos else float("inf")
            d1 = _dist((x, y), t1.pos) if t1 and t1.pos else float("inf")
            if min(d0, d1) < min_dist:
                continue
            return (x, y)
        return (random.uniform(b[0] + self.COIN_MARGIN_MM, b[1] - self.COIN_MARGIN_MM),
                random.uniform(b[2] + self.COIN_MARGIN_MM, b[3] - self.COIN_MARGIN_MM))

    # ============================ rendering ============================
    def draw_world(self, surface, gui):
        if self.engine.state != STATE_PLAYING:
            return
        gui.draw_hitbox_ring(TAG0_ID, C_P1, self.COLLECT_RADIUS_MM)
        gui.draw_hitbox_ring(TAG1_ID, C_P2, self.COLLECT_RADIUS_MM)
        gui.draw_invuln_blink(TAG0_ID, self.invuln[0])
        gui.draw_invuln_blink(TAG1_ID, self.invuln[1])


def _dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])
