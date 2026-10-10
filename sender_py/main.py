#!/usr/bin/env python3
"""WeAre.U Python sender (game engine + operator GUI).

Replaces the Processing sketch. Runs the UWB tracking, game logic and OSC
output to the Pi VR headsets.

Usage:
    python sender_py/main.py                 # normal GUI
    python sender_py/main.py --sim           # start with virtual players on
    python sender_py/main.py --headless      # no window (daemon)
    python sender_py/main.py --ip 192.168.1.106 --port 8000
"""

import argparse
import os
import sys
import time

# Make the repo root importable (for `shared` and `sender_py`) when this file
# is executed directly.
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from shared.protocol import (  # noqa: E402
    STATE_WAIT, STATE_READY, STATE_PLAYING, STATE_GAMEOVER,
    TAG0_ID, TAG1_ID, DEFAULT_P1_START, DEFAULT_P2_START,
)
from sender_py.tracker import Tracker  # noqa: E402
from sender_py.osc_client import OscClient  # noqa: E402
from sender_py.entities import EntityManager  # noqa: E402
from sender_py.engine import GameEngine  # noqa: E402
from sender_py.virtual_tags import VirtualTags  # noqa: E402
from sender_py.serial_reader import SerialReader  # noqa: E402
from sender_py.gui import Gui, MODE_GAME, MODE_SETUP  # noqa: E402
from sender_py.setup_mode import SetupMode  # noqa: E402


def now_ms():
    return int(time.monotonic() * 1000)


class SenderApp:
    def __init__(self, args):
        self.args = args
        self.tracker = Tracker()
        self.osc = OscClient(args.ip, args.target_port, enabled=True)
        self.entities = EntityManager()
        self.engine = GameEngine(
            self.osc, self.tracker, self.entities,
            list(DEFAULT_P1_START), list(DEFAULT_P2_START))
        self.virtual = VirtualTags(self.tracker, self.osc,
                                   self.engine.p1_start, self.engine.p2_start)

        self.app_mode = MODE_GAME
        self.hud_debug = False
        self.hud_keys = False
        self.use_speed_clamp = True
        self.use_ema = True
        self.smooth_alpha = 0.30

        # serial status
        self.serial_status = "searching"
        self.serial = SerialReader(
            on_frame=self._on_frame, port_hint=args.port_hint,
            on_status=self._on_serial_status)

        # gui / setup
        self.gui = Gui() if not args.headless else None
        self.setup = SetupMode(self)

    # ============================ serial ============================
    def _on_serial_status(self, text):
        self.serial_status = text

    def _on_frame(self, tagid, mask, kalman):
        if self.virtual.on:
            return
        self.tracker.handle_frame(tagid, mask, kalman)
        if tagid in (TAG0_ID, TAG1_ID):
            t = self.tracker.tags.get(tagid)
            if t is not None and t.pos is not None:
                self.osc.pos(tagid, t.pos[0], t.pos[1])

    # ============================ modes / setup ============================
    def set_app_mode(self, mode):
        self.app_mode = mode
        if mode == MODE_GAME:
            self.engine.reset_round()
            self.engine.send_mode_osc()
            self.engine.send_start_zones()
            self.engine.send_anchors()

    # ============================ input (game mode) ============================
    def _is_movement_key(self, key):
        if self.virtual.on is False:
            return False
        return key in (self.virtual.w, self.virtual.a, self.virtual.s, self.virtual.d,
                       self.virtual.up, self.virtual.down,
                       self.virtual.left, self.virtual.right)

    def key_down(self, key, shift):
        import pygame
        if self.app_mode == MODE_SETUP:
            if key != pygame.K_TAB:
                self.setup.key_down(key, shift)
                return
        if key == pygame.K_TAB:
            if self.app_mode == MODE_GAME:
                self.engine.reset_round()
            self.set_app_mode(MODE_SETUP if self.app_mode == MODE_GAME else MODE_GAME)
            return
        if key == pygame.K_v:
            self._toggle_virtual()
            return
        if self.virtual.on and self._is_movement_key(key):
            self.virtual.keys.add(key)
            return
        if key == pygame.K_m:
            self.engine.next_mode()
            return
        if key == pygame.K_r:
            self.engine.reset_round()
            if self.virtual.on:
                self.virtual.reset_players(now_ms())
            print("round reset (R)")
            return
        if key == pygame.K_d:
            self.hud_debug = not self.hud_debug
            return
        if key == pygame.K_h:
            self.hud_keys = not self.hud_keys
            return
        if key == pygame.K_1:
            self.use_speed_clamp = not self.use_speed_clamp
        elif key == pygame.K_2:
            self.use_ema = not self.use_ema
        elif key == pygame.K_4:
            if self.smooth_alpha < 0.25:
                self.smooth_alpha = 0.30
            elif self.smooth_alpha < 0.40:
                self.smooth_alpha = 0.50
            elif self.smooth_alpha < 0.65:
                self.smooth_alpha = 0.80
            else:
                self.smooth_alpha = 0.15
        elif key == pygame.K_SPACE:
            if self.engine.state == STATE_WAIT or self.engine.state == STATE_READY:
                self.engine.debug_start_round()
            elif self.engine.state == STATE_GAMEOVER:
                self.engine.reset_round()

    def key_up(self, key):
        if self.virtual.on and self._is_movement_key(key):
            self.virtual.keys.discard(key)

    def mouse_down(self, pos):
        if self.app_mode == MODE_SETUP:
            self.setup.mouse_down(self.gui, pos)

    def mouse_drag(self, pos):
        if self.app_mode == MODE_SETUP:
            self.setup.mouse_drag(self.gui, pos)

    def mouse_up(self):
        if self.app_mode == MODE_SETUP:
            self.setup.mouse_up()

    def _toggle_virtual(self):
        if self.virtual.on:
            self.engine.reset_round()
            self.virtual.disable()
        else:
            self.engine.reset_round()
            self.virtual.enable(now_ms())

    # ============================ frame ============================
    def update(self):
        self.virtual.update(now_ms())
        if self.app_mode == MODE_GAME:
            self.engine.update()
            self.engine.send_game_osc()

    # ============================ startup ============================
    def start(self):
        self.setup.load_config()
        self.engine.mode.on_mode_enter()
        self.engine.send_mode_osc()
        self.engine.send_start_zones()
        self.engine.send_anchors()
        self.serial.start()
        if self.args.sim:
            self.virtual.enable(now_ms())

    def shutdown(self):
        self.serial.stop()


