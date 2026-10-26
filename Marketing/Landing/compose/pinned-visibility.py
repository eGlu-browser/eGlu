"""Pinned tabs shown or hidden on each device on its own, as a loop: the iPhone on the left in the
generated hand, Safience for Mac close up on the right with its Settings window over the browser.

A  the iPhone's pinned list, held open: Instagram is in it.
B  iPhone Settings > Pinned Tabs: the right thumb switches Instagram off. The Mac keeps it.
C  the iPhone's pinned list again: without Instagram.
M  the Mac: its pointer switches Instagram off (the tile leaves the sidebar), then on again.
D  iPhone Settings > Pinned Tabs: Instagram switched on again; back to the start.

python pinned-visibility.py VIS_DIR hand.png bezel.png mac.mov MAC_OFFSET out.mp4 [--still t out.png]

VIS_DIR holds the iPhone recordings seg-list-with, seg-off, seg-list-without, seg-on (.mp4).
MAC_OFFSET: the Mac recording's time when its pointer script's clock is 0.
"""
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

# The drawn lines (hand, tap lines, press arc) in the site's sky blue, its dark-mode --blue.
LINE = (61, 155, 233)

vis_dir, hand_png, bezel_png, mac_mov, mac_offset, out = sys.argv[1:7]
mac_offset = float(mac_offset)
still = None
if "--still" in sys.argv:
    k = sys.argv.index("--still")
    still = (float(sys.argv[k + 1]), sys.argv[k + 2])

FPS = 60
CW, CH, BG = 2730, 1536, (17, 17, 19)

# The phone, as in mockup3.py.
S = 0.3815
BX, BY = 380.6, 116.7
bezel = Image.open(bezel_png).convert("RGBA").resize((round(1470 * S), round(3000 * S)), Image.LANCZOS)
SX, SY = round(BX + 75 * S), round(BY + 66 * S)
SW, SH, SR = round(1320 * S), round(2868 * S), 245 * S
mask = Image.new("L", (SW * 4, SH * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, SW * 4 - 1, SH * 4 - 1), radius=SR * 4, fill=255)
mask = mask.resize((SW, SH), Image.LANCZOS)
PT = SW / 402
MID = BX + 1470 * S / 2


def screen_pt(x, y):
    return SX + x * PT, SY + y * PT


# The Mac: its recording of the rect from (560, 206), two pixels a point, the browser's corner 160
# pixels in; shown one recorded pixel to a canvas pixel, the browser's corner level with the phone.
ZOOM = 1.0
WX, WY = 1060, 124.7
cx0, cy0 = int(160 - 120 / ZOOM), max(int(160 - WY / ZOOM), 0)
cx1, cy1 = min(int(160 + (CW - WX) / ZOOM) + 2, 2880), min(int(160 + (CH - WY) / ZOOM) + 2, 1960)
MW, MH = round((cx1 - cx0) * ZOOM), round((cy1 - cy0) * ZOOM)
MX, MY = round(WX + (cx0 - 160) * ZOOM), round(WY + (cy0 - 160) * ZOOM)


def mac_canvas(p):
    return WX + ((p[0] - 560) * 2 - 160) * ZOOM, WY + ((p[1] - 206) * 2 - 160) * ZOOM


# The hands: the drawing's left hand, its wrist fading out where it leaves the drawing; and the same
# mirrored about the phone's middle, a right hand on its right edge, fading out past the phone.
def smoothstep(f):
    f = np.clip(f, 0, 1)
    return f * f * (3 - 2 * f)


left = Image.open(hand_png).convert("RGBA")
_a = np.asarray(left).astype(np.float32)
_a[..., 3] *= smoothstep((1535 - np.arange(_a.shape[0])) / 260)[:, None] * smoothstep(np.arange(_a.shape[1]) / 130)[None, :]
left = Image.fromarray(_a.astype(np.uint8), "RGBA")
PAD_L = np.array(screen_pt(36.6, 445.5))  # the left thumb's pad, as drawn
right = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
right.paste(left.transpose(Image.FLIP_LEFT_RIGHT), (round(2 * MID - 1024), 0))
PAD_R = np.array([2 * MID - PAD_L[0], PAD_L[1]])
RIGHT_FADE = smoothstep((1000 - np.arange(CW)) / 70)[None, :]


def ease_out(k):
    k = min(max(k, 0), 1)
    return 1 - (1 - k) ** 3


def smooth(k):
    k = min(max(k, 0), 1)
    return k * k * (3 - 2 * k)


