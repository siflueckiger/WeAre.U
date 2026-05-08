from __future__ import annotations

import pygame

from config import (
    COL_BG,
    COL_COIN,
    COL_DRAW,
    COL_P1,
    COL_P2,
    COL_TEXT,
    COIN_SIZE,
    FPS,
    GAME_SIZE,
    OSC_PORT,
    PLAYER_SIZE,
    POWERUP_SIZE,
    STATE_GAMEOVER,
    STATE_MENU,
    STATE_PLAYING,
    VIEWPORT_H,
    VIEWPORT_W,
    WINDOW_H,
    WINDOW_W,
)
from models import GameObject, Player
from osc_receiver import OSCReceiver
from utils import draw_text


class GameVisualizer:
    def __init__(self):
        pygame.init()
        pygame.display.set_caption("WeAreU Game Visualizer")
        pygame.mouse.set_visible(False)  

        self.canvas = pygame.Surface((VIEWPORT_W, VIEWPORT_H))
        
        self.screen = pygame.display.set_mode((0,0), pygame.FULLSCREEN)
       
        self.clock = pygame.time.Clock()

        self.font_small = pygame.font.SysFont(None, 18)
        self.font_hud = pygame.font.SysFont(None, 25)
        self.font_menu = pygame.font.SysFont(None, 26)
        self.font_over_big = pygame.font.SysFont(None, 32)
        self.font_over_mid = pygame.font.SysFont(None, 26)
        self.font_over_small = pygame.font.SysFont(None, 22)

        self.state = STATE_MENU
        self.time_left = 0

        self.player_size = int(PLAYER_SIZE * (VIEWPORT_W / GAME_SIZE))
        self.coin_size = int(COIN_SIZE * (VIEWPORT_W / GAME_SIZE))
        self.powerup_size = int(POWERUP_SIZE * (VIEWPORT_W / GAME_SIZE))

        self.p1 = Player("p1", COL_P1)
        self.p2 = Player("p2", COL_P2)
        self.game_objects: list[GameObject] = [GameObject("coin", COL_COIN)]

        self.osc = OSCReceiver("0.0.0.0", OSC_PORT)

    def process_osc_messages(self):
        for address, args in self.osc.poll():
            if address == "/p1/pos" and len(args) >= 2:
                self.p1.x = float(args[0])
                self.p1.y = float(args[1])
            elif address == "/p2/pos" and len(args) >= 2:
                self.p2.x = float(args[0])
                self.p2.y = float(args[1])
            elif address == "/coin/pos" and len(args) >= 2:
                self.game_objects[0].x = float(args[0])
                self.game_objects[0].y = float(args[1])
            elif address == "/game/stats" and len(args) >= 4:
                self.state = int(args[0])
                self.time_left = int(args[1])
                self.p1.score = int(args[2])
                self.p2.score = int(args[3])

    def draw_menu(self, surface: pygame.Surface):
        draw_text(
            surface,
            "Warte auf Spieler...",
            self.font_menu,
            COL_TEXT,
            surface.get_width() // 2,
            surface.get_height() // 2,
            align="center",
        )

    def draw_hud(self, surface: pygame.Surface):
        draw_text(
            surface,
            self.time_left,
            self.font_small,
            COL_TEXT,
            surface.get_width() // 2,
            30,
            align="center",
        )
        draw_text(surface, self.p1.score, self.font_hud, self.p1.color, 20, 30, align="left")
        draw_text(surface, self.p2.score, self.font_hud, self.p2.color, surface.get_width() - 20, 30, align="right")

    def draw_game(self, surface: pygame.Surface):
        for obj in self.game_objects:
            obj.draw(surface, self.coin_size)

        self.p1.draw(surface, self.player_size)
        self.p2.draw(surface, self.player_size)
        self.draw_hud(surface)

    def draw_game_over(self, surface: pygame.Surface):
        cx = surface.get_width() // 2
        cy = surface.get_height() // 2

        draw_text(surface, "GAME OVER", self.font_over_big, COL_TEXT, cx, cy - 60, align="center")

        if self.p1.score > self.p2.score:
            result_text = "SPIELER 1 GEWINNT!"
            result_col = self.p1.color
        elif self.p2.score > self.p1.score:
            result_text = "SPIELER 2 GEWINNT!"
            result_col = self.p2.color
        else:
            result_text = "UNENTSCHIEDEN!"
            result_col = COL_DRAW

        draw_text(surface, result_text, self.font_over_mid, result_col, cx, cy - 10, align="center")
        draw_text(surface, f"P1: {self.p1.score}", self.font_over_small, self.p1.color, cx - 20, cy + 40, align="right")
        draw_text(surface, f"P2: {self.p2.score}", self.font_over_small, self.p2.color, cx + 20, cy + 40, align="left")

    def render(self):
        self.screen.fill(COL_BG)
        self.canvas.fill(COL_BG)

        if self.state == STATE_MENU:
            self.draw_menu(self.canvas)
        elif self.state == STATE_PLAYING:
            self.draw_game(self.canvas)
        elif self.state == STATE_GAMEOVER:
            self.draw_game_over(self.canvas)

        self.screen.blit(self.canvas, (0, 0))
        self.screen.blit(self.canvas, (VIEWPORT_W, 0))
        pygame.display.flip()

    def run(self):
        self.osc.start()
        running = True

        while running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    running = False
                elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                    running = False

            self.process_osc_messages()
            self.render()
            self.clock.tick(FPS)

        self.osc.stop()
        pygame.quit()