def run_gui(app):
    import pygame
    pygame.init()
    screen = pygame.display.set_mode((1000, 800))
    pygame.display.set_caption("sender")
    clock = pygame.time.Clock()
    app.virtual.bind(pygame.K_w, pygame.K_a, pygame.K_s, pygame.K_d,
                     pygame.K_UP, pygame.K_DOWN, pygame.K_LEFT, pygame.K_RIGHT)
    app.start()
    running = True
    while running:
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT:
                running = False
            elif ev.type == pygame.KEYDOWN:
                mods = pygame.key.get_mods()
                app.key_down(ev.key, bool(mods & pygame.KMOD_SHIFT))
            elif ev.type == pygame.KEYUP:
                app.key_up(ev.key)
            elif ev.type == pygame.MOUSEBUTTONDOWN and ev.button == 1:
                app.mouse_down(ev.pos)
            elif ev.type == pygame.MOUSEBUTTONUP and ev.button == 1:
                app.mouse_up()
            elif ev.type == pygame.MOUSEMOTION and pygame.mouse.get_pressed()[0]:
                app.mouse_drag(ev.pos)
        app.update()
        app.gui.draw(screen, app)
        pygame.display.flip()
        clock.tick(60)
    app.shutdown()
    pygame.quit()


def run_headless(app):
    app.start()
    try:
        while True:
            app.update()
            time.sleep(1 / 60.0)
    except KeyboardInterrupt:
        pass
    finally:
        app.shutdown()


def main():
    p = argparse.ArgumentParser(description="WeAre.U Python sender")
    p.add_argument("--headless", action="store_true", help="no GUI window")
    p.add_argument("--sim", action="store_true", help="start with virtual players")
    p.add_argument("--ip", default="192.168.1.106", help="receiver IP")
    p.add_argument("--target-port", type=int, default=8000)
    p.add_argument("--port-hint", default="usbmodem", help="serial port substring")
    args = p.parse_args()

    app = SenderApp(args)
    print("OSC -> %s:%d" % (args.ip, args.target_port))
    if args.headless:
        run_headless(app)
    else:
        run_gui(app)


if __name__ == "__main__":
    main()
