"""mockup5.py's picture as a loop, with the presses shown: the iPhone held in the generated hand
on the left, Safience for Mac close up on the right, crossing the same pinned tabs on one clock.
The hand comes in onto the pinned button, short lines burst from the thumb's tip as it lands and as it
lifts, and from the Mac pointer's tip as it clicks; at the end both go back to
the first frame, so the last frame meets the first. The long press is held longer than it was
recorded (EXTRA) and shown by an arc that fills round the thumb's tip.

python pinned-switch.py raw.mp4 hand-lines.png bezel.png mac.mov OFFSET out.mp4 [--zoom Z] [--still t out.png [--dot]]

t, for --still, is on the loop's clock: the main part starts LEAD seconds in.

OFFSET: the Mac recording's time when the phone recording's is 0.
"""
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

# The drawn lines (hand, tap lines, press arc) in the site's sky blue, its dark-mode --blue.
LINE = (61, 155, 233)

raw, hand_png, bezel_png, mac_mov, offset, out = sys.argv[1:7]
offset = float(offset)
still = None
if "--still" in sys.argv:
    k = sys.argv.index("--still")
    still = (float(sys.argv[k + 1]), sys.argv[k + 2])
dot = "--dot" in sys.argv

# The backdrop behind the Mac window when it was recorded, as the recording decodes it. 16:9.
CW, CH, BG = 2730, 1536, (17, 17, 19)
# The phone's canvas of mockup3.py, where it was.
OX = 0
# The Mac recording: 2880 x 1960 pixels, the window's 2560 x 1640 from (160, 160), its shadow round it.
# Its top left corner level with the phone's body, a gap after the phone; ZOOM canvas pixels to one
# recorded (two to a point at ZOOM 1). Only what falls on the canvas is cut out and scaled.
ZOOM = float(sys.argv[sys.argv.index("--zoom") + 1]) if "--zoom" in sys.argv else 1.5
WX, WY = 1060, 124.7
cx0, cy0 = int(160 - 120 / ZOOM), max(int(160 - WY / ZOOM), 0)
cx1, cy1 = min(int(160 + (CW - WX) / ZOOM) + 2, 2880), min(int(160 + (CH - WY) / ZOOM) + 2, 1960)
MW, MH = round((cx1 - cx0) * ZOOM), round((cy1 - cy0) * ZOOM)
MX, MY = round(WX + (cx0 - 160) * ZOOM), round(WY + (cy0 - 160) * ZOOM)
# Apple's bezel over the drawn phone: its body (29..1440 by 21..2978 of 1470 x 3000) on the drawing's.
S = 0.3815
BX, BY = OX + 380.6, 116.7
bezel = Image.open(bezel_png).convert("RGBA")
bezel = bezel.resize((round(1470 * S), round(3000 * S)), Image.LANCZOS)
SX, SY = round(BX + 75 * S), round(BY + 66 * S)
SW, SH, SR = round(1320 * S), round(2868 * S), 245 * S
mask = Image.new("L", (SW * 4, SH * 4), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, SW * 4 - 1, SH * 4 - 1), radius=SR * 4, fill=255)
mask = mask.resize((SW, SH), Image.LANCZOS)
PT = SW / 402
# Where the drawing's thumb pad is, in screen points.
PAD = (36.6, 445.5)
hand = Image.open(hand_png).convert("RGBA")
FPS = 60

path = [(34, 764, 0), (34, 764, 650), (38, 740, 80), (44, 710, 80), (50, 680, 80), (56, 655, 80), (60, 644, 80),
        (60, 644, 800), (64, 620, 80), (68, 600, 80), (70, 584, 80), (70, 584, 800), (72, 560, 80), (74, 540, 80),
        (75, 524, 80), (75, 524, 800), (74, 545, 80), (72, 565, 80), (70, 584, 80), (70, 584, 700)]
times, t = [], 0.0
for _, _, dt in path:
    t += dt / 1000
    times.append(t)
times = [x - times[0] for x in times]
anchors = [(0.0, 0.02), (0.35, 0.37), (0.75, 0.52), (0.91, 0.64), (1.95, 1.77), (2.99, 2.92), (4.05, 4.07), (4.87, 5.15)]
LIFT = anchors[-1][1]


