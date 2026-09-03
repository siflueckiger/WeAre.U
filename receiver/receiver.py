import os
import threading
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import pygame

# ============================ CONFIG ============================
LISTEN_PORT = 8000      # must match OSC_TARGET_PORT in sender/sender.pde

# Anchor positions A0..A3 in mm -- standard 3x7m layout.
# Synced live from the sender via /anchors (setup mode); fallback below.
AX = [0, 0, 7000, 7000]
AY = [3000, 0, 0, 3000]

TRAIL_MAX = 60
C_P1 = (0, 200, 255)
C_P2 = (255, 150, 40)

# Game states -- MUST MATCH sender/sender.pde
STATE_WAIT = 0
STATE_PLAYING = 1
STATE_GAMEOVER = 2
STATE_READY = 3

# Start zones -- synced live from the sender via /start/p1 and /start/p2
# (setup mode). The values below are only fallbacks.
P1_START = [1200, 2400]
P2_START = [5400, 700]
START_ZONE_RADIUS_MM = 250

C_COIN = (255, 220, 40)
COIN_PX = 10

FULLSCREEN = True       # False -> fixed window (debug on desktop)
WINDOW_W = 800          # VR headset screen size (split into left/right eye)
WINDOW_H = 480

STALE_MS = 2000         # warn if no packets for this long

MARGIN = 30             # px margin inside each eye viewport
EYE_OFFSET_MM = 150     # horizontal parallax per eye in mm (0 = no stereo)

# Rotate image 180 deg if display is mounted upside down.
# Override: BU03_FLIP_180=0 python receiver.py
FLIP_180 = os.environ.get("BU03_FLIP_180", "1") == "1"
# ================================================================

tags = {}
packets = 0
last_packet_ms = 0
game_state = STATE_WAIT
time_left = 0
p1_score = 0
p2_score = 0
coin_pos = None
oob = {0: None, 1: None}   # player_index -> (seconds_left, active) or None
winner = -1                # -1 = derive from scores, 1/2 = forced winner
clock = pygame.time.Clock()
font = None
font_small = None
font_mid = None
font_big = None


class TagData:
    def __init__(self, tag_id):
        self.id = tag_id
        self.pos = None
        self.trail = []


def make_pos_handler(tag_id):
    def handler(address, *args):
        global packets, last_packet_ms
        if len(args) < 2:
            return
        x, y = float(args[0]), float(args[1])
        packets += 1
        last_packet_ms = pygame.time.get_ticks()
        t = tags.get(tag_id)
        if t is None:
            t = TagData(tag_id)
            tags[tag_id] = t
        t.pos = (x, y)
        t.trail.append(t.pos)
        if len(t.trail) > TRAIL_MAX:
            t.trail.pop(0)
    return handler


def coin_handler(address, *args):
    global coin_pos
    if len(args) < 2:
        return
    coin_pos = (float(args[0]), float(args[1]))


def make_start_handler(zone):
    def handler(address, *args):
        if len(args) < 2:
            return
        zone[0] = float(args[0])
        zone[1] = float(args[1])
    return handler


def anchors_handler(address, *args):
    if len(args) < 8:
        return
    for i in range(4):
        AX[i] = float(args[i])
        AY[i] = float(args[i + 4])


def stats_handler(address, *args):
    global game_state, time_left, p1_score, p2_score, winner, packets, last_packet_ms
    if len(args) < 4:
        return
    packets += 1
    last_packet_ms = pygame.time.get_ticks()
    game_state = int(args[0])
    time_left = int(args[1])
    p1_score = int(args[2])
    p2_score = int(args[3])
    winner = int(args[4]) if len(args) >= 5 else -1


def oob_handler(address, *args):
    if len(args) < 3:
        return
    player = int(args[0])
    seconds = int(args[1])
    active = int(args[2])
    oob[player] = (seconds, active)


def start_osc():
    dispatcher = Dispatcher()
    dispatcher.map("/p1/pos", make_pos_handler(0x0000))
    dispatcher.map("/p2/pos", make_pos_handler(0x0001))
    dispatcher.map("/coin/pos", coin_handler)
    dispatcher.map("/game/stats", stats_handler)
    dispatcher.map("/game/oob", oob_handler)
    dispatcher.map("/start/p1", make_start_handler(P1_START))
    dispatcher.map("/start/p2", make_start_handler(P2_START))
    dispatcher.map("/anchors", anchors_handler)
    server = BlockingOSCUDPServer(("0.0.0.0", LISTEN_PORT), dispatcher)
    print(f"listening for OSC on port {LISTEN_PORT}")
    server.serve_forever()


def tag_color(tag_id):
    if tag_id == 0x0000:
        return C_P1
    if tag_id == 0x0001:
        return C_P2
    return (200, 200, 255)


