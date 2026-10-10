"""Interactive setup / calibration mode (TAB).

Anchor distances -> auto-layout, start zones via live tag capture or mouse drag,
persistence in config.json. Port of `sender/Setup.pde`.
"""

import json
import math
import os

import pygame

D_PAIRS = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
D_NAMES = ["A0-A1", "A0-A2", "A0-A3", "A1-A2", "A1-A3", "A2-A3"]
LAYOUT_WARN_MM = 200
CONFIG_FILE = os.path.join(os.path.dirname(__file__), "config.json")


class SetupMode:
    def __init__(self, app):
        self.app = app
        self.anchor_d = [0.0] * 6
        self.anchor_d_idx = 0
        self.drag_anchor = -1
        self.drag_zone = -1
        self.status = ""
        self.dist_input = ""
        self.compute_d()

    # ============================ geometry ============================
    def compute_d(self):
        ax, ay = self.app.tracker.ax, self.app.tracker.ay
        for i, (a, b) in enumerate(D_PAIRS):
            self.anchor_d[i] = math.hypot(ax[a] - ax[b], ay[a] - ay[b])

    def apply_layout(self):
        self.dist_input = ""
        d01, d02, d03, d12, d13, d23 = self.anchor_d
        if d01 < 1:
            self.status = "A0-A1 zu klein"
            return
        ax = [0.0, d01, 0.0, 0.0]
        ay = [0.0, 0.0, 0.0, 0.0]
        x2 = (d02 * d02 - d12 * d12 + d01 * d01) / (2 * d01)
        y2sq = d02 * d02 - x2 * x2
        x3 = (d03 * d03 - d13 * d13 + d01 * d01) / (2 * d01)
        y3sq = d03 * d03 - x3 * x3
        self.status = "Layout berechnet"
        if y2sq < 0:
            self.status = "WARNUNG: A2 inkonsistent - geklemmt"
            y2sq = 0
        if y3sq < 0:
            self.status = "WARNUNG: A3 inkonsistent - geklemmt"
            y3sq = 0
        ax[2], ay[2] = x2, math.sqrt(y2sq)
        ax[3], ay[3] = x3, math.sqrt(y3sq)
        self.app.tracker.set_anchors(ax, ay)
        d23c = math.hypot(ax[2] - ax[3], ay[2] - ay[3])
        if abs(d23c - d23) > LAYOUT_WARN_MM:
            self.status = "WARNUNG: A2-A3-Check (%.0f vs %.0f)" % (d23c, d23)
        self.compute_d()
        self.app.engine.send_anchors()

    def standard_layout(self):
        self.app.tracker.set_anchors([0, 0, 7000, 7000], [3000, 0, 0, 3000])
        self.dist_input = ""
        self.compute_d()
        self.app.engine.send_anchors()
        self.status = "Standard-Layout 3x7m gesetzt"

    def capture_zone(self, player):
        tid = 0x0000 if player == 0 else 0x0001
        t = self.app.tracker.tags.get(tid)
        if t is None or t.pos is None:
            self.status = "P%d: noch kein Positions-Fix" % (player + 1)
            return
        if player == 0:
            self.app.engine.p1_start[0], self.app.engine.p1_start[1] = t.pos
        else:
            self.app.engine.p2_start[0], self.app.engine.p2_start[1] = t.pos
        self.app.engine.send_start_zones()
        self.status = "P%d-Start -> (%.0f, %.0f)" % (player + 1, t.pos[0], t.pos[1])

    # ============================ config ============================
    def load_config(self):
        if not os.path.exists(CONFIG_FILE):
            print("no config.json -- using built-in defaults")
            self.compute_d()
            return
        try:
            with open(CONFIG_FILE) as f:
                j = json.load(f)
            if len(j.get("AX", [])) == 4 and len(j.get("AY", [])) == 4:
                self.app.tracker.set_anchors(j["AX"], j["AY"])
            d = j.get("D")
            if d and len(d) == 6:
                self.anchor_d = [float(v) for v in d]
            else:
                self.compute_d()
            if len(j.get("P1_START", [])) == 2:
                self.app.engine.p1_start[0], self.app.engine.p1_start[1] = j["P1_START"]
            if len(j.get("P2_START", [])) == 2:
                self.app.engine.p2_start[0], self.app.engine.p2_start[1] = j["P2_START"]
            if j.get("MODE"):
                self.app.engine.set_mode_by_id(j["MODE"])
            print("config loaded:", CONFIG_FILE)
        except Exception as e:
            print("config load failed:", e)
            self.compute_d()

    def save_config(self):
        try:
            j = {
                "AX": self.app.tracker.ax,
                "AY": self.app.tracker.ay,
                "D": self.anchor_d,
                "P1_START": list(self.app.engine.p1_start),
                "P2_START": list(self.app.engine.p2_start),
                "MODE": self.app.engine.mode.id,
            }
            with open(CONFIG_FILE, "w") as f:
                json.dump(j, f, indent=2)
            self.status = "Config gespeichert"
            print("config saved:", CONFIG_FILE)
        except Exception as e:
            self.status = "Speichern fehlgeschlagen"
            print("config save failed:", e)

    # ============================ input ============================
    def key_down(self, key, shift):
        # selection
        if key == pygame.K_UP:
            self.anchor_d_idx = (self.anchor_d_idx - 1) % 6
            self.dist_input = ""
        elif key == pygame.K_DOWN:
            self.anchor_d_idx = (self.anchor_d_idx + 1) % 6
            self.dist_input = ""
        elif key == pygame.K_LEFT:
            self.anchor_d[self.anchor_d_idx] = max(
                0, self.anchor_d[self.anchor_d_idx] - (1 if shift else 10))
        elif key == pygame.K_RIGHT:
            self.anchor_d[self.anchor_d_idx] += (1 if shift else 10)
        elif pygame.K_0 <= key <= pygame.K_9:
            self.dist_input += chr(key)
        elif key == pygame.K_BACKSPACE:
            self.dist_input = self.dist_input[:-1]
        elif key in (pygame.K_RETURN, pygame.K_KP_ENTER):
            if self.dist_input:
                self.anchor_d[self.anchor_d_idx] = float(self.dist_input)
                self.dist_input = ""
        elif key == pygame.K_l:
            self.apply_layout()
        elif key == pygame.K_r:
            self.standard_layout()
        elif key == pygame.K_z:
            self.capture_zone(0)
        elif key == pygame.K_x:
            self.capture_zone(1)
        elif key == pygame.K_v:
            self.save_config()

    def world_from_screen(self, gui, px, py):
        return ((px - gui.ox) / gui.s, (gui.oy - py) / gui.s)

    def mouse_down(self, gui, pos):
        self.drag_anchor = -1
        self.drag_zone = -1
        from shared.protocol import START_ZONE_RADIUS_MM
        for i, z in ((1, self.app.engine.p2_start), (0, self.app.engine.p1_start)):
            q = gui.scr(z[0], z[1])
            if math.hypot(pos[0] - q[0], pos[1] - q[1]) < max(20, START_ZONE_RADIUS_MM * gui.s):
                self.drag_zone = i
                return
        for i in (3, 2, 1, 0):
            q = gui.scr(self.app.tracker.ax[i], self.app.tracker.ay[i])
            if math.hypot(pos[0] - q[0], pos[1] - q[1]) < 20:
                self.drag_anchor = i
                return

    def mouse_drag(self, gui, pos):
        w = self.world_from_screen(gui, pos[0], pos[1])
        if self.drag_anchor >= 0:
            self.app.tracker.ax[self.drag_anchor] = w[0]
            self.app.tracker.ay[self.drag_anchor] = w[1]
        elif self.drag_zone >= 0:
            if self.drag_zone == 0:
                self.app.engine.p1_start[0], self.app.engine.p1_start[1] = w
            else:
                self.app.engine.p2_start[0], self.app.engine.p2_start[1] = w

    def mouse_up(self):
        if self.drag_anchor >= 0:
            self.compute_d()
            self.app.engine.send_anchors()
        elif self.drag_zone >= 0:
            self.app.engine.send_start_zones()
        self.drag_anchor = -1
        self.drag_zone = -1

    # ============================ rendering ============================
    def draw(self, surface, gui):
        self._draw_distances(surface, gui)
        self._draw_anchor_highlight(surface, gui)
        gui.draw_start_zones(surface, self.app)
        self._draw_panel(surface, gui)

    def _draw_distances(self, surface, gui):
        for i in range(6):
            a, b = D_PAIRS[i]
            pa = gui.scr(self.app.tracker.ax[a], self.app.tracker.ay[a])
            pb = gui.scr(self.app.tracker.ax[b], self.app.tracker.ay[b])
            col = (255, 230, 120) if i == self.anchor_d_idx else (140, 140, 170)
            pygame.draw.line(surface, col, pa, pb, 2 if i == self.anchor_d_idx else 1)
            t = gui.font_small.render("%.0f" % self.anchor_d[i], True,
                                      (255, 230, 120) if i == self.anchor_d_idx else (200, 200, 255))
            surface.blit(t, t.get_rect(center=((pa[0] + pb[0]) / 2, (pa[1] + pb[1]) / 2 - 8)))

    def _draw_anchor_highlight(self, surface, gui):
        a, b = D_PAIRS[self.anchor_d_idx]
        for idx in (a, b):
            p = gui.scr(self.app.tracker.ax[idx], self.app.tracker.ay[idx])
            pygame.draw.rect(surface, (255, 230, 120), (p[0] - 11, p[1] - 11, 22, 22), 3)

    def _draw_panel(self, surface, gui):
        x, y = 10, 10
        surface.blit(gui.font.render("SETUP-MODUS  |  TAB -> GAME", True, (255, 230, 120)), (x, y))
        y += 22
        surface.blit(gui.font_small.render("Anker-Distanzen (gemessen):", True, (200, 200, 200)), (x, y))
        y += 20
        for i in range(6):
            col = (255, 230, 120) if i == self.anchor_d_idx else (200, 200, 200)
            if i == self.anchor_d_idx and self.dist_input:
                val = self.dist_input + "_"
            else:
                val = "%.0f mm" % self.anchor_d[i]
            prefix = "> " if i == self.anchor_d_idx else "  "
            surface.blit(gui.font_small.render("%s%s = %s" % (prefix, D_NAMES[i], val), True, col), (x, y))
            y += 16
        y += 6
        ax, ay = self.app.tracker.ax, self.app.tracker.ay
        for i in range(4):
            surface.blit(gui.font_small.render("A%d = (%.0f, %.0f)" % (i, ax[i], ay[i]), True, (150, 150, 150)), (x, y))
            y += 14
        y += 6
        for ln in (
            "hoch/runter: waehlen   links/rechts: -/+10mm (shift 1mm)",
            "ziffern: wert eingeben   backspace: loeschen   enter: bestaetigen",
            "L: auto-layout   Z/X: P1-/P2-Startposition uebernehmen",
            "R: standard 3x7m   maus: anchors + zonen ziehen   V: config speichern",
        ):
            surface.blit(gui.font_small.render(ln, True, (150, 150, 150)), (x, y))
            y += 14
        if self.status:
            surface.blit(gui.font_small.render(self.status, True, (255, 150, 150)), (x, y))
