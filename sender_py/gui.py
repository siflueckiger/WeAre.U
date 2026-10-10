"""Pygame renderer for the sender operator view (game mode + shared field).

Layout: unified header (P1 | center | P2), a completely free playing field,
floating warnings only when active, and a compact status footer.
"""

import math
import time

import pygame

from shared.protocol import (
    STATE_WAIT, STATE_READY, STATE_PLAYING, STATE_GAMEOVER,
    START_ZONE_RADIUS_MM, C_P1, C_P2, TAG0_ID, TAG1_ID, TRAIL_MAX,
)

W, H = 1000, 800
HEADER_H = 96
FOOTER_H = 30

MODE_GAME = 0
MODE_SETUP = 1

F_BG = (12, 12, 18)
F_PANEL = (12, 12, 18)
GRID = (45, 45, 45)
ANCHOR = (90, 200, 90)

STATE_COLORS = {
    STATE_WAIT: (160, 160, 160),
    STATE_READY: (255, 230, 120),
    STATE_PLAYING: (140, 230, 140),
    STATE_GAMEOVER: (255, 170, 60),
}


class Gui:
    def __init__(self):
        pygame.font.init()
        self.font = pygame.font.SysFont(None, 18)
        self.font_small = pygame.font.SysFont(None, 16)
        self.font_big = pygame.font.SysFont(None, 46)
        self.font_mid = pygame.font.SysFont(None, 26)
        self.s = 1.0
        self.ox = 0.0
        self.oy = 0.0

    # ============================ transform ============================
    def compute_transform(self, app):
        ax, ay = app.tracker.ax, app.tracker.ay
        minx, maxx = min(ax), max(ax)
        miny, maxy = min(ay), max(ay)
        w = maxx - minx
        h = maxy - miny
        if w < 1:
            w = 1000
        if h < 1:
            h = 1000
        if app.app_mode == MODE_GAME:
            top, bottom, side = HEADER_H + 16, H - FOOTER_H - 16, 24
        else:
            top, bottom, side = 80, H - 80, 80
        avail_w = W - 2 * side
        avail_h = bottom - top
        self.s = min(avail_w / w, avail_h / h)
        field_top = top + (avail_h - h * self.s) / 2
        self.ox = side + (avail_w - w * self.s) / 2 - minx * self.s
        self.oy = field_top + maxy * self.s

    def scr(self, x, y):
        return (self.ox + x * self.s, self.oy - y * self.s)

    # ============================ primitives ============================
    def panel(self, surface, x, y, w, h, title, title_col):
        pygame.draw.rect(surface, F_PANEL, (x, y, w, h))
        pygame.draw.rect(surface, title_col, (x, y, w, 18))
        t = self.font_small.render(title, True, (0, 0, 0))
        surface.blit(t, (x + 6, y + 2))

    # ============================ main draw ============================
    def draw(self, surface, app):
        self.surface = surface
        self.app = app
        surface.fill((22, 22, 22))
        self.compute_transform(app)
        self.draw_grid(surface, app)
        self.draw_anchors(surface, app)
        if app.app_mode == MODE_GAME:
            self.draw_start_zones(surface, app)
            app.engine.mode.draw_world(surface, self)
            self.draw_entities(surface, app)
        self.draw_tag(surface, app, TAG0_ID, C_P1, "P1")
        self.draw_tag(surface, app, TAG1_ID, C_P2, "P2")
        if app.app_mode == MODE_GAME:
            self.draw_oob_markers(surface, app)
            self.draw_header(surface, app)
            self.draw_warnings(surface, app)
            self.draw_footer(surface, app)
            if app.hud_debug:
                self.draw_debug_cards(surface, app)
            if app.hud_keys:
                self.draw_key_help(surface)
        else:
            app.setup.draw(surface, self)

    # ============================ field ============================
    def draw_grid(self, surface, app):
        ax, ay = app.tracker.ax, app.tracker.ay
        minx, maxx = min(ax), max(ax)
        miny, maxy = min(ay), max(ay)
        step = 500
        gx = math.floor(minx / step) * step
        while gx <= maxx:
            a = self.scr(gx, miny)
            b = self.scr(gx, maxy)
            pygame.draw.line(surface, GRID, a, b, 1)
            gx += step
        gy = math.floor(miny / step) * step
        while gy <= maxy:
            a = self.scr(minx, gy)
            b = self.scr(maxx, gy)
            pygame.draw.line(surface, GRID, a, b, 1)
            gy += step

    def draw_anchors(self, surface, app):
        for i in range(4):
            p = self.scr(app.tracker.ax[i], app.tracker.ay[i])
            pygame.draw.rect(surface, ANCHOR, (p[0] - 8, p[1] - 8, 16, 16))
            t = self.font_small.render("A%d" % i, True, (255, 255, 255))
            surface.blit(t, t.get_rect(midbottom=(p[0], p[1] - 10)))

    def draw_start_zones(self, surface, app):
        from shared.protocol import STATE_WAIT, STATE_READY
        if app.engine.state not in (STATE_WAIT, STATE_READY):
            return
        for zone, label, c in ((app.engine.p1_start, "P1", C_P1),
                               (app.engine.p2_start, "P2", C_P2)):
            q = self.scr(zone[0], zone[1])
            r = max(1, int(START_ZONE_RADIUS_MM * self.s))
            pygame.draw.circle(surface, c, (int(q[0]), int(q[1])), r, 2)
            s = self.font_small.render(label, True, c)
            surface.blit(s, s.get_rect(center=(int(q[0]), int(q[1]))))

    def draw_tag(self, surface, app, tid, color, label):
        t = app.tracker.tags.get(tid)
        if t is None:
            return
        stale = app.tracker.last_frame_ms and (now_ms() - app.tracker.last_frame_ms > 2000)
        if len(t.trail) >= 2:
            pts = [self.scr(x, y) for (x, y) in t.trail]
            n = len(pts)
            for i in range(1, n):
                f = 15 + (i - 1) * (200 - 15) / max(1, n - 2)
                a = f if not stale else f * 90 / 255
                col = tuple(int(c * a / 220) for c in color)
                pygame.draw.line(surface, col, pts[i - 1], pts[i], 2)
        if t.pos is not None:
            p = self.scr(t.pos[0], t.pos[1])
            col = color if not stale else tuple(int(c * 90 / 255) for c in color)
            pygame.draw.circle(surface, col, (int(p[0]), int(p[1])), 7)
            pygame.draw.circle(surface, (255, 255, 255), (int(p[0]), int(p[1])), 7, 2)
            s = self.font_small.render(label, True, (255, 255, 255))
            surface.blit(s, (p[0] + 10, p[1] - 8))

    def draw_entities(self, surface, app):
        for e in app.entities.values():
            if not e.visible:
                continue
            x, y = self.scr(e.x, e.y)
            r = max(2, int(e.radius * self.s))
            typ = e.type
            if typ == "enemy" or typ == "obstacle":
                pygame.draw.rect(surface, e.color, (x - r, y - r, 2 * r, 2 * r))
            elif typ == "powerup" or typ == "zone":
                pygame.draw.circle(surface, e.color, (int(x), int(y)), r, 3)
            else:
                pygame.draw.circle(surface, e.color, (int(x), int(y)), r)
                pygame.draw.circle(surface, (255, 255, 255), (int(x), int(y)), r, 2)
            if e.label:
                s = self.font_small.render(e.label, True, (255, 255, 255))
                surface.blit(s, s.get_rect(center=(int(x), int(y))))

    def draw_hitbox_ring(self, tid, color, radius_mm):
        t = self.app.tracker.tags.get(tid)
        if t is None or t.pos is None:
            return
        q = self.scr(t.pos[0], t.pos[1])
        r = max(1, int(radius_mm * self.s))
        pygame.draw.circle(self.surface, color, (int(q[0]), int(q[1])), r, 1)

    def draw_oob_markers(self, surface, app):
        for i, tid in ((0, TAG0_ID), (1, TAG1_ID)):
            if not app.engine.oob_active[i]:
                continue
            t = app.tracker.tags.get(tid)
            if t is None or t.pos is None:
                continue
            p = self.scr(t.pos[0], t.pos[1])
            r = max(20, int(40 * self.s))
            pygame.draw.circle(surface, (255, 60, 60), (int(p[0]), int(p[1])), r, 4)
            s = self.font_small.render("GO BACK! %ds" % int(app.engine.oob_countdown[i] + 0.999),
                                       True, (255, 80, 80))
            surface.blit(s, s.get_rect(midbottom=(p[0], p[1] - r - 4)))

    # ============================ header ============================
    def draw_header(self, surface, app):
        eng = app.engine
        pygame.draw.rect(surface, F_PANEL, (0, 0, W, HEADER_H))
        pygame.draw.line(surface, (60, 60, 60), (0, HEADER_H), (W, HEADER_H))
        sc = STATE_COLORS.get(eng.state, (255, 255, 255))

        mode_t = self.font.render(eng.mode.display_name.upper(), True, (200, 200, 200))
        surface.blit(mode_t, mode_t.get_rect(midtop=(W // 2, 6)))
        big = self.font_big.render(self._center_value(app), True, sc)
        surface.blit(big, big.get_rect(midtop=(W // 2, 22)))
        st = self.font.render(eng.state_name(), True, sc)
        surface.blit(st, st.get_rect(midtop=(W // 2, HEADER_H - 32)))
        lines = eng.mode.hud_lines()
        if lines:
            lt = self.font_small.render("    ".join(lines), True, (235, 210, 150))
            surface.blit(lt, lt.get_rect(midtop=(W // 2, HEADER_H - 15)))

        self.draw_header_player(surface, app, 0, 16)
        self.draw_header_player(surface, app, 1, W - 16)

    def _center_value(self, app):
        eng = app.engine
        if eng.state == STATE_WAIT:
            both = (eng.in_zone(eng.tags.get(TAG0_ID), eng.p1_start)
                    and eng.in_zone(eng.tags.get(TAG1_ID), eng.p2_start))
            return "STARTING" if both else "WAITING"
        if eng.state == STATE_READY:
            return str(max(1, int(eng.time_left + 0.999)))
        if eng.state == STATE_PLAYING:
            return "%ds" % int(eng.time_left)
        return "GAME OVER"

    def draw_header_player(self, surface, app, p, x):
        eng = app.engine
        c = C_P1 if p == 0 else C_P2
        left = (p == 0)
        sc = eng.mode.scores()

        lbl = self.font.render("P%d" % (p + 1), True, c)
        surface.blit(lbl, lbl.get_rect(topleft=(x, 8)) if left else lbl.get_rect(topright=(x, 8)))
        num = self.font_big.render(str(sc[p]), True, c)
        surface.blit(num, num.get_rect(topleft=(x, 20)) if left else num.get_rect(topright=(x, 20)))

        lives = eng.mode.player_lives(p)
        pip_y = 66
        if lives >= 0:
            pip_r, gap = 5, 5
            n = max(1, lives)
            total = n * 2 * pip_r + (n - 1) * gap
            sx = x if left else x - total
            for i in range(n):
                cx = int(sx + pip_r + i * (2 * pip_r + gap))
                if i < lives:
                    pygame.draw.circle(surface, c, (cx, pip_y), pip_r)
                else:
                    pygame.draw.circle(surface, tuple(int(v * 0.3) for v in c), (cx, pip_y), pip_r, 1)

        if eng.state in (STATE_WAIT, STATE_READY):
            inz = eng.in_zone(eng.tags.get(TAG0_ID if p == 0 else TAG1_ID),
                              eng.p1_start if p == 0 else eng.p2_start)
            col = (140, 230, 140) if inz else (255, 150, 90)
            t = self.font_small.render("IN ZONE" if inz else "GO TO ZONE", True, col)
        else:
            fx = eng.mode.player_effects(p)
            t = self.font_small.render("  ".join(fx), True, (235, 210, 150)) if fx else None
        if t is not None:
            surface.blit(t, t.get_rect(topleft=(x, 78)) if left else t.get_rect(topright=(x, 78)))

    # ============================ warnings / footer ============================
    def draw_warnings(self, surface, app):
        warns = []
        if not app.virtual.on and app.serial.port is None:
            warns.append(("SERIAL NOT CONNECTED -- searching port", (255, 50, 50)))
        elif not app.virtual.on and app.tracker.last_frame_ms and now_ms() - app.tracker.last_frame_ms > 2000:
            warns.append(("NO TAG DATA FOR >2s", (255, 50, 50)))
        for i in (app.tracker.seen_ids):
            if i not in (TAG0_ID, TAG1_ID):
                warns.append(("UNKNOWN TagID 0x%04X -- check TAG0_ID/TAG1_ID" % i, (255, 160, 40)))
                break
        if app.engine.oob_active[0]:
            warns.append(("P1: GO BACK NOW OR LOSE A LIFE (%ds)" % int(app.engine.oob_countdown[0] + 0.999), (255, 50, 50)))
        if app.engine.oob_active[1]:
            warns.append(("P2: GO BACK NOW OR LOSE A LIFE (%ds)" % int(app.engine.oob_countdown[1] + 0.999), (255, 50, 50)))

        y = HEADER_H + 12
        for text, col in warns:
            t = self.font.render(text, True, (255, 255, 255))
            pad = 8
            x = W // 2 - t.get_width() // 2 - pad
            pygame.draw.rect(surface, col, (x, y, t.get_width() + 2 * pad, 22))
            surface.blit(t, (x + pad, y + 2))
            y += 26

    def draw_footer(self, surface, app):
        fy = H - FOOTER_H
        pygame.draw.rect(surface, F_PANEL, (0, fy, W, FOOTER_H))
        pygame.draw.line(surface, (60, 60, 60), (0, fy), (W, fy))
        cy = fy + FOOTER_H // 2

        if app.virtual.on:
            dot, serial = (120, 180, 255), "VIRTUAL SIM"
        elif app.serial.port is None:
            dot, serial = (255, 80, 80), "SERIAL --"
        else:
            dot, serial = (120, 230, 120), "SERIAL OK"
        pygame.draw.circle(surface, dot, (16, cy), 5)
        t = self.font_small.render(serial, True, dot)
        surface.blit(t, (26, cy - 8))

        osc_txt = "OSC %s:%d   frames %d   scale %.3f" % (
            app.osc.ip, app.osc.port, app.tracker.frames, self.s)
        surface.blit(self.font_small.render(osc_txt, True, (170, 170, 170)), (150, cy - 8))

        filt = "Clamp %s  EMA %s a=%.2f" % (_onoff(app.use_speed_clamp), _onoff(app.use_ema), app.smooth_alpha)
        surface.blit(self.font_small.render(filt, True, (170, 170, 170)), (430, cy - 8))

        hint = "V virtual   R reset   SPACE start   TAB setup   M mode   D debug   H help"
        ht = self.font_small.render(hint, True, (150, 150, 150))
        surface.blit(ht, ht.get_rect(topright=(W - 14, cy - 8)))

    def draw_debug_cards(self, surface, app):
        w, h, y = 300, 92, HEADER_H + 10
        self.draw_debug_card(surface, app, TAG0_ID, "P1", C_P1, 10, y, w, h)
        self.draw_debug_card(surface, app, TAG1_ID, "P2", C_P2, W - 10 - w, y, w, h)

    def draw_debug_card(self, surface, app, tid, label, c, x, y, w, h):
        self.panel(surface, x, y, w, h, label + "  (debug)", c)
        t = app.tracker.tags.get(tid)
        if t is None:
            surface.blit(self.font_small.render("no frames yet", True, (255, 255, 255)), (x + 8, y + 24))
            return
        if t.pos is not None:
            txt = "pos %.0f, %.0f mm   %.2f m/s" % (t.pos[0], t.pos[1], t.speed_ms / 1000.0)
        else:
            txt = "no fix (<3 anchors)"
        surface.blit(self.font_small.render(txt, True, (255, 255, 255)), (x + 8, y + 24))
        mask = "".join("1" if (t.mask >> i) & 1 else "0" for i in range(7, -1, -1))
        line2 = "tagid 0x%04X  mask %s  trail %d/%d" % (t.id, mask, len(t.trail), TRAIL_MAX)
        surface.blit(self.font_small.render(line2, True, (200, 200, 200)), (x + 8, y + 40))
        anchors = "  ".join(_anchor_str(t, i) for i in range(4))
        surface.blit(self.font_small.render(anchors, True, (200, 200, 200)), (x + 8, y + 56))

    def draw_key_help(self, surface):
        lines = [
            "TAB ........ Setup mode",
            "M .......... next mode / reset",
            "V .......... virtual players (debug)",
            "SPACE ...... start / skip round",
            "R .......... reset / abort round",
            "1 / 2 ...... filters on/off",
            "4 .......... EMA alpha",
            "D .......... tag debug details",
            "H .......... hide this help",
            "WASD / arrows = move virtual P1/P2",
        ]
        w, h = 300, 24 + len(lines) * 18 + 10
        x, y = W // 2 - w // 2, H // 2 - h // 2
        self.panel(surface, x, y, w, h, "KEYS", (180, 200, 220))
        for i, ln in enumerate(lines):
            surface.blit(self.font.render(ln, True, (255, 255, 255)), (x + 10, y + 26 + i * 18))

    def draw_invuln_blink(self, tid, seconds):
        if seconds <= 0:
            return
        if (now_ms() // 150) % 2 != 0:
            return
        t = self.app.tracker.tags.get(tid)
        if t is None or t.pos is None:
            return
        p = self.scr(t.pos[0], t.pos[1])
        pygame.draw.circle(self.surface, (255, 255, 255), (int(p[0]), int(p[1])), 17, 3)


def _onoff(v):
    return "ON" if v else "OFF"


def _anchor_str(t, i):
    v = "%.0f" % t.kalman[i] if ((t.mask & (1 << i)) and t.kalman[i] > 0) else "--"
    return "A%d=%s" % (i, v)


def now_ms():
    return int(time.monotonic() * 1000)