def touch_pt(vt):
    pt = float(np.interp(vt, [a[1] for a in anchors], [a[0] for a in anchors]))
    return float(np.interp(pt, times, [p[0] for p in path])), float(np.interp(pt, times, [p[1] for p in path]))



# The loop: LEAD seconds of the first frame while the hand comes in and rests; the recordings from 0 to HOLD
# (the phone's Instagram has loaded by then); then OUTRO seconds back to the first frame.
LEAD, HOLD, OUTRO = 1.0, 9.2, 0.7

# The long press: both recordings held EXTRA seconds from T0, just after the thumb lands (the Mac's
# pointer is still off the frame then), so the press lasts long enough to read as a hold.
T0, EXTRA = 0.06, 0.6
TOTAL = round((LEAD + HOLD + EXTRA + OUTRO) * FPS)


def source_time(u):
    """The recordings' time at u seconds into the main part."""
    return u if u < T0 else max(T0, u - EXTRA)


def ease_out(k):
    k = min(max(k, 0), 1)
    return 1 - (1 - k) ** 3


def smooth(k):
    k = min(max(k, 0), 1)
    return k * k * (3 - 2 * k)


# Of the lead, how long the hand takes to come in, to just short of the button, where it rests;
# in its last APPROACH seconds the thumb goes onto the button.
COME_IN, APPROACH = 0.6, 0.15
REST = (-16, 20)


def lead_pose(t):
    """The hand's offset from where it presses, and its opacity, t seconds into the lead."""
    if t < COME_IN:
        e = ease_out(t / COME_IN)
        return -50 + (50 + REST[0]) * e, 60 + (REST[1] - 60) * e, e
    k = smooth((t - (LEAD - APPROACH)) / APPROACH)
    return REST[0] * (1 - k), REST[1] * (1 - k), 1.0


# The Mac pointer's path (pointer.swift), in screen points, on the same clock as the phone.
def _mj(u):
    u = min(max(u, 0), 1)
    return u ** 3 * (10 - 15 * u + 6 * u * u)


def _move(a, b, u, bow):
    s = _mj(u)
    ddx, ddy = b[0] - a[0], b[1] - a[1]
    n = max(np.hypot(ddx, ddy), 1)
    side = bow * np.sin(np.pi * s)
    return a[0] + ddx * s - ddy / n * side, a[1] + ddy * s + ddx / n * side


def mac_pointer(t):
    g1, ig2, ig3 = (854, 391), (771, 395), (767, 393)
    if t < 4.07:
        return _move(g1, ig2, (t - 3.85) / 0.22, -4) if t >= 3.85 else None
    if t < 4.95:
        s = 0.5 - 0.5 * np.cos(np.pi * min((t - 4.07) / 0.88, 1))
        return ig2[0] + (ig3[0] - ig2[0]) * s, ig2[1] + (ig3[1] - ig2[1]) * s
    return ig3


def mac_canvas(p):
    """A point on the screen, in screen points, where it shows on the canvas: the recording was of
    the rect from (560, 206) at two pixels a point, the window's corner 160 pixels in."""
    return WX + ((p[0] - 560) * 2 - 160) * ZOOM, WY + ((p[1] - 206) * 2 - 160) * ZOOM


TOUCH_DOWN, LIST_OPENS = anchors[0][1], anchors[1][1]
CLICK_DOWN, CLICK_UP = 5.03, 5.15
SS = 3  # the bursts are drawn three times larger, then reduced: smooth lines
BURST = 0.4


def burst_lines(draw, cx, cy, k, radius, length, angles):
    """Three short strokes out from (cx, cy) at angles (degrees, y down), k seconds into a burst
    of BURST: they shoot out and fade, in the hand's own line colour."""
    u = k / BURST
    if not 0 <= u < 1:
        return
    inner = radius + length * 0.9 * ease_out(u)
    outer = radius + length * 0.35 + length * 1.1 * ease_out(min(u * 1.6, 1))
    alpha = 1 - smooth((u - 0.35) / 0.65)
    for a in angles:
        c, s_ = np.cos(np.radians(a)), np.sin(np.radians(a))
        p0 = ((cx + c * inner) * SS, (cy + s_ * inner) * SS)
        p1 = ((cx + c * outer) * SS, (cy + s_ * outer) * SS)
        w = round(3.2 * SS)
        draw.line([p0, p1], fill=(*LINE, round(240 * alpha)), width=w)
        for q in (p0, p1):
            draw.ellipse((q[0] - w / 2, q[1] - w / 2, q[0] + w / 2, q[1] + w / 2), fill=(*LINE, round(240 * alpha)))


