from __future__ import annotations

from dataclasses import dataclass

import pygame

from utils import gx, gy


@dataclass
class Player:
    player_id: str
    color: tuple[int, int, int]
    x: float = 0.0
    y: float = 0.0
    score: int = 0

    def draw(self, surface: pygame.Surface, size: int):
        pygame.draw.circle(
            surface,
            self.color,
            (gx(self.x, surface.get_width()), gy(self.y, surface.get_height())),
            max(1, size // 2),
        )


@dataclass
class GameObject:
    obj_type: str
    color: tuple[int, int, int]
    x: float = 0.0
    y: float = 0.0
    active: bool = True

    def draw(self, surface: pygame.Surface, size: int):
        if not self.active:
            return

        cx = gx(self.x, surface.get_width())
        cy = gy(self.y, surface.get_height())
        rect = pygame.Rect(0, 0, size, size)
        rect.center = (cx, cy)
        pygame.draw.rect(surface, self.color, rect)


class PowerUp(GameObject):
    def __init__(self):
        super().__init__(obj_type="powerup", color=(0, 255, 100))

    def draw(self, surface: pygame.Surface, size: int):
        if not self.active:
            return

        cx = gx(self.x, surface.get_width())
        cy = gy(self.y, surface.get_height())
        half = size // 2
        points = [(cx, cy - half), (cx - half, cy + half), (cx + half, cy + half)]
        pygame.draw.polygon(surface, self.color, points)


class Obstacle(GameObject):
    def __init__(self):
        super().__init__(obj_type="obstacle", color=(150, 150, 150))

    def draw(self, surface: pygame.Surface, size: int):
        if not self.active:
            return

        cx = gx(self.x, surface.get_width())
        cy = gy(self.y, surface.get_height())
        rect = pygame.Rect(0, 0, size * 2, size)
        rect.center = (cx, cy)
        pygame.draw.rect(surface, self.color, rect)