def update_transform(surface_w, surface_h):
    min_x, max_x = min(AX), max(AX)
    min_y, max_y = min(AY), max(AY)
    world_w = max_x - min_x
    world_h = max_y - min_y
    if world_w < 1:
        world_w = 1000
    if world_h < 1:
        world_h = 1000
    s = min((surface_w - 2 * MARGIN) / world_w, (surface_h - 2 * MARGIN) / world_h)
    ox = (surface_w - world_w * s) / 2 - min_x * s
    oy = (surface_h + world_h * s) / 2 + min_y * s
    return s, ox, oy


def scr(x, y, s, ox, oy):
    return int(ox + x * s), int(oy - y * s)


def draw_grid(surface, s, ox, oy):
    min_x, max_x = min(AX), max(AX)
    min_y, max_y = min(AY), max(AY)
    step = 500
    gx = (min_x // step) * step
    while gx <= max_x:
        a = scr(gx, min_y, s, ox, oy)
        b = scr(gx, max_y, s, ox, oy)
        pygame.draw.line(surface, (45, 45, 45), a, b, 1)
        gx += step
    gy = (min_y // step) * step
    while gy <= max_y:
        a = scr(min_x, gy, s, ox, oy)
        b = scr(max_x, gy, s, ox, oy)
        pygame.draw.line(surface, (45, 45, 45), a, b, 1)
        gy += step


def draw_anchors(surface, s, ox, oy):
    for i in range(len(AX)):
        p = scr(AX[i], AY[i], s, ox, oy)
        rect = pygame.Rect(p[0] - 8, p[1] - 8, 16, 16)
        pygame.draw.rect(surface, (90, 200, 90), rect)
        pygame.draw.rect(surface, (200, 200, 200), rect, 2)
        label = font_small.render("A" + str(i), True, (255, 255, 255))
        surface.blit(label, label.get_rect(center=(p[0], p[1] - 10)))


def draw_tag(surface, layer, tag_id, color, label, s, ox, oy):
    t = tags.get(tag_id)
    if t is None:
        return
    if len(t.trail) >= 2:
        for i in range(1, len(t.trail)):
            a = scr(t.trail[i - 1][0], t.trail[i - 1][1], s, ox, oy)
            b = scr(t.trail[i][0], t.trail[i][1], s, ox, oy)
            f = int(15 + (i - 1) * (200 - 15) / max(1, len(t.trail) - 2))
            pygame.draw.line(layer, (*color, f), a, b, 2)
    if t.pos is not None:
        p = scr(t.pos[0], t.pos[1], s, ox, oy)
        pygame.draw.circle(surface, color, p, 7)
        pygame.draw.circle(surface, (255, 255, 255), p, 7, 2)
        label_surf = font_small.render(label, True, (255, 255, 255))
        surface.blit(label_surf, (p[0] + 10, p[1] - 8))


def draw_hud(surface, s):
    age = pygame.time.get_ticks() - last_packet_ms
    if last_packet_ms == 0:
        text = f"Waiting for OSC on port {LISTEN_PORT} ..."
        color = (255, 120, 120)
    elif age > STALE_MS:
        text = f"STALE: no packets for {age / 1000.0} s"
        color = (255, 120, 120)
    else:
        text = f"OSC :{LISTEN_PORT}  |  packets: {packets}  |  age: {age} ms"
        color = (180, 230, 180)
    surface.blit(font.render(text, True, color), (10, 10))
    y = 30
    for tag_id, t in tags.items():
        surface.blit(font.render(f"0x{tag_id:04X}", True, tag_color(tag_id)), (10, y))
        pos_text = f"pos=({t.pos[0]:.0f}, {t.pos[1]:.0f}) mm" if t.pos is not None else "no pos"
        surface.blit(font.render(pos_text, True, (255, 255, 255)), (60, y))
        y += 20
    surface.blit(
        font.render(
            f"state={game_state} time={time_left} p1={p1_score} p2={p2_score} coin={coin_pos}",
            True, (200, 200, 200),
        ),
        (10, y),
    )
    y += 20
    surface.blit(
        font_small.render(f"scale: {s:.3f} px/mm  |  grid: 500 mm", True, (150, 150, 150)),
        (10, surface.get_height() - 18),
    )


def fmt_mmss(seconds):
    return f"{int(seconds) // 60}:{int(seconds) % 60:02d}"


def draw_center_text(surface, text, fnt, color, dy=0):
    surf = fnt.render(text, True, color)
    rect = surf.get_rect(center=(surface.get_width() // 2, surface.get_height() // 2 + dy))
    surface.blit(surf, rect)


def draw_start_zones(surface, s, ox, oy):
    for p, label, color in ((P1_START, "P1", C_P1), (P2_START, "P2", C_P2)):
        c = scr(p[0], p[1], s, ox, oy)
        r = max(1, int(START_ZONE_RADIUS_MM * s))
        pygame.draw.circle(surface, color, c, r, 2)
        label_surf = font_mid.render(label, True, color)
        surface.blit(label_surf, label_surf.get_rect(center=c))


def draw_coin(surface, s, ox, oy):
    if coin_pos is None:
        return
    c = scr(coin_pos[0], coin_pos[1], s, ox, oy)
    pygame.draw.circle(surface, C_COIN, c, COIN_PX)
    pygame.draw.circle(surface, (255, 255, 255), c, COIN_PX, 2)


def draw_game_hud(surface):
    w = surface.get_width()
    timer_surf = font_mid.render(fmt_mmss(time_left), True, (255, 255, 255))
    surface.blit(timer_surf, timer_surf.get_rect(midtop=(w // 2, 8)))
    s1 = font_mid.render(str(p1_score), True, C_P1)
    surface.blit(s1, s1.get_rect(topleft=(12, 8)))
    s2 = font_mid.render(str(p2_score), True, C_P2)
    surface.blit(s2, s2.get_rect(topright=(w - 12, 8)))


def draw_game_overlay(surface):
    if game_state == STATE_WAIT:
        draw_center_text(surface, "Warte auf Spieler...", font_mid, (255, 255, 255))
    elif game_state == STATE_READY:
        draw_center_text(surface, str(max(1, time_left)), font_big, (255, 255, 255))
    elif game_state == STATE_GAMEOVER:
        draw_center_text(surface, "GAME OVER", font_big, (255, 255, 255), -40)
        w = winner
        if w == -1:
            w = 1 if p1_score > p2_score else (2 if p2_score > p1_score else 0)
        if w == 1:
            draw_center_text(surface, "SPIELER 1 GEWINNT!", font_mid, C_P1, 10)
        elif w == 2:
            draw_center_text(surface, "SPIELER 2 GEWINNT!", font_mid, C_P2, 10)
        else:
            draw_center_text(surface, "UNENTSCHIEDEN!", font_mid, (200, 200, 200), 10)
        draw_center_text(surface, f"P1: {p1_score}   P2: {p2_score}", font, (255, 255, 255), 50)


def draw_oob_warning(surface):
    warnings = []
    for player, color, label in ((0, C_P1, "P1"), (1, C_P2, "P2")):
        v = oob.get(player)
        if v and v[1]:
            warnings.append((color, label, v[0]))
    if not warnings:
        return
    base = surface.get_height() // 2 - 40
    for i, (color, label, seconds) in enumerate(warnings):
        text = f"{label}: GO BACK NOW OR LOSE A LIFE  ({seconds})"
        surf = font_mid.render(text, True, color)
        rect = surf.get_rect(center=(surface.get_width() // 2, base + i * 44))
        bar = pygame.Rect(0, rect.y - 6, surface.get_width(), rect.height + 12)
        pygame.draw.rect(surface, (120, 0, 0), bar)
        surface.blit(surf, rect)


def render_eye(surface, s, ox, oy, draw_debug_hud):
    surface.fill((22, 22, 22))
    draw_grid(surface, s, ox, oy)
    draw_anchors(surface, s, ox, oy)
    layer = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    for tag_id in tags:
        color = tag_color(tag_id)
        label = "P1" if tag_id == 0x0000 else ("P2" if tag_id == 0x0001 else f"0x{tag_id:04X}")
        draw_tag(surface, layer, tag_id, color, label, s, ox, oy)
    surface.blit(layer, (0, 0))
    if game_state in (STATE_WAIT, STATE_READY):
        draw_start_zones(surface, s, ox, oy)
    if game_state == STATE_PLAYING:
        draw_coin(surface, s, ox, oy)
        draw_game_hud(surface)
    draw_game_overlay(surface)
    draw_oob_warning(surface)
    if draw_debug_hud:
        draw_hud(surface, s)


def main():
    global font, font_small, font_mid, font_big
    pygame.init()
    if FULLSCREEN:
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    else:
        screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
    pygame.display.set_caption("WeAre.U BU03 VR Receiver (pygame)")
    font = pygame.font.Font(None, 20)
    font_small = pygame.font.Font(None, 16)
    font_mid = pygame.font.Font(None, 36)
    font_big = pygame.font.Font(None, 64)

    threading.Thread(target=start_osc, daemon=True).start()

    running = True
    while running:
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
            elif event.type == pygame.KEYDOWN and event.key == pygame.K_ESCAPE:
                running = False
        w, h = screen.get_size()
        eye_w = w // 2
        left = pygame.Surface((eye_w, h))
        right = pygame.Surface((eye_w, h))
        s, ox, oy = update_transform(eye_w, h)
        off = EYE_OFFSET_MM * s
        render_eye(left, s, ox + off, oy, draw_debug_hud=True)
        render_eye(right, s, ox - off, oy, draw_debug_hud=False)
        if FLIP_180:
            left = pygame.transform.flip(left, True, True)
            right = pygame.transform.flip(right, True, True)
        screen.blit(left, (0, 0))
        screen.blit(right, (eye_w, 0))
        pygame.draw.line(screen, (60, 60, 60), (eye_w, 0), (eye_w, h), 2)
        pygame.display.flip()
        clock.tick(60)
    pygame.quit()


if __name__ == "__main__":
    main()