def hand_layer(side, touch, presence, arriving):
    """The hand ("left" or "right") with its pad on touch (screen points), coming in or going out:
    presence 0..1, from below and outside when it is less than 1."""
    x, y = touch
    e = ease_out(presence) if arriving else 1 - ease_out(1 - presence)
    away = 1 - e
    layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    if side == "left":
        # Along the phone's edge most of the way, so its edge stays on the bezel (mockup3.py).
        dx, dy = 0.7 * (x - 36.6) * PT, (y - 445.5) * PT
        layer.paste(left, (round(dx - 50 * away), round(dy + 60 * away)))
        arr = np.asarray(layer).astype(np.float32)
    else:
        tx, ty = screen_pt(x, y)
        layer.paste(right, (round(tx - PAD_R[0] + 50 * away), round(ty - PAD_R[1] + 60 * away)))
        arr = np.asarray(layer).astype(np.float32)
        arr[..., 3] *= RIGHT_FADE
    arr[..., 3] *= e
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


# The marks: an arc that fills round the thumb while it holds, lines that burst out at a tap.
SS = 3
ARC = 120
BURST = 0.4


def draw_burst(g, cx, cy, k, radius, length, angles):
    u = k / BURST
    if not 0 <= u < 1:
        return
    inner = radius + length * 0.9 * ease_out(u)
    outer = radius + length * 0.35 + length * 1.1 * ease_out(min(u * 1.6, 1))
    alpha = round(240 * (1 - smooth((u - 0.35) / 0.65)))
    w = round(3.2 * SS)
    for a in angles:
        c, s = np.cos(np.radians(a)), np.sin(np.radians(a))
        p0 = ((cx + c * inner) * SS, (cy + s * inner) * SS)
        p1 = ((cx + c * outer) * SS, (cy + s * outer) * SS)
        g.line([p0, p1], fill=(*LINE, alpha), width=w)
        for q in (p0, p1):
            g.ellipse((q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2), fill=(*LINE, alpha))


