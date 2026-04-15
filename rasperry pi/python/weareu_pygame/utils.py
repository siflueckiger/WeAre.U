from __future__ import annotations

from config import GAME_SIZE


def gx(x: float, viewport_width: int) -> int:
    return int((x / GAME_SIZE) * viewport_width)


def gy(y: float, viewport_height: int) -> int:
    return int((y / GAME_SIZE) * viewport_height)


def draw_text(surface, text, font, color, x, y, align="center"):
    text_surf = font.render(str(text), True, color)
    rect = text_surf.get_rect()

    if align == "center":
        rect.center = (x, y)
    elif align == "left":
        rect.midleft = (x, y)
    elif align == "right":
        rect.midright = (x, y)
    else:
        rect.center = (x, y)

    surface.blit(text_surf, rect)
