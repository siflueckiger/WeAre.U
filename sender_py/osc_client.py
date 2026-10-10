"""OSC output to the VR headsets (protocol v2, see docs/osc-protocol.md)."""

from shared.protocol import (
    ADDR_P1_POS, ADDR_P2_POS, ADDR_ENT_UPSERT, ADDR_ENT_POS, ADDR_ENT_REMOVE,
    ADDR_GAME_STATS, ADDR_GAME_OOB, ADDR_GAME_MODE, ADDR_GAME_RESULT,
    ADDR_GAME_HIT, ADDR_HUD, ADDR_START_P1, ADDR_START_P2, ADDR_ANCHORS,
)

try:
    from pythonosc.udp_client import SimpleUDPClient
    _HAVE_OSC = True
except Exception:
    _HAVE_OSC = False


class OscClient:
    def __init__(self, ip, port, enabled=True):
        self.enabled = enabled and _HAVE_OSC
        self.ip = ip
        self.port = port
        self.sent = 0
        self.client = SimpleUDPClient(ip, port) if self.enabled else None

    def _send(self, addr, args):
        if not self.enabled or self.client is None:
            return
        try:
            self.client.send_message(addr, args)
            self.sent += 1
        except Exception:
            pass

    # ---- players ----
    def pos(self, tagid, x, y):
        from shared.protocol import TAG0_ID
        self._send(ADDR_P1_POS if tagid == TAG0_ID else ADDR_P2_POS, [float(x), float(y)])

    # ---- game ----
    def stats(self, state, time_left, p1, p2, winner):
        self._send(ADDR_GAME_STATS, [int(state), int(time_left), int(p1), int(p2), int(winner)])

    def oob(self, player, seconds_left, active):
        self._send(ADDR_GAME_OOB, [int(player), int(seconds_left), 1 if active else 0])

    def mode(self, mode_id, display_name):
        self._send(ADDR_GAME_MODE, [str(mode_id), str(display_name)])

    def result(self, title, subtitle):
        self._send(ADDR_GAME_RESULT, [str(title), str(subtitle)])

    def hit(self, player, seconds):
        self._send(ADDR_GAME_HIT, [int(player), float(seconds)])

    def hud(self, lines):
        if lines:
            self._send(ADDR_HUD, [str(l) for l in lines])

    # ---- entities ----
    def ent_upsert(self, e):
        self._send(ADDR_ENT_UPSERT, [
            int(e.id), str(e.type), float(e.x), float(e.y), float(e.radius),
            int(e.color[0]), int(e.color[1]), int(e.color[2]), str(e.label),
        ])

    def ent_pos(self, e):
        self._send(ADDR_ENT_POS, [int(e.id), float(e.x), float(e.y)])

    def ent_remove(self, eid):
        self._send(ADDR_ENT_REMOVE, [int(eid)])

    # ---- setup / config ----
    def start_zones(self, p1, p2):
        self._send(ADDR_START_P1, [float(p1[0]), float(p1[1])])
        self._send(ADDR_START_P2, [float(p2[0]), float(p2[1])])

    def anchors(self, ax, ay):
        self._send(ADDR_ANCHORS, [float(v) for v in list(ax) + list(ay)])