def draw_arc(g, cx, cy, fill, fade):
    cx, cy, r = cx * SS, cy * SS, ARC * SS
    w = round(3.2 * SS)
    box = (cx - r, cy - r, cx + r, cy + r)
    g.ellipse(box, outline=(*LINE, round(60 * fade)), width=w)
    if fill > 0:
        end = -90 + 360 * fill
        g.arc(box, -90, end, fill=(*LINE, round(240 * fade)), width=w)
        for a in (-90, end):
            ex, ey = cx + (r - w / 2) * np.cos(np.radians(a)), cy + (r - w / 2) * np.sin(np.radians(a))
            g.ellipse((ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=(*LINE, round(240 * fade)))


def marks_layer(arcs, bursts):
    if not arcs and not bursts:
        return None
    pts = [(a[0], a[1]) for a in arcs] + [(b[0], b[1]) for b in bursts]
    x0 = int(min(p[0] for p in pts)) - 200
    y0 = int(min(p[1] for p in pts)) - 200
    x1 = int(max(p[0] for p in pts)) + 200
    y1 = int(max(p[1] for p in pts)) + 200
    big = Image.new("RGBA", ((x1 - x0) * SS, (y1 - y0) * SS), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    for cx, cy, fill, fade in arcs:
        draw_arc(g, cx - x0, cy - y0, fill, fade)
    for cx, cy, k, radius, length, angles in bursts:
        draw_burst(g, cx - x0, cy - y0, k, radius, length, angles)
    return big.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0)


# ----- The timeline ---------------------------------------------------------------------------
# Each phone part: its recording, and its times there against the loop's (piecewise straight,
# flat where the recording is held). Each hand: when it is there and where its pad is.
BUTTON, ROW = (34, 764), (120, 762)
SWITCH = (342, 250)
XF = 0.35  # cross-fades between the phone's parts


def long_press_part(name, t0, src_still, down, opens, move, release):
    """The pinned list held open, as A and C: the hand comes in (0.6 s), rests, presses at t0 + 1;
    the hold is drawn out by HOLD seconds; the thumb moves onto the tab on screen and lets go."""
    HOLD = 0.55
    t_down = t0 + 1.0
    keys = [(t0, src_still), (t_down, down), (t_down + 0.07, down + 0.07), (t_down + 0.07 + HOLD, down + 0.07)]
    shift = t_down + 0.07 + HOLD - (down + 0.07)  # loop time = source time + shift, after the hold
    end_src = release + 0.35
    keys.append((end_src + shift, end_src))
    t_open = opens + shift
    t_move = (move[0] + shift, move[1] + shift)
    t_release = release + shift
    return dict(name=name, keys=keys, start=t0, end=end_src + shift, down=t_down, open=t_open,
                move=t_move, release=t_release)


def tap_part(name, t0, src_still, down, up, src_hold, hold_until):
    """A switch tapped, as B and D: the right hand comes in (0.5 s), rests, taps at t0 + 0.75,
    lets go and leaves; the recording is held on the switch's new state until hold_until."""
    t_down = t0 + 0.75
    keys = [(t0, src_still), (t_down, down), (t_down + (src_hold - down), src_hold), (hold_until, src_hold)]
    return dict(name=name, keys=keys, start=t0, end=hold_until, down=t_down, up=t_down + (up - down))


A = long_press_part("seg-list-with", 0.0, 1.0, down=1.53, opens=1.97, move=(2.6, 2.9), release=3.75)
B = tap_part("seg-off", A["end"] + XF, 1.0, down=1.58, up=1.70, src_hold=1.95, hold_until=A["end"] + XF + 1.9)
C = long_press_part("seg-list-without", B["end"] + XF, 0.9, down=1.49, opens=1.93, move=(2.6, 2.9), release=3.95)
MAC_START = C["end"] + 0.15
MAC_LEN = 4.6
MAC_CLICKS = (1.0, 2.8)
D = tap_part("seg-on", MAC_START + MAC_LEN + 0.1 + XF, 8.6, down=9.15, up=9.27, src_hold=9.45,
             hold_until=MAC_START + MAC_LEN + 0.1 + XF + 1.9)
TOTAL_T = D["end"] + XF
TOTAL = round(TOTAL_T * FPS)
PARTS = [A, B, C, D]
print(f"loop {TOTAL_T:.2f} s; A {A['start']:.2f}-{A['end']:.2f} B {B['start']:.2f}-{B['end']:.2f} "
      f"C {C['start']:.2f}-{C['end']:.2f} Mac {MAC_START:.2f}-{MAC_START + MAC_LEN:.2f} D {D['start']:.2f}-{D['end']:.2f}")


def source_time(part, t):
    ks = part["keys"]
    return float(np.interp(t, [k[0] for k in ks], [k[1] for k in ks]))


# ----- Frames -----------------------------------------------------------------------------------
class Reader:
    """A recording's frames in order, at 60 a second, scaled; the one at a time asked for."""

    def __init__(self, path, size, vf_extra="", start=0.0):
        self.size, self.start = size, start
        vf = f"fps={FPS}" + (f",{vf_extra}" if vf_extra else "") + f",scale={size[0]}:{size[1]}:flags=lanczos"
        args = ["ffmpeg", "-v", "error"] + (["-ss", str(start)] if start else []) + ["-i", path, "-vf", vf,
                                                                                     "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        self.p = subprocess.Popen(args, stdout=subprocess.PIPE)
        self.index, self.frame = -1, None

    def at(self, t):
        want = max(round((t - self.start) * FPS), 0)
        while self.index < want:
            data = self.p.stdout.read(self.size[0] * self.size[1] * 3)
            if len(data) < self.size[0] * self.size[1] * 3:
                break
            self.frame = Image.frombytes("RGB", self.size, data)
            self.index += 1
        return self.frame

    def close(self):
        self.p.kill()


readers = {p["name"]: Reader(f"{vis_dir}/{p['name']}.mp4", (SW, SH)) for p in PARTS}
mac_crop = f"crop={cx1 - cx0}:{cy1 - cy0}:{cx0}:{cy0}"
mac_reader = Reader(mac_mov, (MW, MH), mac_crop, start=max(mac_offset - 0.5, 0))
MAC_REST = 0.1  # script time of the Mac's frame while it waits
mac_rest = mac_reader.at(mac_offset + MAC_REST).copy()

# The Mac's pointer path (pointer2.swift), for where its click marks go.
MAC_SWITCH = (1369, 686)


def phone_screen(t):
    """The phone's screen at loop time t: its part's frame, or a cross-fade between two parts'."""
    for i, p in enumerate(PARTS):
        if p["start"] <= t < p["end"]:
            return readers[p["name"]].at(source_time(p, t))
        nxt = PARTS[(i + 1) % len(PARTS)]
        gap_end = nxt["start"] if i + 1 < len(PARTS) else TOTAL_T
        if p["end"] <= t < gap_end:
            a = readers[p["name"]].at(source_time(p, p["end"]))
            if p is C and t < D["start"] - XF:
                return a  # the browser waits while the Mac has its turn
            first = readers_first[nxt["name"]]
            # Ending on the next part's first frame exactly: the loop's last frame meets its first.
            k = smooth((t - (gap_end - XF)) / (XF - 1 / FPS))
            return Image.blend(a, first, k)
    return readers_first[A["name"]]


# Each part's first frame, for the cross-fades into it (read now, from separate readers).
readers_first = {}
for p in PARTS:
    r = Reader(f"{vis_dir}/{p['name']}.mp4", (SW, SH))
    readers_first[p["name"]] = r.at(p["keys"][0][1]).copy()
    r.close()


def mac_frame(t):
    if MAC_START <= t < MAC_START + MAC_LEN:
        return mac_reader.at(mac_offset + MAC_REST + (t - MAC_START))
    return mac_rest


def hands_and_marks(t):
    hands, arcs, bursts = [], [], []
    for p in (A, C):
        if p["start"] <= t < p["end"] + 0.4:
            come, rest_end = p["start"] + 0.6, p["down"] - 0.15
            # Where the pad is: short of the button while it rests, on it, then over to the tab on screen.
            if t < rest_end:
                touch = (BUTTON[0] - 13 / PT, BUTTON[1] + 16 / PT)
            elif t < p["down"]:
                k = smooth((t - rest_end) / 0.15)
                touch = (BUTTON[0] - 13 / PT * (1 - k), BUTTON[1] + 16 / PT * (1 - k))
            else:
                k = smooth((t - p["move"][0]) / (p["move"][1] - p["move"][0]))
                touch = (BUTTON[0] + (ROW[0] - BUTTON[0]) * k, BUTTON[1] + (ROW[1] - BUTTON[1]) * k)
            if t < come:
                hands.append(("left", touch, (t - p["start"]) / 0.6, True))
            elif t < p["release"]:
                hands.append(("left", touch, 1.0, True))
            else:
                hands.append(("left", touch, 1 - (t - p["release"]) / 0.35, False))
            if p["down"] <= t < p["open"] + 0.2:
                cx, cy = screen_pt(*BUTTON)
                fill = min((t - p["down"]) / (p["open"] - p["down"]), 1)
                fade = ease_out((t - p["down"]) / 0.1) if t < p["open"] else 1 - smooth((t - p["open"]) / 0.2)
                arcs.append((cx, cy, fill, fade))
            if 0 <= t - p["open"] < BURST:
                cx, cy = screen_pt(*BUTTON)
                bursts.append((cx, cy, t - p["open"], ARC + 10, 26, (-105, -60, -15)))
    for p in (B, D):
        if p["start"] <= t < p["up"] + 0.45:
            come = p["start"] + 0.5
            if t < come:
                hands.append(("right", SWITCH, (t - p["start"]) / 0.5, True))
            elif t < p["up"] + 0.05:
                hands.append(("right", SWITCH, 1.0, True))
            else:
                hands.append(("right", SWITCH, 1 - (t - p["up"] - 0.05) / 0.35, False))
        if 0 <= t - p["down"] < BURST:
            cx, cy = screen_pt(*SWITCH)
            # The right thumb comes from the lower right: its lines go up and to the left.
            bursts.append((cx, cy, t - p["down"], 46, 22, (-165, -120, -75)))
    for c in MAC_CLICKS:
        k = t - (MAC_START + c - MAC_REST)
        if 0 <= k < BURST:
            mx, my = mac_canvas(MAC_SWITCH)
            bursts.append((mx, my, k, 34, 20, (-170, -125, -80)))
    return hands, arcs, bursts


back = Image.new("RGBA", (CW, CH), BG + (255,))


def frame_at(t):
    canvas = back.copy()
    canvas.paste(mac_frame(t), (MX, MY))
    canvas.paste(phone_screen(t).resize((SW, SH)), (SX, SY), mask)
    canvas.alpha_composite(bezel, (round(BX), round(BY)))
    hands, arcs, bursts = hands_and_marks(t)
    mark = marks_layer(arcs, bursts)
    if mark:
        canvas.alpha_composite(mark[0], mark[1])
    for side, touch, presence, arriving in hands:
        if presence > 0:
            canvas.alpha_composite(hand_layer(side, touch, min(presence, 1), arriving))
    return canvas.convert("RGB")


writer = None
if not still:
    writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{CW}x{CH}",
                               "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                               "-movflags", "+faststart", out], stdin=subprocess.PIPE)
for n in range(TOTAL):
    t = n / FPS
    if still:
        if t + 1e-9 < still[0]:
            phone_screen(t), mac_frame(t)  # keep the readers moving
            continue
        frame_at(t).save(still[1])
        break
    writer.stdin.write(frame_at(t).tobytes())
for r in readers.values():
    r.close()
mac_reader.close()
if writer:
    writer.stdin.close()
    writer.wait()
print("frames", TOTAL)
