import threading
from pythonosc.dispatcher import Dispatcher
from pythonosc.osc_server import BlockingOSCUDPServer
import pygame

# ============================ CONFIG ============================
LISTEN_PORT = 8000      # must match OSC_TARGET_PORT in bu03_visualizer.pde

# Anchor positions A0..A3 in mm -- MUST MATCH the sender sketch.
AX = [1710, 50, 6420, 6550]
AY = [3000, 350, 130, 2960]

TRAIL_MAX = 60
C_T0 = (0, 200, 255)
C_T1 = (255, 150, 40)

FULLSCREEN = True       # False -> fixed window (debug on desktop)
WINDOW_W = 800          # VR headset screen size (split into left/right eye)
WINDOW_H = 480

STALE_MS = 2000         # warn if no packets for this long

MARGIN = 30             # px margin inside each eye viewport
EYE_OFFSET_MM = 150     # horizontal parallax per eye in mm (0 = no stereo)
# ================================================================

tags = {}
packets = 0
last_packet_ms = 0
clock = pygame.time.Clock()
font = None
font_small = None


class TagData:
    def __init__(self, tag_id):
        self.id = tag_id
        self.pos = None
        self.trail = []


def osc_handler(address, *args):
    global packets, last_packet_ms
    if address != "/pos" or len(args) < 3:
        return
    tag_id = int(args[0])
    x = float(args[1])
    y = float(args[2])
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


def start_osc():
    dispatcher = Dispatcher()
    dispatcher.map("/pos", osc_handler)
    server = BlockingOSCUDPServer(("0.0.0.0", LISTEN_PORT), dispatcher)
    print(f"listening for OSC on port {LISTEN_PORT}")
    server.serve_forever()


def tag_color(tag_id):
    if tag_id == 0x0000:
        return C_T0
    if tag_id == 0x0001:
        return C_T1
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
        font_small.render(f"scale: {s:.3f} px/mm  |  grid: 500 mm", True, (150, 150, 150)),
        (10, surface.get_height() - 18),
    )


def render_eye(surface, s, ox, oy, draw_hud_flag):
    surface.fill((22, 22, 22))
    draw_grid(surface, s, ox, oy)
    draw_anchors(surface, s, ox, oy)
    layer = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    for tag_id in tags:
        color = tag_color(tag_id)
        label = "T0" if tag_id == 0x0000 else ("T1" if tag_id == 0x0001 else f"0x{tag_id:04X}")
        draw_tag(surface, layer, tag_id, color, label, s, ox, oy)
    surface.blit(layer, (0, 0))
    if draw_hud_flag:
        draw_hud(surface, s)


def main():
    global font, font_small
    pygame.init()
    if FULLSCREEN:
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
    else:
        screen = pygame.display.set_mode((WINDOW_W, WINDOW_H))
    pygame.display.set_caption("WeAre.U BU03 VR Receiver (pygame)")
    font = pygame.font.Font(None, 20)
    font_small = pygame.font.Font(None, 16)

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
        left = screen.subsurface(pygame.Rect(0, 0, eye_w, h))
        right = screen.subsurface(pygame.Rect(eye_w, 0, eye_w, h))
        s, ox, oy = update_transform(eye_w, h)
        off = EYE_OFFSET_MM * s
        render_eye(left, s, ox + off, oy, draw_hud_flag=True)
        render_eye(right, s, ox - off, oy, draw_hud_flag=False)
        pygame.draw.line(screen, (60, 60, 60), (eye_w, 0), (eye_w, h), 2)
        pygame.display.flip()
        clock.tick(60)
    pygame.quit()


if __name__ == "__main__":
    main()