# Larger than the button and past the phone's edge: a mark over the picture, not a part of the app.
ARC = 120


def presses(vt, u):
    """The layer of the presses, or None; vt on the recordings' clock, u on the main part's. While
    the thumb holds the pinned button an arc round its tip fills, in the hand's own line; when it is
    full the list opens and lines burst out. Lines burst again as the thumb lifts on Instagram, and
    from the Mac pointer's tip on its click, each on the side away from the hand or the pointer."""
    arcs, bursts = [], []
    u_open = LIST_OPENS + EXTRA
    if TOUCH_DOWN <= u < u_open + 0.2:
        x, y = touch_pt(TOUCH_DOWN)
        fill = min((u - TOUCH_DOWN) / (u_open - TOUCH_DOWN), 1)
        fade = ease_out((u - TOUCH_DOWN) / 0.1) if u < u_open else 1 - smooth((u - u_open) / 0.2)
        arcs.append((SX + x * PT, SY + y * PT, ARC, fill, fade))
    # The thumb comes from the lower left: its lines go up and to the right.
    if 0 <= u - u_open < BURST:
        x, y = touch_pt(TOUCH_DOWN)
        bursts.append((SX + x * PT, SY + y * PT, u - u_open, ARC + 10, 26, (-105, -60, -15)))
    if 0 <= vt - LIFT < BURST:
        x, y = touch_pt(LIFT)
        bursts.append((SX + x * PT, SY + y * PT, vt - LIFT, 46, 22, (-105, -60, -15)))
    # The arrow points up and to the left: its lines go that way.
    if 0 <= vt - CLICK_DOWN < BURST:
        mx, my = mac_canvas(mac_pointer(CLICK_DOWN))
        bursts.append((mx, my, vt - CLICK_DOWN, 22, 20, (-170, -125, -80)))
    if not bursts and not arcs:
        return None
    x0 = int(min(b[0] for b in bursts + arcs)) - 120
    y0 = int(min(b[1] for b in bursts + arcs)) - 120
    x1 = int(max(b[0] for b in bursts + arcs)) + 120
    y1 = int(max(b[1] for b in bursts + arcs)) + 120
    big = Image.new("RGBA", ((x1 - x0) * SS, (y1 - y0) * SS), (0, 0, 0, 0))
    g = ImageDraw.Draw(big)
    w = round(3.2 * SS)
    for cx, cy, r, fill, fade in arcs:
        cx, cy, r = (cx - x0) * SS, (cy - y0) * SS, r * SS
        box = (cx - r, cy - r, cx + r, cy + r)
        # The whole ring faint, what has filled bright, from the top, clockwise; round ends.
        g.ellipse(box, outline=(*LINE, round(60 * fade)), width=w)
        if fill > 0:
            end = -90 + 360 * fill
            g.arc(box, -90, end, fill=(*LINE, round(240 * fade)), width=w)
            for a in (-90, end):
                ex = cx + (r - w / 2) * np.cos(np.radians(a))
                ey = cy + (r - w / 2) * np.sin(np.radians(a))
                g.ellipse((ex - w / 2, ey - w / 2, ex + w / 2, ey + w / 2), fill=(*LINE, round(240 * fade)))
    for cx, cy, k, radius, length, angles in bursts:
        burst_lines(g, cx - x0, cy - y0, k, radius, length, angles)
    return big.resize((x1 - x0, y1 - y0), Image.LANCZOS), (x0, y0)


back = Image.new("RGBA", (CW, CH), BG + (255,))


