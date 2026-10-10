"""Central truth for the WeAre.U OSC protocol.

Imported by both `sender_py/` (Python sender) and `receiver/receiver.py`
(Pi VR headsets). Every value here must match `docs/osc-protocol.md`.
"""

# ============================ NETWORK ============================
LISTEN_PORT = 8000              # receiver listens here; sender targets this
OSC_LOCAL_PORT = 12000          # unused sender-side listen port (oscP5 compat)

# ============================ GAME STATES ============================
STATE_WAIT = 0                  # players must reach their start zones
STATE_PLAYING = 1               # round running
STATE_GAMEOVER = 2              # result screen, auto restart
STATE_READY = 3                 # countdown before round start

STATE_NAMES = {
    STATE_WAIT: "WAIT",
    STATE_PLAYING: "PLAYING",
    STATE_GAMEOVER: "GAMEOVER",
    STATE_READY: "READY",
}

# ============================ FIELD ============================
# Anchor positions A0..A3 in mm -- standard 3x7m layout.
# A0 top left, A1 bottom left, A2 bottom right, A3 top right.
DEFAULT_AX = [0, 0, 7000, 7000]
DEFAULT_AY = [3000, 0, 0, 3000]

# Start positions per player (mm) -- centered, 1 m apart.
DEFAULT_P1_START = [3000, 1500]
DEFAULT_P2_START = [4000, 1500]
START_ZONE_RADIUS_MM = 250

# ============================ TAGS ============================
TAG0_ID = 0x0000
TAG1_ID = 0x0001

C_P1 = (0, 200, 255)           # player 1 (cyan)
C_P2 = (255, 150, 40)          # player 2 (orange)
TRAIL_MAX = 60

# ============================ OSC ADDRESSES ============================
ADDR_P1_POS = "/p1/pos"
ADDR_P2_POS = "/p2/pos"
ADDR_ENT_UPSERT = "/ent/upsert"
ADDR_ENT_POS = "/ent/pos"
ADDR_ENT_REMOVE = "/ent/remove"
ADDR_GAME_STATS = "/game/stats"
ADDR_GAME_OOB = "/game/oob"
ADDR_GAME_MODE = "/game/mode"
ADDR_GAME_RESULT = "/game/result"
ADDR_GAME_HIT = "/game/hit"
ADDR_HUD = "/hud"
ADDR_START_P1 = "/start/p1"
ADDR_START_P2 = "/start/p2"
ADDR_ANCHORS = "/anchors"

# ============================ ENTITY TYPES ============================
ENTITY_SHAPES = {
    "coin": "circle",
    "enemy": "square",
    "powerup": "ring",
    "zone": "ring",
    "obstacle": "rect",
}
