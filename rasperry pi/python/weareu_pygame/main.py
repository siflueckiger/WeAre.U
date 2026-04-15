from __future__ import annotations

import sys

import pygame

from visualizer import GameVisualizer


if __name__ == "__main__":
    try:
        GameVisualizer().run()
    except KeyboardInterrupt:
        pygame.quit()
        sys.exit(0)