def frame_at(screen, mac, vt, hand_in=None, u=None):
    """vt on the recordings' clock, u on the main part's; hand_in, in the lead, the hand's offset
    and opacity (lead_pose)."""
    canvas = back.copy()
    canvas.paste(mac, (MX, MY))
    canvas.paste(screen.resize((SW, SH), Image.LANCZOS), (SX, SY), mask)
    canvas.alpha_composite(bezel, (round(BX), round(BY)))
    mark = presses(vt, vt if u is None else u) if hand_in is None else None
    if mark:
        canvas.alpha_composite(mark[0], mark[1])
    x, y = touch_pt(min(max(vt, 0), LIFT))
    # The hand slides along the phone's edge to the touch; across, most of the way, so what comes
    # out from behind the phone stays on its bezel.
    dx, dy = 0.7 * (x - PAD[0]) * PT, (y - PAD[1]) * PT
    alpha = 1.0
    if hand_in is not None:
        # Coming in the way it leaves, the other way round.
        dx, dy, alpha = dx + hand_in[0], dy + hand_in[1], hand_in[2]
    elif vt > LIFT:
        e = ease_out((vt - LIFT) / 0.35)
        dx, dy, alpha = dx - 50 * e, dy + 60 * e, 1 - e
    if alpha > 0:
        layer = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
        layer.paste(hand, (round(OX + dx), round(dy)))
        if alpha < 1:
            arr = np.asarray(layer).astype(np.float32)
            arr[..., 3] *= alpha
            layer = Image.fromarray(arr.astype(np.uint8), "RGBA")
        canvas.alpha_composite(layer)
    if dot:
        tx, ty = SX + x * PT, SY + y * PT
        ImageDraw.Draw(canvas).ellipse((tx - 6, ty - 6, tx + 6, ty + 6), fill=(255, 40, 40, 255))
        p = mac_pointer(vt)
        if p:
            mx, my = mac_canvas(p)
            ImageDraw.Draw(canvas).ellipse((mx - 5, my - 5, mx + 5, my + 5), fill=(40, 255, 40, 255))
    return canvas.convert("RGB")


RW, RH = 1206, 2622
reader = subprocess.Popen(["ffmpeg", "-v", "error", "-i", raw, "-t", str(HOLD + OUTRO + 0.5), "-vf", f"fps={FPS}",
                           "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
mac_reader = subprocess.Popen(["ffmpeg", "-v", "error", "-ss", str(offset), "-i", mac_mov, "-t", str(HOLD + OUTRO + 0.5),
                               "-vf", f"fps={FPS},crop={cx1 - cx0}:{cy1 - cy0}:{cx0}:{cy0},scale={MW}:{MH}:flags=lanczos",
                               "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
screen = mac = None


def next_frames():
    """Both recordings' next frames; the last again for one that has run out."""
    global screen, mac
    data = reader.stdout.read(RW * RH * 3)
    if len(data) == RW * RH * 3:
        screen = Image.frombytes("RGB", (RW, RH), data)
    data = mac_reader.stdout.read(MW * MH * 3)
    if len(data) == MW * MH * 3:
        mac = Image.frombytes("RGB", (MW, MH), data)
    return screen, mac


writer = None
if not still:
    writer = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{CW}x{CH}",
                               "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18",
                               "-movflags", "+faststart", out], stdin=subprocess.PIPE)
first_screen, first_mac = next_frames()
# Where the loop starts and ends: the recordings' first frames, no hand.
first = np.asarray(frame_at(first_screen, first_mac, 0.0, hand_in=lead_pose(0.0))).astype(np.float32)
lead_frames, main_frames = round(LEAD * FPS), round((HOLD + EXTRA) * FPS)
read = 0  # the recordings' frames read past the first
for n in range(TOTAL):
    t = n / FPS
    u = (n - lead_frames) / FPS
    # Read on to the recordings' frame for this one; none while they are held.
    while n >= lead_frames and read < round(source_time(u) * FPS):
        next_frames()
        read += 1
    if still and t < still[0] - 1e-9:
        continue
    if n < lead_frames:
        frame = frame_at(first_screen, first_mac, 0.0, hand_in=lead_pose(t))
    else:
        frame = frame_at(screen, mac, read / FPS, u=u)
        if n >= lead_frames + main_frames:
            # Back to the first frame, ending on it exactly.
            k = smooth((n - lead_frames - main_frames) / (TOTAL - 1 - lead_frames - main_frames))
            frame = Image.fromarray((np.asarray(frame).astype(np.float32) * (1 - k) + first * k).round().astype(np.uint8))
    if still:
        frame.save(still[1])
        break
    writer.stdin.write(frame.tobytes())
reader.kill()
mac_reader.kill()
if writer:
    writer.stdin.close()
    writer.wait()
print("frames", TOTAL, "seconds", TOTAL / FPS)
