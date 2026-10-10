"""Game mode interface. The engine owns the shared state machine, start zones,
countdown, round timer and out-of-bounds handling; a mode only implements the
round content.
"""

from shared.protocol import STATE_PLAYING


class GameMode:
    id = "base"
    display_name = "Base"

    def __init__(self, engine):
        self.engine = engine

    # lifecycle
    def on_mode_enter(self):
        pass

    def on_round_end(self):
        pass

    def on_round_start(self):
        raise NotImplementedError

    def update(self, dt):
        raise NotImplementedError

    # data
    def scores(self):
        return (0, 0)

    def hud_lines(self):
        return []

    def result_text(self):
        return None

    def player_lives(self, player):
        return -1

    def player_effects(self, player):
        return []

    # input / rendering
    def key_pressed(self, key):
        pass

    def draw_world(self, surface, gui):
        pass

    # engine hook when a player stayed out of bounds too long
    def on_player_out(self, player):
        self.engine.round_winner = 2 if player == 0 else 1
        print("P%d out of bounds -> round over" % (player + 1))
        self.engine.request_end()
